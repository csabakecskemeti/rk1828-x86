# Vendor files: provenance

All files here are **unmodified** Rockchip deliverables, © Rockchip Electronics Co., Ltd., under their own license
terms (`rknn3-toolkit-v1.2.0-x86_64/LICENSE-RKNN-SDK`; GPL for the kernel driver sources). Each folder has a
`SHA256SUMS`.

## `rockchip-rk182x-host-packages-v1.2.0/`
- Source: Rockchip RK1820/RK1828 release share (linked from the rknn3-toolkit README as "RK1820/RK1828 Firmware"):
  <https://console.box.lenovo.com/l/PHk0PF> → `RK1820_RK1828/RELEASE_V1.2.0/`. Released 2026-11-07.
- `debs/`
  - `rknn3-rk182x-sodimm_v1.2.0_x86_64.deb`: official **x86_64** host package (SODIMM module): DKMS `pcie-rkep`
    3.3.1, `pcie_upgrade_tool`, `rknn-smi`, `librknnsmi.so`, proxy, `rkllm3-server`, `rknn3_llm_cli`, systemd
    `rknn3.service` + `rknn3_startup` (loads the firmware before starting the proxy), udev rule, SODIMM firmware.
  - `rknn3-rk182x-m2_v1.2.0_arm64.deb`: arm64 host package for the **M.2 2280** module (source of the M.2 firmware).
  - `rknn3-rk182x-m2-2242_v1.2.0_arm64.deb`: arm64 host package for the **M.2 2242** module.
- `firmware/`: the `rknn3_rk1820.img` from each deb, renamed:
  | File | Board | md5 |
  |---|---|---|
  | `rknn3_rk1820_m2-2280.img` | M.2 2280 (**the one we use**) | 45dd70f436ae86af5283d01cc7bcb601 |
  | `rknn3_rk1820_m2-2242.img` | M.2 2242 | dbe9ebca7ec8df45e06143690494eda4 |
  | `rknn3_rk1820_sodimm.img` | SODIMM (shipped in the x86 deb) | 8f83b139c62ce88c5451ec78c6ae0886 |

  Firmware is board-specific but host-architecture-independent. The x86 deb has only the SODIMM image, so for an
  M.2 card take the M.2 image.
- `x86_64-deb-extracted/`: contents of the x86_64 deb (`dpkg-deb -x`), so nothing needs installing.

## `rknn3-toolkit-v1.2.0-x86_64/`
- Source: <https://github.com/airockchip/rknn3-toolkit> @ commit `141883c8e11b05ef4cca4a69d8a7572c4d855191` (v1.2.0).
- `rknn3_transfer_proxy/`: `rknn3-runtime/rknn3_transfer_proxy/linux-x86_64/` (byte-identical to the deb's)
- `rknn3-api/`: `rknn3-runtime/rknn3-api/{include, Linux/x86_64 → lib}`
- `rkllm3-server/`: `rknn3-runtime/rkllm3-server/{bin/linux-x86_64 → bin, lib/linux-x86_64 → lib, lib/include, guide, test clients, demo.jpg}`
- `examples/rknn3_llm_cli/`: example source (build: `./build-linux.sh -t x86 -a x86_64 -b Release`)
- `prebuilt/rknn3_llm_cli_x86_64/`: that example built on Ubuntu 26.04 (needs glibc ≥ 2.38; rebuild on older systems)
- `doc-EN/`: SDK PDFs (`doc/EN`)
