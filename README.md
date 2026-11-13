# rk1828-how-to

Running LLMs and vision-language models on a **Rockchip RK1828** AI accelerator (M.2 module, 5 GB 3D-stacked
DRAM, 20 TOPS NPU) from **x86_64 Linux PCs** (kernel driver port) and an **Orange Pi 5 Plus** (Rockchip's own
arm64 package): host software, firmware, scripts, step-by-step logs and benchmark results.

> Formerly `rk1828-x86`; GitHub redirects the old URL.

| Folder | Contents |
|---|---|
| [`x86_64-linux-ubuntu/`](x86_64-linux-ubuntu/) | Everything used to get it working on **x86_64 Ubuntu 26.04 (kernel 7.0)**, Nov 2026: driver, vendor binaries + firmware, scripts, docs, results. **Start with its [README](x86_64-linux-ubuntu/README.md).** |
| [`manjaro-x86_64-linux/`](manjaro-x86_64-linux/) | Same bring-up reproduced on **Manjaro** (kernel 6.12): what differed |
| [`orangepi5plus-arm64-ubuntu/`](orangepi5plus-arm64-ubuntu/) | The card in an **Orange Pi 5 Plus** (RK3588, Ubuntu 24.04): Rockchip's arm64 package, no driver port. **Working**: chat + 115 tok/s on Qwen3-1.7B — [bring-up log](orangepi5plus-arm64-ubuntu/BRINGUP_LOG.md) |

Results on one RK1828 (generation speed, all on the card; x86 Ubuntu host):

| Model | tok/s | Max context |
|---|---:|---:|
| Qwen3-1.7B | ~95 | 32k |
| Qwen3-8B | ~49 | 6k |
| Qwen3.5-4B (+ vision) | ~33 (flat to 32k) | 68k |

Details: [`x86_64-linux-ubuntu/docs/TEST_RESULTS.md`](x86_64-linux-ubuntu/docs/TEST_RESULTS.md).

Qwen3-1.7B by host: x86 Ubuntu ~99, x86 Manjaro 118, **Orange Pi 5 Plus 115** tok/s. Once the model is loaded,
generation runs from the card's own memory, so the host barely matters.

> Vendor files (binaries, firmware, packages, PDFs) are © Rockchip Electronics Co., Ltd., redistributed unmodified
> for convenience under their own terms (see `vendor/*/LICENSE*`). The kernel driver is GPL (Rockchip's source with
> a small x86 port). Scripts and docs in this repo: free to use.
