# RK1828 on x86_64 Linux (tested on Ubuntu 26.04, kernel 7.0)

Everything needed to reproduce our working setup: an RK1828 M.2 card driven from an x86_64 PC, running Qwen3 /
Qwen3.5 LLMs and a vision model on the card.

- **What was tested:** Ubuntu 26.04.1, kernel 7.0.0-38-generic, AMD Threadripper PRO (AMD-Vi IOMMU on), card in an
  M.2→PCIe x4 adapter via a 30 cm M.2 extender, card has an **external power supply**.
- **Link:** PCIe Gen2 x1 (the card's own maximum). Only model loading crosses it; generation runs from card memory.
- **Vendor software:** Rockchip RKNN3 SDK **v1.2.0** (first release with x86_64 host support) + Rockchip RK182x host
  packages v1.2.0 (firmware + `pcie_upgrade_tool`).

## Layout
| Path | What |
|---|---|
| `driver/pcie-rkep-x86-port/` | Kernel driver `pcie-rkep` (Rockchip vendor kernel `develop-6.1`, v3.3.0.1), ported to build out-of-tree on x86 (kernel ≥ 6.x incl. 7.0). `rockchip-original/` + `x86-port.patch` show the changes. |
| `vendor/rockchip-rk182x-host-packages-v1.2.0/` | Rockchip host `.deb`s (x86_64 SODIMM, arm64 M.2 2280, arm64 M.2 2242), **firmware images** (`firmware/`), and the extracted x86_64 deb (`x86_64-deb-extracted/`: `pcie_upgrade_tool`, `rknn-smi`, DKMS driver 3.3.1 source, systemd units, …). |
| `vendor/rknn3-toolkit-v1.2.0-x86_64/` | From `airockchip/rknn3-toolkit` v1.2.0: `rknn3_transfer_proxy`, `librknn3_api*.so` + headers, `rkllm3-server` (x86_64), `rknn3_llm_cli` example source + **prebuilt x86_64 binary**, EN docs (PDF). |
| `scripts/` | `rk1828-up.sh` (bring-up after boot), `download-models.sh`, `run-llm.sh`, `serve-qwen35-vl.sh`, `ask.py` |
| `tools/` | `rk-smi` (small status tool), `rk-ep-state.py` (dump card BAR0 status block) |
| `models/` | Download target (weights not in git). `checksums/` holds the SHA256SUMS of the exact builds tested. |
| `docs/` | Full write-up: `SETUP_GUIDE.md` (how it was made to work), `TEST_RESULTS.md`, `TRIED_AND_FAILED.md`, `FINDINGS_AND_TODO.md`. These are the original working notes and use the original folder layout; see the mapping at the end of this README. |
| `results/` | Raw benchmark logs |

## Reproduce on a new machine

### 0. Requirements
- x86_64 Linux, glibc ≥ 2.38 (the prebuilt CLI needs 2.38; everything else needs ≤ 2.34), `gcc`, `make`,
  kernel headers for the running kernel, `python3`, the HF CLI (`pip install -U huggingface_hub`).
- **Secure Boot off** (or sign the module yourself); the driver is an unsigned out-of-tree module.
- Card's **external power connected before boot.** Without it the card doesn't appear on the PCI bus at all.
- Check: `lspci -nn | grep 1d87:182a`

**Ubuntu/Debian:** `sudo apt install build-essential linux-headers-$(uname -r) python3-pip`
**Manjaro/Arch:** `sudo pacman -S base-devel python-pip` plus the headers package that matches your kernel, e.g.
`sudo pacman -S $(pacman -Qsq '^linux[0-9]+$' | head -1)-headers` (on Manjaro: `mhwd-kernel -li` shows the kernel,
then install `linuxXYZ-headers`). HF CLI: `pipx install huggingface_hub` or `pip install --user -U huggingface_hub`.

### 1. Build the driver (once, and after every kernel update)
```bash
cd driver/pcie-rkep-x86-port && make && cd ../..
```
Alternative: Rockchip's own DKMS source (v3.3.1) is in
`vendor/rockchip-rk182x-host-packages-v1.2.0/x86_64-deb-extracted/usr/src/pcie-rkep-3.3.1/`.

### 2. Download the tested models (pinned commits, SHA256-verified)
```bash
./scripts/download-models.sh            # all four (~14 GB), or: qwen3-1.7b | qwen3-8b | qwen3.5-4b | qwen3.5-4b-vl
```

### 3. Bring up the card (after EVERY power-on)
```bash
sudo ./scripts/rk1828-up.sh
```
It finds the card by PCI ID, sets its IOMMU group to passthrough (only if the card is alone in it), `insmod`s
the driver, **loads the firmware** with `pcie_upgrade_tool … uf rknn3_rk1820_m2-2280.img -reset`, and starts
`rknn3_transfer_proxy` (root). Logs go to `run/`.
- Exit `0` from the firmware tool means it loaded from the boot ROM; the script then waits 90 s (`FW_WAIT`) for the card to boot.
- Exit `234` (`check ddr load addr request failed`) means the firmware is **already running**. That's fine.
- Success looks like `magic=524b4550` in `run/fw-load.log` / `run/proxy.log`.
- Other card: `FW_IMG=m2-2242` (42 mm M.2) or `FW_IMG=sodimm`. **The wrong image can hang the card until a full
  cold power cycle** (PSU and external power off).

### 4. Run models (normal user)
```bash
./scripts/run-llm.sh qwen3.5-4b                                   # interactive chat
./scripts/run-llm.sh qwen3-8b --prompt "Explain NPUs." --once -n 256
./scripts/run-llm.sh qwen3-1.7b --bench 128 128                   # benchmark
```
Vision + OpenAI-compatible API:
```bash
nohup ./scripts/serve-qwen35-vl.sh > run/server.log 2>&1 &          # 127.0.0.1:8080
python3 scripts/ask.py "What is in this picture?" vendor/rknn3-toolkit-v1.2.0-x86_64/rkllm3-server/demo.jpg
pkill -f rkllm3-server
```
Only **one model fits on the card at a time.** Stop the CLI or server before starting another
(`MODEL_SETUP fail, ack = ACK_FAIL` = card busy).

### 5. Expected results
~95 tok/s (Qwen3-1.7B), ~49 tok/s (Qwen3-8B), ~33 tok/s (Qwen3.5-4B); see `docs/TEST_RESULTS.md`.

## Key lessons (read `docs/TRIED_AND_FAILED.md` for all of them)
1. **The card needs firmware loaded by the host on every boot.** Symptom without it: the proxy lists the card, but
   clients hang at `rknn3_init` and the proxy log stops at `wait ep create....`, with **zero interrupts**.
2. **External power must be on before boot**, otherwise the BIOS hides the slot (a PCI rescan won't help).
3. **Never hard-code the PCI address**: it shifts when devices appear or disappear.
4. **Never unbind or rmmod the driver while a proxy holds the device**: unkillable process, reboot needed.
5. The proxy ignores SIGTERM when stuck: `sudo kill -9 $(pgrep -x rknn3_transfer_)`.
6. A slow-looking load with zero interrupts isn't slow, it's stuck. `RKNN_LOG_LEVEL=5` shows where.
7. The IOMMU was never the problem (no page faults); passthrough is kept only as harmless.

## Mapping: original working layout (used in docs/) → this repo
| Original (`~/Documents/workspace/RK1828-test/`) | Repo |
|---|---|
| `pcie-rkep/` | `driver/pcie-rkep-x86-port/` |
| `rknn3-toolkit/rknn3-runtime/rknn3_transfer_proxy/linux-x86_64/` | `vendor/rknn3-toolkit-v1.2.0-x86_64/rknn3_transfer_proxy/` |
| `rknn3-toolkit/rknn3-runtime/rknn3-api/Linux/x86_64/` | `vendor/rknn3-toolkit-v1.2.0-x86_64/rknn3-api/lib/` |
| `rknn3-toolkit/rknn3-runtime/rkllm3-server/bin/linux-x86_64/` | `vendor/rknn3-toolkit-v1.2.0-x86_64/rkllm3-server/bin/` |
| `…/examples/rknn3_llm_cli/install/rknn3_llm_cli_x86_64/` | `vendor/rknn3-toolkit-v1.2.0-x86_64/prebuilt/rknn3_llm_cli_x86_64/` |
| `rk182x-host-pkg/` (`x86-extracted/`, `firmware/`, debs) | `vendor/rockchip-rk182x-host-packages-v1.2.0/` (`x86_64-deb-extracted/`, `firmware/`, `debs/`) |
| `rk1828-up.sh`, `serve-qwen35-vl.sh`, `ask.py` | `scripts/` |
| `rk-smi/`, `rk-ep-state.py` | `tools/` |
| `models/` | `models/` (via `scripts/download-models.sh`) |

## Not included
- Model weights (download script, pinned + verified).
- The RKNN3 Toolkit Python wheel for model **conversion** (97 MB, not used here):
  `airockchip/rknn3-toolkit` @ `141883c8e11b05ef4cca4a69d8a7572c4d855191` → `rknn3-toolkit/packages/`.
  Model zoo (conversion scripts): `airockchip/rknn3-model-zoo` @ `7f8c7d848448fa14cf16ba359ca98405c8bb94b5`.
