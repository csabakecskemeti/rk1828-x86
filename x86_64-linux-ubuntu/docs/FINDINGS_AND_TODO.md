# RK1828 on x86 Linux — Findings & TODO

> **Note:** these are the original working notes. Paths refer to the original folder layout (`~/Documents/workspace/RK1828-test/…`). See the mapping table in [`../README.md`](../README.md) for where each item lives in this repo.

_Last updated: 2026-11-07 (end of day 1)_

## ✅ STATUS 2026-11-08: WORKING

Qwen3-1.7B (w4a16, `RKNNAI/RK182X-LLM-Qwen3-1.7B`, 32k ctx config) runs on the RK1828 from this x86 host.

| Metric (`--bench 128 128`) | Value |
|---|---|
| Prefill | **1220 tok/s** (0.82 ms/token) |
| Generate | **99 tok/s** (10.1 ms/token) |
| TTFT (128-token prompt) | 105 ms |
| Model load (1.7 GB over Gen2 x1) + run | ~11 s wall total |

### Working bring-up procedure (after every power-on)
1. External power on the card **connected before boot**.
2. `cd ~/Documents/workspace/RK1828-test && sudo ./rk1828-up.sh`. It:
   - finds the card by `1d87:182a` (never a fixed address)
   - sets its IOMMU group to `identity` (only if the card is alone in the group)
   - loads `pcie-rkep`
   - runs `pcie_upgrade_tool uf <m2-2280.img> -reset`: exit 0 = loaded from boot ROM, then waits
     `FW_WAIT` (90 s); exit 234 = firmware already running, OK
   - starts the proxy. Output goes to `rk1828-up.log` and `fw-load.log`.
3. Run models as a normal user with `rknn3_llm_cli` (see TODO for the command).

Key facts learned on day 2:
- The card does **not** boot its eMMC firmware on its own at power-on. The host must run
  `pcie_upgrade_tool uf … -reset` every time (same as Rockchip's `rknn3_startup`).
- After the firmware boots, the driver logs `update magic=524b4550, ver=2`: the status block moves
  (`bar0_reserved=0x58000`). Reading BAR0 offset 0 is **not** a valid firmware check (reads `0x1f4`).
- After a fresh firmware load the card needs roughly 1–2 minutes before the proxy can use it. Starting
  the proxy too early was the likely cause of day 1's post-flash hang.
- With no device in its slot (external power off), the BIOS hides the root port and PCI addresses
  shift. On this box `0000:01:00.0` then becomes the X710 NIC.

## TL;DR — where we were (end of day 1)

- Host side is **done and working**: kernel driver, proxy, runtime libs, chat CLI, model.
- Root cause of all hangs found: **the card had no running firmware**. Fixed by flashing Rockchip's
  M.2 firmware into the card's eMMC with `pcie_upgrade_tool` (2280 image).
- After the flash the card reports a **valid status block** (`magic=524b4550` "RKEP", `ep_cc_version=30300`,
  real BAR addresses) — firmware is running.
- Generation **still hung once after the flash**, with 0 interrupts. Most likely reason: the driver was
  loaded *before* the firmware reset, so the card's `irq_rc_msi_en` flag (written by the driver at probe)
  was wiped. **Next step: full cold power cycle, then `sudo ./rk1828-up.sh`, then test.**

## Hardware / system

| Item | Value |
|---|---|
| Host | AMD Threadripper PRO 7965WX (24c/48t), 1 TB RAM, Ubuntu 26.04.1, kernel 7.0.0-38-generic |
| GPUs (not used for this) | RTX PRO 6000 Blackwell, RTX 5090 |
| Accelerator | Rockchip RK1828 M.2 module, PCI `1d87:182a`, at `0000:01:00.0` |
| Mounting | GLOTRENDS M.2→PCIe x4 adapter + OwlTree 30 cm M.2 extender cable |
| PCIe link | **5.0 GT/s x1 (Gen2 x1)** — this is the card's own max (`max_link_speed`), not the slot |
| IOMMU | AMD-Vi on; card alone in **IOMMU group 33** |
| Secure Boot | disabled (unsigned module loads fine) |
| Card power | **external power supply** (plus slot). Must be connected at boot — without it the card is invisible and the BIOS hides its root port. A true cold reset = PSU off AND external power off. |

## Software stack (all in `~/Documents/workspace/RK1828-test/`)

| Path | What |
|---|---|
| `pcie-rkep/` | Rockchip `pcie-rkep` kernel driver (from `rockchip-linux/kernel` `develop-6.1`, DRV_VERSION 0x30301), ported to kernel 7.0. Build: `make`. Originals kept as `*.orig`. |
| `rknn3-toolkit/` | `airockchip/rknn3-toolkit` **v1.2.0** (git clone). Proxy: `rknn3-runtime/rknn3_transfer_proxy/linux-x86_64/`. Libs: `rknn3-runtime/rknn3-api/Linux/x86_64/`. Docs extracted to text in `doc/EN/*.txt`. |
| `rknn3-toolkit/rknn3-runtime/examples/rknn3_llm_cli/install/rknn3_llm_cli_x86_64/` | Built x86 `rknn3_llm_cli` (+ `rknn3_llm_step_decode`). |
| `rknn3-model-zoo/` | `airockchip/rknn3-model-zoo` (conversion scripts; not needed now). |
| `models/RK182X-LLM-Qwen3-1.7B/Qwen3-1.7B-w4a16-8-32256/` | Pre-converted Qwen3-1.7B (w4a16 GRQ, 8 cores, 32k ctx, fp16 KV). SHA256 verified. Built for runtime v1.1.0. |
| `models/Qwen3-1.7B/` | Original HF weights (4 GB) — **not needed, can delete**. |
| `rk182x-host-pkg/` | Rockchip's official packages from their Lenovo share: `rknn3-rk182x-sodimm_v1.2.0_x86_64.deb`, M.2 arm64 debs, extracted x86 deb (`x86-extracted/`), and firmware images in `firmware/`. |
| `rk1828-up.sh` | Bring-up script: IOMMU identity → insmod driver → start proxy → list devices. Run with sudo. |
| `rk-ep-state.py` | Read-only dump of the card's status block (BAR0 offset 0). `sudo python3 rk-ep-state.py` |
| `rk-smi/` | Small `nvidia-smi`-like tool (`./rk-smi`, `-l N` loop, `-n` no runtime context). |
| `proxy.log`, `proxy-fg.log`, `gen.log`, `bench.log` | Logs from today's runs. |
| conda env `rknn3` | Python 3.12 + `rknn3_toolkit-1.2.0` (imports as `rknn.api`) + transformers. Only for model conversion. |

## Key findings

### 1. The card needs firmware; host must provide it
- Fresh card: BAR0 status block was **random uninitialized memory** (`devmode=40349`, BAR addrs `0xffff…`).
  PCIe enumerates fine, but nothing runs on the card → proxy waits forever at `wait ep create....`.
- Rockchip's **official x86 host package** (`rknn3-rk182x-sodimm_v1.2.0_x86_64.deb`, released 2026-11-07)
  runs `rknn3_startup` before the proxy, which does:
  ```
  pcie_upgrade_tool ld
  pcie_upgrade_tool -s <addr> uf /usr/lib/firmware/rknn3_rk1820.img -reset
  ```
  (`uf` = "Write firmware into emmc".) Rockchip runs this on **every service start**.
- Firmware is **board-specific**. Images (md5):
  | File | For | md5 |
  |---|---|---|
  | `firmware/rknn3_rk1820_m2-2280.img` | M.2 2280 | 45dd70f4… |
  | `firmware/rknn3_rk1820_m2-2242.img` | M.2 2242 | dbe9ebca… |
  | `firmware/rknn3_rk1820_sodimm.img` | SODIMM (shipped in x86 deb) | 8f83b139… |
- **We flashed the 2280 image** — card length **confirmed 2280** by the user. Flash log: bootloader loaded
  (boot state `0x4c42`), wrote idb, gpt, `subsoc_os`, `node2_os`, `node4_os`, reset OK.
- Wrong image reportedly hangs the card in DDR init until a **full cold power cycle** (PSU off).
  A PCI remove/rescan or warm reboot does **not** reset the chip.

### 2. After flashing, card status is valid
Proxy log after flash:
```
magic=524b4550, ver=2      (was 18 / d01ec828 = garbage)
rc_cc_version=30301  ep_cc_version=30300
bar0_phy_addr=0x1200058000 bar1=0x1200068000 bar2=0x1200000000 bar5=0x1200070000
```

### 3. Why it still hung after flash (hypothesis, to verify)
- `pcie-rkep` sets `obj_info->irq_rc_msi_en = 1` at **probe** (pcie-rkep.c ~line 1627) — this tells the card
  it may raise MSIs to the host. Our driver probed at boot (when the card had no firmware); the firmware
  reset afterwards wiped the flag, and there was no re-probe. → card never interrupts → hang.
- Fix: cold boot (card firmware boots from eMMC first, then driver loads), or stop proxy → unbind/rebind
  driver.

### 4. Host-side facts
- Our driver port == Rockchip's official DKMS `pcie-rkep` 3.3.1 functionally. Official Makefile also adds
  `-DCONFIG_NO_GKI` (enables sysfs `rkep` firmware-load attribute) — optional.
- The proxy in the official x86 deb is **byte-identical** to the rknn3-toolkit `linux-x86_64` one (v1.2.0, d9457bb6).
- Driver has **no PCI alias** (upstream `MODULE_DEVICE_TABLE(pcie_rkep, …)` typo) → never autoloads; `insmod` manually.
- `/dev/pcie-rkep-*` is root-only → proxy must run as root; clients (CLI, rk-smi) can run as normal user.
- Proxy creates abstract unix sockets `@transfer_proxy3_native` and `@transfer_proxy3_native_<hash>` plus TCP
  127.0.0.1:18898 / 18821. A stale owner of these sockets blocks every new proxy/client.
- Proxy **ignores SIGTERM** when stuck → use `kill -9`.
- Proxy process name is truncated to `rknn3_transfer_` — use `pgrep -x rknn3_transfer_`, not `pgrep -f`
  (that also matches `sudo` wrappers).
- `RKNN_LOG_LEVEL=5` on the client shows where `rknn3_init` stops.
- Interrupt check: `grep rkep /proc/interrupts` — 4 MSI vectors (IR-PCI-MSI). Must go above 0 when working.
- No IOMMU page faults were ever logged; IOMMU passthrough (`identity`) did not fix the hang (firmware was the
  real issue). Keeping `identity` is harmless; may or may not be needed.
- Official x86 deb also ships `rknn-smi` + `librknnsmi.so` (real nvidia-smi equivalent: health, memory, etc.).

### 5. Models
- **RKNNAI** org on Hugging Face hosts pre-converted RK1828/RK182X models (`RKNNAI/RK182X-LLM-*`, `RK1828-LLM-*`).
- Single card ceiling ≈ 8–9B (e.g. `RK1828-LLM-Qwen3-8B`, `RK1828-LLM-Qwen3.5-9B`).
- `RK1828-LLM-Qwen3.5-35B-A3B` needs **5 cards** (split into 5 × ~4.4 GB segments) — not usable with one card.
- Pre-converted models are tagged runtime v1.1.0; v1.2.0 runtime expected to be compatible but not yet verified
  (a hard version mismatch gives an explicit `RKNN3 VERSION UNMATCH!` error, not a hang).

## TODO (in order)

1. **Cold power cycle**: shut down, PSU off / unplug, wait ~10 s, boot.
2. `cd ~/Documents/workspace/RK1828-test && sudo ./rk1828-up.sh`
   - check `proxy.log` shows `magic=524b4550`
3. Run single generation (as normal user):
   ```bash
   cd ~/Documents/workspace/RK1828-test/rknn3-toolkit/rknn3-runtime/examples/rknn3_llm_cli/install/rknn3_llm_cli_x86_64
   RKNN_LOG_LEVEL=3 ./rknn3_llm_cli \
     --model ~/Documents/workspace/RK1828-test/models/RK182X-LLM-Qwen3-1.7B/Qwen3-1.7B-w4a16-8-32256/Qwen3-1.7B.rknn \
     --core-mask 0xff -n 128 --prompt "Explain what an NPU is in two sentences." --once
   ```
   In another terminal: `watch -n1 'grep rkep /proc/interrupts'` — counts must rise.
4. If still hanging with 0 IRQs after cold boot:
   - `sudo python3 rk-ep-state.py` → check `irq_rc_msi_en` (should be 1) and `devmode`.
   - Try stop proxy (`kill -9`) → `echo 0000:01:00.0 | sudo tee /sys/bus/pci/drivers/pcie-rkep/unbind` →
     `…/bind` → start proxy. **Never unbind while a proxy holds the device.**
   - Try the official x86 deb's full flow (its `rknn3_startup` = flash + reset on every start, with its own
     `pcie_upgrade_tool`, `rknn-smi`, `librknn3_api.so`), but swap in the M.2 firmware image.
   - Card length is confirmed 2280, so the firmware image is correct (no need to try `m2-2242`).
   - Compare with community x86 setup: <https://github.com/Riconec/rk1828-x86-linux> (Debian 13, kernel 6.12,
     M.2 card, ~64 tok/s Gemma4 E2B). Its `scripts/probe-bar0.py` and `docs/troubleshooting.md`.
5. Once working:
   - Benchmark: `./rknn3_llm_cli --model … --bench 128 128`
   - Run `rknn-smi` from `rk182x-host-pkg/x86-extracted/usr/bin/` (health / memory / versions).
   - Try bigger models: `RKNNAI/RK1828-LLM-Qwen3-8B`, `RKNNAI/RK1828-LLM-Qwen3.5-9B`, `RK182X-LLM-Qwen3-4B-Instruct-2507`.
   - Start `rkllm3-server` (x86 binary in `rknn3-toolkit/rknn3-runtime/rkllm3-server/bin/linux-x86_64/`) for an
     OpenAI-compatible API.
6. Make it persistent:
   - udev rule for `/dev/pcie-rkep-*` permissions (optional; proxy runs as root anyway).
   - systemd unit (like official `rknn3.service`): insmod → (optional firmware load) → proxy.
   - If IOMMU identity turns out to be required: kernel param `iommu=pt` or keep it in the startup script
     (must be set **before** the driver binds).
   - Or install the official deb (DKMS driver) with the M.2 firmware swapped in.
7. Cleanup: delete `models/Qwen3-1.7B/` (4 GB, unused); remove conda env `rknn3` if no conversion planned.

## Sources
- rknn3-toolkit: <https://github.com/airockchip/rknn3-toolkit> (issue #22: x86 request; issue #24: version mismatch error)
- Rockchip firmware/host packages share: <https://console.box.lenovo.com/l/PHk0PF> (`RK1820_RK1828/RELEASE_V1.2.0/`)
- Rockchip kernel (pcie-rkep): <https://github.com/rockchip-linux/kernel> branch `develop-6.1`
- Pre-converted models: <https://huggingface.co/RKNNAI>
- Community x86 setup: <https://github.com/Riconec/rk1828-x86-linux>
- DFRobot RK1828 guide (expected healthy `rknn-smi` output): <https://wiki.dfrobot.com/dfr1263/docs/24734>
- Forlinx guide: <https://docs.forlinx.net/ai-accelerator/rk1820_rk1828/RK1820_RK1828_AI_Accelerator_Development_Guide.html>

## Final target: Orange Pi 5 Plus (ARM, Ubuntu)

This x86 workstation is only the **test bench**. The final installation is an **Orange Pi 5 Plus** (RK3588 SoC,
aarch64, Ubuntu). Goal right now: get the card working here first, then move it.

Why that should be easier:
- RK3588 is an **officially supported RK182x host** (Rockchip's docs and examples are written for RK3588 + RK182x).
- The OPi5+ has an M.2 M-key slot (PCIe 3.0 x4) on the board, so the card fits directly, without adapter or
  extender.
- Rockchip's **arm64 M.2 host package is already downloaded**: `rk182x-host-pkg/rknn3-rk182x-m2_v1.2.0_arm64.deb`.
  It contains the DKMS `pcie-rkep` driver, `pcie_upgrade_tool`, `rknn-smi`, proxy, `rkllm3-server`, `rknn3_llm_cli`,
  the M.2 2280 firmware, and the `rknn3.service` startup flow.
- The firmware is already on the card's eMMC (flashed 2026-11-07), and it is board-specific (M.2 2280), not
  host-specific. Rockchip's startup script still re-flashes on every service start.

Things to check when moving it:
- Whether the OPi5+ Ubuntu kernel (Rockchip BSP 5.10/6.1, or mainline) already has `CONFIG_PCIE_FUNC_RKEP`.
  If not, use the deb's DKMS driver (needs kernel headers for the OPi kernel).
- Whether the M.2 slot powers or resets the card properly at boot (Rockchip boards use `npu_powerctrl`).
- The models and lessons from this bench carry over unchanged (same runtime v1.2.0, same `.rknn` files).
