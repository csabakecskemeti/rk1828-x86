# Running LLMs on a Rockchip RK1828 M.2 Accelerator from an x86 Linux PC

> **Note:** these are the original working notes. Paths refer to the original folder layout (`~/Documents/workspace/RK1828-test/…`). See the mapping table in [`../README.md`](../README.md) for where each item lives in this repo.

_Bring-up done 2026-11-07 → 2026-11-08. Result: Qwen3 / Qwen3.5 LLMs and a vision-language model running
fully on the RK1828, at up to ~95 tok/s (1.7B) and ~49 tok/s (8B)._

Related docs in this folder:
- [`TEST_RESULTS.md`](TEST_RESULTS.md): all benchmark numbers
- [`TRIED_AND_FAILED.md`](TRIED_AND_FAILED.md): every dead end, so you don't repeat them
- [`FINDINGS_AND_TODO.md`](FINDINGS_AND_TODO.md): detailed working notes and the open to-do list

---

## 1. The setup

### Hardware
| Part | Details |
|---|---|
| Accelerator | **Rockchip RK1828** M.2 2280 M-key module: 20 TOPS INT8 NPU (8 cores), **5 GB 3D-stacked DRAM** in package, PCI ID `1d87:182a` |
| Card power | **external power supply** on the card, plus slot power |
| Card link | PCIe **Gen2 x1** (5 GT/s). This is the card's own maximum, not a slot limit |
| Mounting | GLOTRENDS M.2 NVMe → PCIe 4.0 x4 adapter card + OwlTree 30 cm M.2 extender cable |
| Host | Threadripper PRO 7965WX workstation, 1 TB RAM, Ubuntu 26.04.1, kernel 7.0.0-38-generic, AMD-Vi IOMMU on, Secure Boot off |
| Not used | The NVIDIA GPUs (RTX PRO 6000, RTX 5090) are not involved in inference; verified with `nvidia-smi pmon` |

The workstation is only the **test bench**. The final target is an **Orange Pi 5 Plus** (RK3588, Ubuntu),
which is an officially supported RK182x host.

### Software (all in `~/Documents/workspace/RK1828-test/`)
| Component | Source / version |
|---|---|
| Kernel driver `pcie-rkep` | Rockchip vendor kernel (`rockchip-linux/kernel`, branch `develop-6.1`, DRV_VERSION 0x30301), **ported to kernel 7.0** → `pcie-rkep/` |
| RKNN3 SDK | [`airockchip/rknn3-toolkit`](https://github.com/airockchip/rknn3-toolkit) **v1.2.0**: `rknn3_transfer_proxy` (linux-x86_64), `librknn3_api.so`, `rkllm3-server`, docs → `rknn3-toolkit/` |
| Firmware + flasher | Rockchip's official host packages (v1.2.0, Lenovo Box share): `pcie_upgrade_tool` from the **x86_64** deb, **M.2 2280 firmware image** from the M.2 arm64 deb → `rk182x-host-pkg/` |
| Chat CLI | `rknn3_llm_cli` example, **built natively for x86_64** |
| Models | Pre-converted by [RKNNAI on Hugging Face](https://huggingface.co/RKNNAI) → `models/` |

### How the pieces fit
```
 rknn3_llm_cli / rkllm3-server  (normal user)
        │  unix socket @transfer_proxy3_native_<hash>
        ▼
 rknn3_transfer_proxy            (root)
        │  /dev/pcie-rkep-<BDF>  (ioctl, mmap of BARs, DMA buffers)
        ▼
 pcie-rkep.ko  ──PCIe Gen2 x1──►  RK1828 (firmware loaded by pcie_upgrade_tool)
```
- Model weights travel over the x1 link **once**, at load time (~10–25 s). After that, generation runs from the
  card's own memory, so the slow link doesn't limit tokens/s.
- The token embedding table (`*.embed.bin`) and the tokenizer stay on the host. Only the transformer
  weights and the KV cache sit on the card.

---

## 2. How we got it working (the short story)

1. **Card visible, but no driver.** `lspci` showed `1d87:182a` with no driver bound. The driver only exists in
   Rockchip's vendor kernel, so we took `pcie-rkep.c` from `develop-6.1` and built it out-of-tree. That
   needed three small changes for kernel 7.0: flattened include paths, `PCI_IRQ_LEGACY` → `PCI_IRQ_INTX`, and
   `MODULE_IMPORT_NS("…")` as a string.
2. **The SDK had just gained x86 support.** rknn3-toolkit **v1.2.0** added "Linux x86_64 coprocessor mode": an
   x86 proxy, runtime libs and server. The proxy listed the card, but every client **hung** at
   `rknn3_init` with **zero interrupts**.
3. **Wrong theories first.** We suspected the IOMMU (set passthrough: no change) and slow loading
   (zero interrupts = nothing moving). A driver unbind while the proxy was running even left an unkillable
   process, which needed a reboot. See `TRIED_AND_FAILED.md`.
4. **Root cause: no firmware on the card.** Dumping the card's BAR0 status block (`rk-ep-state.py`) showed
   random, uninitialized memory. Nothing was running on the RK1828.
5. **The missing piece.** A research pass found that Rockchip had released an official **x86_64 host package
   the same day**. Its startup script runs `pcie_upgrade_tool uf <firmware.img> -reset` **before** the proxy.
   The package ships only a SODIMM firmware image; the **M.2 2280 image** comes from the M.2 arm64 package
   (firmware images don't depend on the host architecture). The community project
   [Riconec/rk1828-x86-linux](https://github.com/Riconec/rk1828-x86-linux) confirmed the approach.
6. **Firmware flashed.** The status block became valid (`magic=524b4550` "RKEP", `ep_cc_version=30300`).
7. **Day 2 lessons.**
   - The card's **external power** must be connected before boot. Otherwise the BIOS hides its slot.
   - The card does **not** boot the firmware on its own at power-on. The host must load it on
     **every** start.
   - BAR0 offset 0 is not a valid "firmware running" check (it reads `0x1f4` even when running). Rely on the
     tool's own `magic=524b4550` output and its exit code (`234` = already running).
   - Never hard-code the PCI address: after one boot `0000:01:00.0` was a NIC, and the first version of our
     script unbound it.
8. **Success.** The firmware loaded, the proxy started, and Qwen3-1.7B generated at **~95 tok/s**. Then
   Qwen3-8B (~49 tok/s), Qwen3.5-4B (~33 tok/s, 68k context) and Qwen3.5-4B with vision via `rkllm3-server`.

---

## 3. Reproducible procedure

### 3.1 One-time preparation
```bash
cd ~/Documents/workspace/RK1828-test

# a) kernel driver (re-run after kernel updates)
cd pcie-rkep && make && cd ..

# b) SDK (already cloned) → rknn3-toolkit/ ; build the CLI for x86
cd rknn3-toolkit/rknn3-runtime/examples/rknn3_llm_cli && ./build-linux.sh -t x86 -a x86_64 -b Release && cd -

# c) firmware + flasher are in rk182x-host-pkg/ (extracted from Rockchip's v1.2.0 debs)
#    rk182x-host-pkg/x86-extracted/usr/bin/pcie_upgrade_tool
#    rk182x-host-pkg/firmware/rknn3_rk1820_m2-2280.img    (md5 45dd70f4…)

# d) models (example)
hf download RKNNAI/RK182X-LLM-Qwen3-1.7B --revision v1.1.0 \
   --include "Qwen3-1.7B-w4a16-8-32256/**" --local-dir models/RK182X-LLM-Qwen3-1.7B
# always verify: cd <config dir> && sha256sum -c SHA256SUMS
```

### 3.2 After every power-on
1. Make sure the card's **external power** is connected **before** booting.
2. Bring up the card:
   ```bash
   cd ~/Documents/workspace/RK1828-test && sudo ./rk1828-up.sh
   ```
   `rk1828-up.sh` does the following:
   - finds the card by `1d87:182a` and refuses to act if it isn't present;
   - sets its IOMMU group to `identity`, only if the card is alone in the group;
   - `insmod pcie-rkep.ko`;
   - runs `pcie_upgrade_tool -s <BDF> uf rknn3_rk1820_m2-2280.img -reset`:
     - exit `0`: firmware loaded from boot ROM, waits `FW_WAIT` (default 90 s);
     - exit `234`: firmware already running, continues;
   - starts `rknn3_transfer_proxy` as a daemon;
   - writes its output to `rk1828-up.log`, `fw-load.log` and `proxy.log`.
3. Check: `proxy.log` / `fw-load.log` show `magic=524b4550`.

### 3.3 Run a model (normal user)
```bash
cd ~/Documents/workspace/RK1828-test/rknn3-toolkit/rknn3-runtime/examples/rknn3_llm_cli/install/rknn3_llm_cli_x86_64

# one-shot
./rknn3_llm_cli --model ~/Documents/workspace/RK1828-test/models/RK1828-LLM-Qwen3.5-4B/Qwen3.5-4B-w4a16-8-68608-kv-int4/Qwen3.5-4B.rknn \
  --core-mask 0xff -n 1024 --prompt "Explain attention with an example." --once
# interactive chat: drop --prompt/--once
# benchmark:       --bench <n_in> <n_out>
```

### 3.4 OpenAI-compatible server with vision
```bash
cd ~/Documents/workspace/RK1828-test
nohup ./serve-qwen35-vl.sh > server.log 2>&1 &      # Qwen3.5-4B + vision, 127.0.0.1:8080
python3 ask.py "What is in this picture?" photo.jpg  # stdlib client, prints tok/s
pkill -f rkllm3-server                               # stop (card holds one model at a time)
```
Any OpenAI client or Open WebUI can use `http://127.0.0.1:8080/v1`.

### 3.5 Stopping / troubleshooting
- Stop the proxy: `sudo kill -9 $(pgrep -x rknn3_transfer_)`. It ignores SIGTERM when stuck.
- **Never** unbind or `rmmod` the driver while a proxy holds the device.
- Only one model fits on the card at a time. Close the CLI or server before starting another
  (`MODEL_SETUP fail, ack = ACK_FAIL` = card already occupied).
- Card missing from `lspci`: external power. `rescan` won't help, because the BIOS hides the empty root port.
- `RKNN_LOG_LEVEL=5` on the client shows exactly where it stops.
- Card status block dump: `sudo python3 rk-ep-state.py` (only meaningful before firmware relocation).

---

## 4. Files in this folder
| Path | Purpose |
|---|---|
| `rk1828-up.sh` | Bring-up after boot (driver → firmware → proxy) |
| `serve-qwen35-vl.sh` | Start `rkllm3-server` with Qwen3.5-4B + vision |
| `ask.py` | Minimal OpenAI-API client (text and image), prints speed |
| `rk-ep-state.py` | Read-only dump of the card's BAR0 status block |
| `rk-smi/` | Small status tool (driver, proxy, PCIe link). Rockchip's real `rknn-smi` is in `rk182x-host-pkg/x86-extracted/usr/bin/` |
| `pcie-rkep/` | Ported kernel driver (`*.orig` = Rockchip originals) |
| `rknn3-toolkit/`, `rknn3-model-zoo/` | Rockchip SDK and model zoo (git clones) |
| `rk182x-host-pkg/` | Rockchip v1.2.0 host debs, extracted x86 package, firmware images |
| `models/` | Downloaded RKNNAI models (`models/Qwen3-1.7B/` = unused original HF weights, deletable) |
| `bench-*.log`, `*.log` | Raw benchmark and run logs |

## 5. Moving to the Orange Pi 5 Plus (next)
- Use Rockchip's **arm64 M.2 package** (`rk182x-host-pkg/rknn3-rk182x-m2_v1.2.0_arm64.deb`). It contains the DKMS
  driver, `pcie_upgrade_tool`, `rknn-smi`, proxy, server, CLI, M.2 firmware and a systemd service that loads the
  firmware on every start.
- Put the card directly in the OPi5+ M.2 M-key slot. Keep the external power.
- Check whether the OPi Ubuntu kernel already has `CONFIG_PCIE_FUNC_RKEP`; otherwise use the deb's DKMS driver.
- Models, SDK version (v1.2.0) and everything learned here carry over.

## 6. Credits / sources
- Rockchip RKNN3 SDK: <https://github.com/airockchip/rknn3-toolkit>
- Rockchip vendor kernel (pcie-rkep): <https://github.com/rockchip-linux/kernel> (`develop-6.1`)
- Rockchip RK1820/RK1828 release share (firmware, host packages): <https://console.box.lenovo.com/l/PHk0PF>
- Pre-converted models: <https://huggingface.co/RKNNAI>
- Community x86 bring-up that confirmed the firmware step: <https://github.com/Riconec/rk1828-x86-linux>
