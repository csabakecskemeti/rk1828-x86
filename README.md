# rk1828-x86

Running LLMs and vision-language models on a **Rockchip RK1828** AI accelerator (M.2 module, 5 GB 3D-stacked
DRAM, 20 TOPS NPU) from an **x86_64 Linux PC**: kernel driver port, Rockchip host software, firmware, scripts,
docs and benchmark results.

| Folder | Contents |
|---|---|
| [`x86_64-linux-ubuntu/`](x86_64-linux-ubuntu/) | Everything used to get it working on **x86_64 Ubuntu 26.04 (kernel 7.0)**, Nov 2026: driver, vendor binaries + firmware, scripts, docs, results. **Start with its [README](x86_64-linux-ubuntu/README.md).** |

Results on one RK1828 (generation speed, all on the card):

| Model | tok/s | Max context |
|---|---:|---:|
| Qwen3-1.7B | ~95 | 32k |
| Qwen3-8B | ~49 | 6k |
| Qwen3.5-4B (+ vision) | ~33 (flat to 32k) | 68k |

Details: [`x86_64-linux-ubuntu/docs/TEST_RESULTS.md`](x86_64-linux-ubuntu/docs/TEST_RESULTS.md).

> Vendor files (binaries, firmware, packages, PDFs) are © Rockchip Electronics Co., Ltd., redistributed unmodified
> for convenience under their own terms (see `vendor/*/LICENSE*`). The kernel driver is GPL (Rockchip's source with
> a small x86 port). Scripts and docs in this repo: free to use.
