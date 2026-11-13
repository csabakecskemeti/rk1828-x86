# RK1828 on an Orange Pi 5 Plus (arm64 Ubuntu)

The RK1828 is the same card as in [`x86_64-linux-ubuntu`](../x86_64-linux-ubuntu/) and
[`manjaro-x86_64-linux`](../manjaro-x86_64-linux/), here in the **onboard M.2 M-key slot of an Orange Pi 5 Plus
(RK3588)**. This is an officially supported host, so it uses **Rockchip's own arm64 host package** with no
driver port and no hand-built tools.

| | x86 (Ubuntu / Manjaro) | Orange Pi 5 Plus (this folder) |
|---|---|---|
| Host | Threadripper PRO 7965WX / Ryzen 5 5600GT | RK3588, 4× A76 + 4× A55 |
| OS / kernel | Ubuntu 26.04 (7.0) / Manjaro (6.12) | Ubuntu 24.04.5, `6.1.0-1025-rockchip` |
| Card mounting | M.2→PCIe x4 adapter + extender cable | onboard M.2 M-key slot |
| Link | Gen2 x1 | Gen2 x1 (same, the card's own maximum) |
| Driver | `pcie-rkep` ported to x86 (`x86-port.patch`) | `pcie-rkep` 3.3.1 from the arm64 deb, built by DKMS, unmodified |
| Firmware load | `scripts/rk1828-up.sh`, by hand after every boot | `rknn3.service` from the deb, every boot |
| CLI / server | built from the SDK example | prebuilt in the deb (`/usr/bin`) |
| Result | ~95–118 tok/s (Qwen3-1.7B) | **115 tok/s generate / 2022 tok/s prefill** (Qwen3-1.7B) |

## Status

- [x] Card enumerates (`1d87:182a`, Gen2 x1)
- [x] Prerequisites checked: kernel has no built-in RKEP, headers and compiler are present
- [x] arm64 deb inspected; it bundles the M.2 2280 firmware
- [x] Install `dkms` and the deb
- [x] Driver bound (`/dev/pcie-rkep-*`), firmware loaded by `rknn3.service` on every boot
- [ ] **Board hard-reset under load once the card was active: check power** (see log §5)
- [x] `sudo rknn-smi info` sees the card (Online, Health OK, 45 °C idle)
- [x] Qwen3-1.7B downloaded on the board and SHA256-verified (matches the x86 test build)
- [x] Bench Qwen3-1.7B (`--bench 128 128`): **115 tok/s / 2022 prefill**, on par with x86
- [x] Interactive chat with `rknn3_llm_cli` (see log §9)
- [ ] Qwen3.5-4B / Qwen3-8B
- [ ] `rkllm3-server` with Qwen3.5-4B + vision

Step-by-step with outputs: **[`BRINGUP_LOG.md`](BRINGUP_LOG.md)**.
