# RK1828 on x86_64 Linux — Manjaro variant

Confirms the [`x86_64-linux-ubuntu`](../x86_64-linux-ubuntu/) bring-up reproduces on **Manjaro Linux** (Arch-based,
rolling release) with no changes to the vendor binaries, the firmware, or the driver source itself. Same card,
same SDK/firmware release (v1.2.0), **different physical machine**.

| | Ubuntu bring-up | Manjaro bring-up (this folder) |
|---|---|---|
| Host | Threadripper PRO 7965WX, 1 TB RAM | AMD Ryzen 5 5600GT, 62 GB RAM |
| OS | Ubuntu 26.04.1 | Manjaro Linux (rolling) |
| Kernel | 7.0.0-38-generic | 6.12.101-1-MANJARO |
| gcc | — | 16.1.1 |
| Result | ~95 tok/s (Qwen3-1.7B) | **118 tok/s generate / 2130 tok/s prefill** (Qwen3-1.7B); 47 tok/s (Qwen3.5-4B-VL) |

See **[`DIFFERENCES_FROM_UBUNTU.md`](DIFFERENCES_FROM_UBUNTU.md)** for the full list of what actually differed —
short version: two packaging/shell gotchas (PEP 668, zsh glob), zero driver-source changes beyond the existing
`driver/pcie-rkep-x86-port/x86-port.patch`, zero firmware/vendor-binary changes, and a different (and in this
case faster) host box.

`scripts/` here holds the scripts exactly as they ran on the Manjaro box — they assume a flat workspace layout
(`driver/`, `rknn3-toolkit/`, `rk182x-host-pkg/`, `models/` all as siblings) rather than this repo's nested
`vendor/` layout, since that's how the workspace was built up before this repo was found. They're included for
reference/diffing, not as a drop-in replacement for `../x86_64-linux-ubuntu/scripts/` — use those (they already
work unmodified on Manjaro; only the one-time environment setup in `DIFFERENCES_FROM_UBUNTU.md` differs).
