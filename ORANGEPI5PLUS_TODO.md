# Next: moving the RK1828 to an Orange Pi 5 Plus

> **Started 2026-11-12.** The card is in the Orange Pi and enumerates. Questions 1–5 are answered in
> [`orangepi5plus-arm64-ubuntu/BRINGUP_LOG.md`](orangepi5plus-arm64-ubuntu/BRINGUP_LOG.md) (§0–2), and question 8 in §3: the deb bundles the M.2 2280 image.
> Progress is tracked there. This file is kept as the original plan.

Planning notes from the 2026-11-09 Manjaro bring-up session, written down before stopping so nothing needs to
be re-derived next time. Nothing below has been executed yet — this is what's ready, and what's still unknown.

## Already have, ready to carry over

- **arm64 M.2 host package**: `rk182x-host-pkg/debs/rknn3-rk182x-m2_v1.2.0_arm64.deb` (official Rockchip build —
  includes DKMS `pcie-rkep` driver, `pcie_upgrade_tool`, `rknn-smi`, proxy, `rkllm3-server`, `rknn3_llm_cli`, the
  M.2 firmware, and a systemd service that auto-loads firmware on every boot). **No porting needed** — this is
  Rockchip's own arm64 build, unlike the from-scratch x86 driver port we had to do here.
- **Firmware image**: `rk182x-host-pkg/firmware/rknn3_rk1820_m2-2280.img` (md5 `45dd70f436ae86af5283d01cc7bcb601`)
  — board-specific, not host-arch-specific, so the exact same file applies. (It's likely also bundled inside the
  arm64 deb itself — worth checking which one the systemd unit actually points at before assuming we need to
  supply it separately.)
- **Models**: `models/RK182X-LLM-Qwen3-1.7B/` and `models/RK1828-VLM-Qwen3.5-4B/`, already downloaded and
  SHA256-verified. `.rknn`/`.weight` files aren't CPU-architecture-specific — copy via `scp`/`rsync`, no
  re-download needed.
- **Fallback aarch64 binaries**: `rknn3-toolkit/rknn3-runtime/{rknn3_transfer_proxy/linux-aarch64,
  rknn3-server/Linux/aarch64}` from the public GitHub SDK clone, in case the deb's versions have an issue.
- Everything in the `csabakecskemeti/rk1828-x86` repo (`manjaro-x86_64-linux/`, `x86_64-linux-ubuntu/`) as prior
  art — same SDK release (v1.2.0), same card, same models.

## Unknowns — need answering before/during the move

1. **Is the Orange Pi 5 Plus physically set up and powered on?** What OS/kernel version is it actually running
   (which Ubuntu/Debian image, which kernel)?
2. **Network reachability**: is it reachable over SSH from wherever work happens next? (Same access question we
   hit with GitHub this session — need credentials/reachability before anything can be installed remotely.)
3. **Does its kernel already have `CONFIG_PCIE_FUNC_RKEP` built in?**
   `zcat /proc/config.gz 2>/dev/null | grep PCIE_FUNC_RKEP` or check `/boot/config-$(uname -r)`. If yes, the
   deb's DKMS driver may be redundant (or may conflict — check before installing both).
4. **Matching kernel headers** need to be present on the OPi for DKMS to build the driver against its running
   kernel, if the built-in option above isn't available.
5. **Secure Boot / module signing**: unlikely to be locked down on a hobbyist ARM board image, but worth a quick
   check (`mokutil --sb-state` equivalent or just whether Secure Boot is even a concept on this board's bootloader)
   before assuming an unsigned DKMS module will load.
6. **Physical**: card has to physically move from this PC's M.2→PCIe adapter into the OPi5+'s onboard M.2 M-key
   slot. External power must stay connected and must be up **before** boot (same rule as the x86 box — the BIOS/
   bootloader won't see the card at all otherwise, and there's no rescan workaround).
7. **IOMMU/SMMU**: the x86 guide found IOMMU passthrough was never actually necessary (no page faults either
   way). Unknown whether the ARM SMMU behaves the same way on RK3588 — don't assume, just check for errors in
   `dmesg` after bring-up rather than pre-emptively configuring anything.
8. **Firmware image variant**: double-check the OPi5+'s card is still the M.2 2280 form factor before flashing
   `rknn3_rk1820_m2-2280.img` — a wrong board variant's firmware "can leave an incompatible loader in RAM until a
   full cold power cycle" per the community project's own warning (same risk noted in our Manjaro notes).

## Rough plan once the above is answered

1. `dpkg -i rknn3-rk182x-m2_v1.2.0_arm64.deb` (or `dpkg-deb -x` first to inspect before installing system-wide).
2. Check `systemctl status rknn3.service` / whatever unit the deb installs — it's supposed to load firmware
   automatically on every boot, unlike our manual `rk1828-up.sh` on x86. Confirm this actually works before
   assuming no bring-up script is needed.
3. `scp`/`rsync` the two already-downloaded model folders over.
4. Run `rknn-smi info -l` (Rockchip's official status tool, included in the deb) to confirm the card enumerates.
5. Benchmark the same way we did here (`rknn3_llm_cli --bench 128 128` on Qwen3-1.7B) and compare — different
   PCIe topology (native M.2 M-key slot on the RK3588 vs. our M.2→PCIe-x4 adapter card on the Threadripper/Ryzen
   boxes), so don't assume the number carries over.
6. Write up a third differences doc (`orangepi5plus/` folder in the repo, same pattern as `manjaro-x86_64-linux/`)
   once it's working.

## Where everything lives right now

- Working copy: `~/Documents/workspace/RK1828-test/` on this Manjaro box.
- Archived/shared copy: `git@github.com:csabakecskemeti/rk1828-x86.git` (`main` branch), folders
  `x86_64-linux-ubuntu/` (original) and `manjaro-x86_64-linux/` (this session's notes, pushed as `bb6857a`).
