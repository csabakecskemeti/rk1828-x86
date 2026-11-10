# Differences from the Ubuntu bring-up

Reproducing `../x86_64-linux-ubuntu/docs/SETUP_GUIDE.md` on a Manjaro Linux box (kernel 6.12.101-1-MANJARO,
AMD Ryzen 5 5600GT, 62 GB RAM — a different, smaller machine than the Threadripper used for the original
bring-up). Card, firmware, and SDK release (RKNN3 v1.2.0, host package v1.2.0) are identical; only the host
OS changed. Below is everything that actually differed, in the order it was hit.

## 1. Python package install: PEP 668 "externally managed environment"

Manjaro (like current Arch) blocks `pip install` into the system Python by default:

```
error: externally-managed-environment
× This environment is externally managed
```

`pip install --user "huggingface_hub[cli]"` fails the same way. **Fix:** use a venv instead of fighting the
system Python:

```bash
python3 -m venv .venv
.venv/bin/pip install "huggingface_hub[cli]"
.venv/bin/hf download ...
```

Ubuntu's system `pip` doesn't enforce PEP 668 the same way (varies by Ubuntu release — some do), so the Ubuntu
guide's plain `pip install -U huggingface_hub` doesn't hit this on 26.04. `pipx install huggingface_hub` is the
other standard fix and works identically on both distros; a venv was simpler here since nothing else in the repo
needs that Python environment.

## 2. zsh glob expansion on the `[cli]` extras syntax

Running `pip install huggingface_hub[cli]` under **zsh** (Manjaro's and this box's default shell) fails before
pip even sees it:

```
(eval):1: no matches found: huggingface_hub[cli]
```

zsh treats `[cli]` as a glob character class and tries to expand it against filenames. Bash doesn't do this by
default, which is why the Ubuntu guide's commands (assumed bash) don't need to care. **Fix:** quote the argument:
`pip install "huggingface_hub[cli]"`. Applies to any `pip install pkg[extra]` invocation under zsh, not just this
package.

## 3. Kernel driver: no additional porting needed beyond the existing x86 patch

`driver/pcie-rkep-x86-port/x86-port.patch` (written against the Ubuntu box's kernel 7.0.0) applied/compiled
**unchanged** on kernel 6.12.101:

- `PCI_IRQ_LEGACY` → `PCI_IRQ_INTX`: confirmed needed on 6.12.101 too (checked
  `/usr/lib/modules/$(uname -r)/build/include/linux/pci.h` directly — only `PCI_IRQ_INTX` exists, no
  `PCI_IRQ_LEGACY`). Same symbol rename on both kernels.
- `MODULE_IMPORT_NS(...)` as a bare identifier vs. a string literal: the patch's version check is
  `LINUX_VERSION_CODE >= KERNEL_VERSION(6, 13, 0)`. 6.12.101 is **below** that threshold, so the bare-identifier
  form compiles as-is — verified by reading the running kernel's `MODULE_IMPORT_NS` macro definition in
  `linux/module.h`, which still does `__stringify(ns)` internally on 6.12. No source change was needed on this
  kernel; the patch's conditional already handles it correctly for both sides of 6.13.
- Flattened include paths (`"rockchip-pcie-dma.h"` etc. instead of `"../../pci/controller/..."`) and
  force-including `pcie-dw-dmatest.c` unconditionally: unrelated to kernel version, needed identically on both
  hosts because it's about building out-of-tree at all, not about kernel version.

Net result: **zero new driver changes for Manjaro.** `cd driver/pcie-rkep-x86-port && make` builds cleanly with
gcc 16.1.1 against the Manjaro kernel headers (already installed; no separate headers package needed on this
box — check `ls /usr/lib/modules/$(uname -r)/build` to confirm yours are present, or `sudo pacman -S
linux$(uname -r | grep -oP '^\d+\.\d+' | tr -d .)-headers` if not).

## 4. No package-manager equivalents were needed at all

The Ubuntu guide doesn't call `apt install` for anything beyond build-essential-equivalent tooling, and this
Manjaro box already had `gcc`, `make`, `git`, `python3`, `pip`, and matching kernel headers preinstalled — so no
`pacman -S` calls were needed at any point in this bring-up. (The repo's main README already lists a `pacman`
equivalent for anyone starting from a bare Manjaro install; this bring-up just didn't need to exercise it.)

## 5. Vendor binaries, firmware, and driver source: byte-identical, reused as-is

The firmware image (`rknn3_rk1820_m2-2280.img`, md5 `45dd70f436ae86af5283d01cc7bcb601`), `pcie_upgrade_tool`,
`rknn3_transfer_proxy`, `rkllm3-server`, and the vendor driver source under
`x86_64-deb-extracted/usr/src/pcie-rkep-3.3.1/` all came from this same repo's
`../x86_64-linux-ubuntu/vendor/` — no re-download, no re-extraction, no modification. All `SHA256SUMS` checks
passed unchanged. This confirms the v1.2.0 host package and firmware are genuinely host-OS-independent, as the
original README already states.

## 6. Bring-up procedure: identical, no script changes needed

`sudo ./scripts/rk1828-up.sh` (IOMMU passthrough attempt → `insmod` → firmware flash → start proxy) ran
unmodified and produced the same success signature (`magic=524b4550`-equivalent boot-state transition in the
firmware log, proxy lists the device). The only operational difference observed: this box's card sits in IOMMU
group 11 alongside several other devices (NVMe, other PCIe functions), so the script's "only set identity if the
card is alone in its group" guard correctly left it alone — same logic, different group composition than the
Threadripper box.

## 7. Results

| Model | Ubuntu (Threadripper) | Manjaro (Ryzen 5 5600GT) |
|---|---|---|
| Qwen3-1.7B generate | ~95 tok/s | **118 tok/s** |
| Qwen3-1.7B prefill (128 tok) | — | 2130 tok/s |
| Qwen3.5-4B + vision (VLM) | not benchmarked in original docs | 47 tok/s generate, 1.02 s to first token |

The Manjaro box measured *faster* generate throughput on Qwen3-1.7B despite having a much smaller/cheaper CPU
and far less RAM than the Threadripper — expected, since generation runs entirely on the RK1828's own NPU/DRAM
once the model is loaded; host CPU and RAM mostly matter for model load time and nothing else. Treat both
numbers as single-run data points, not controlled benchmarks (no fixed thermal/clock state was enforced on
either box).

## Bottom line

The v1.2.0 RKNN3 SDK release and host package are solidly host-OS-independent on x86_64: the only real porting
work (the kernel driver patch) was already correct for both kernel 7.0 and 6.12, and the only Manjaro-specific
friction was two generic Python/shell packaging quirks (PEP 668, zsh glob expansion) that have nothing to do
with the RK1828 itself and would show up for any `pip install pkg[extra]` on Arch-based distros.
