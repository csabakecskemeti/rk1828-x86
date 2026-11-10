# RK1828 on x86 Linux — What we tried that did NOT work (and why)

> **Note:** these are the original working notes. Paths refer to the original folder layout (`~/Documents/workspace/RK1828-test/…`). See the mapping table in [`../README.md`](../README.md) for where each item lives in this repo.

_2026-11-07. Read this before repeating any step._

Each entry lists what we did, what happened, and the conclusion.

## 1. Running the stack without loading card firmware
- **Did:** built and loaded `pcie-rkep`, started `rknn3_transfer_proxy`, ran `rknn3_llm_cli` (bench and single prompt).
- **Result:** `proxy devices` lists the card, but every client hangs at
  `rknn3_init, try connect device: 0000:01:00.0`. Proxy stops at `wait ep create....`. Zero MSI interrupts.
- **Conclusion:** PCIe enumeration doesn't prove the card is alive. The card shipped with no running
  firmware: its BAR0 status block held random values (`devmode=40349`, BAR addresses `0xffffffffffffffff`,
  magic `0x18`). **Root cause.** Fixed by flashing firmware (see FINDINGS_AND_TODO.md).

## 2. Waiting longer ("M.2 is slow, loading takes time")
- **Did:** waited up to 10 minutes on bench and generation runs.
- **Result:** no progress, 0% CPU on client and proxy, interrupt counters stayed at 0.
- **Conclusion:** a slow transfer would still produce interrupts. Zero interrupts means nothing is moving.
  Gen2 x1 (~400–500 MB/s) loads 1.7 GB in seconds, so long waits are pointless.

## 3. IOMMU passthrough (identity domain) as the fix
- **Did:** set IOMMU group 33 to `identity` via sysfs (unbind, set type, rebind).
- **Result:** still hung. No `AMD-Vi IO_PAGE_FAULT` was ever logged, before or after.
- **Conclusion:** the IOMMU was not the cause. `rk1828-up.sh` still sets `identity` (harmless, maybe
  needed later). Not proven necessary.

## 4. Unbinding/rebinding the driver while a proxy was running ⚠️
- **Did:** `sudo pkill rknn3_transfer` (didn't actually kill it), then unbind/rebind `pcie-rkep`.
- **Result:** the old proxy got stuck in state `X` (dying but never finishing) inside the kernel. It kept
  holding the abstract socket `@transfer_proxy3_native_b98e6c51`, whose accept queue was full. Every new
  proxy logged `Address already in use` or `failed to start API front proxy listener, ret=-6`. Every
  client blocked in `unix_wait_for_peer`. Only a **reboot** cleared it.
- **Conclusion:** **never unbind or rmmod the driver while any proxy has the device open.** Always confirm
  the proxy is gone first (`pgrep -x rknn3_transfer_` returns nothing).

## 5. `pkill rknn3_transfer` / `kill <pid>` to stop the proxy
- **Result:** didn't stop it. A proxy stuck waiting on the card ignores SIGTERM.
- **Conclusion:** use `sudo kill -9 <pids>`. Find the PIDs with `pgrep -ax rknn3_transfer_`.

## 6. `pgrep -f rknn3_transfer_proxy` to detect a running proxy
- **Result:** matched leftover `sudo stdbuf … rknn3_transfer_proxy` wrapper processes, so
  `rk1828-up.sh` wrongly said "proxy already running".
- **Conclusion:** fixed in the script to use `pgrep -x rknn3_transfer_` (process name, truncated to 15 chars).

## 7. Reading the proxy log redirected to a file
- **Result:** `nohup … > proxy.log` is block-buffered, so the log looked frozen at buffer creation and
  hid the real stopping point.
- **Conclusion:** for debugging, run the proxy in the foreground:
  `sudo stdbuf -oL -eL …/rknn3_transfer_proxy 2>&1 | tee proxy-fg.log`. That revealed `wait ep create....`.

## 8. `pkill -f '<pattern>'` from a shell whose own command line contains the pattern
- **Result:** the shell killed itself (exit 144) before running the next command.
- **Conclusion:** use `pkill -x <name>` or explicit PIDs.

## 9. Converting the model ourselves (export_llm.py)
- **Did:** started the rknn3-model-zoo Qwen3 export (downloaded HF Qwen3-1.7B, 4 GB).
- **Result:** abandoned, not failed. Also note: the export script forces
  `HF_ENDPOINT=https://hf-mirror.com/` (Chinese mirror), so download the model from HF first and pass
  a local path.
- **Conclusion:** unnecessary. **RKNNAI** on Hugging Face hosts pre-converted RK1828 models. The 4 GB in
  `models/Qwen3-1.7B/` can be deleted.

## 10. Qwen3.5-35B-A3B (`RKNNAI/RK1828-LLM-Qwen3.5-35B-A3B`)
- **Conclusion:** needs **5 cards** (5 × ~4.4 GB segments). Can't run on one RK1828. Single-card limit is
  about 8–9B.

## 11. rk-smi memory/version fields via `rknn3_find_devices`
- **Result:** returns the device ID and type, but **memory fields are all zero**. Version and core
  queries need a working `rknn3_init` (which hung, because there was no firmware).
- **Conclusion:** NPU utilization, temperature and clocks aren't in the public API. Use the official
  `rknn-smi` from the x86 deb (`rk182x-host-pkg/x86-extracted/usr/bin/`) once the firmware runs.
  `rk-smi -n` still works for driver, proxy and link status.

## 12. Generation right after flashing firmware (no cold boot, no driver re-probe)
- **Did:** flashed `m2-2280.img` with `pcie_upgrade_tool uf … -reset`, killed old proxies, started a new
  proxy with `rk1828-up.sh`, ran generation.
- **Result:** proxy now reads a valid card state (`magic=524b4550`, `ep_cc_version=30300`, real BAR
  addresses), but the client **still hung with 0 interrupts**.
- **Probable reason (not yet verified):** the driver had probed before the firmware reset. Its probe-time
  write of `irq_rc_msi_en=1` into the card's status block was wiped by the reset, so the card isn't
  allowed to send MSIs.
- **Next:** cold power cycle (PSU off), then `rk1828-up.sh` so the driver probes after the firmware is up.
  See FINDINGS_AND_TODO.md → TODO.

## Not tried yet (so don't assume they fail)
- Cold power cycle after the flash.
- Rebinding the driver after the flash (with no proxy running).
- The official x86 deb's complete flow (`rknn3_startup` + its own binaries and `rknn-smi`).
- ~~`m2-2242` image~~: not needed, the card is confirmed 2280.
- `rkllm3-server` on x86.

## 13. Day 2: card missing after cold boot + script touched the wrong device ⚠️
- **What happened:** after the cold power cycle the RK1828 was not on the PCI bus at all. The cause was
  the **card's external power was disconnected**. With no device in the slot, PCI numbering shifted and
  `0000:01:00.0` became port 1 of the workstation's **Intel X710** NIC. `rk1828-up.sh` had that address
  hard-coded, so it switched the NIC's IOMMU group to `identity` and **unbound its i40e driver**
  (`eno1np0` disappeared).
- **Restored with:** `echo DMA-FQ | sudo tee /sys/kernel/iommu_groups/32/type`, then
  `echo 0000:01:00.0 | sudo tee /sys/bus/pci/drivers/i40e/bind`.
- **Fixed in the script:** it now finds the card by vendor:device `1d87:182a`, never by a fixed address,
  and refuses to change an IOMMU group that contains any other device.
- **Lesson:** connect the card's external power before boot. A `pci rescan` cannot find it afterwards,
  because the BIOS hides the empty root port.
