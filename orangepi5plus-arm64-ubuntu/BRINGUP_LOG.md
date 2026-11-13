# Orange Pi 5 Plus bring-up log

Every step, in order, with what it showed. Started 2026-11-12. Same card as the x86 bring-ups, moved from the
M.2→PCIe adapter into the Orange Pi's onboard M.2 M-key slot.

## 0. Host

| | |
|---|---|
| Board | Orange Pi 5 Plus (RK3588, 4× A76 + 4× A55) |
| OS | Ubuntu 24.04.5 LTS |
| Kernel | `6.1.0-1025-rockchip` (Ubuntu's rockchip kernel, *not* Rockchip's BSP kernel) |
| Root fs | SD card (`mmcblk1`). The onboard eMMC is not used |
| Card slot | M.2 M-key, behind the RK3588's `pcie3x4` controller (domain `0000`) |

## 1. Card on the bus (no software installed yet)

```
$ lspci -nn
0000:00:00.0 PCI bridge [0604]: Rockchip Electronics Co., Ltd RK3588 [1d87:3588] (rev 01)
0000:01:00.0 Processing accelerators [1200]: Rockchip Electronics Co., Ltd Device [1d87:182a] (rev 01)
```

| Check | Result |
|---|---|
| Link | **Gen2 x1 (5 GT/s)**, same as on x86. Root port can do Gen3 x4; the card's own max is Gen2 x1 |
| BARs | 5 regions (64 MB prefetchable, 4 MB, 3× 1 MB), all `[disabled]` |
| Driver | none bound, no `/dev/pcie-rkep-*` |
| Idle temp (SoC) | 49 °C |

The card enumerated on the first boot with no bootloader or device-tree changes.

### Side note: mDNS name after quick reboots
After several fast reboots while reseating hardware, avahi found its own stale record still on the network and
renamed the host to `<hostname>-2.local`. `sudo systemctl restart avahi-daemon` brings the original name back.
Nothing to do with the card, but it looks like "the board didn't come back" when it did.

## 2. Prerequisites (answers to the open questions in `../ORANGEPI5PLUS_TODO.md`)

| Question | Answer on this image |
|---|---|
| `CONFIG_PCIE_FUNC_RKEP` in the kernel? | **No**: `# CONFIG_PCIE_FUNC_RKEP is not set` in `/boot/config-$(uname -r)`. So the deb's out-of-tree driver is needed, with no risk of a clash with a built-in one |
| Kernel headers? | **Yes**: `linux-headers-6.1.0-1025-rockchip` installed, `/lib/modules/$(uname -r)/build` present |
| Compiler? | `build-essential` installed |
| DKMS? | **Not installed.** The deb only *recommends* it. Without it the postinst compiles the module directly, and a kernel update needs a manual re-install. Install `dkms` first |
| Secure Boot / module signing | Not a thing on this board's U-Boot. Unsigned modules load |

## 3. The arm64 host package

`rknn3-rk182x-m2_v1.2.0_arm64.deb` from `../x86_64-linux-ubuntu/vendor/rockchip-rk182x-host-packages-v1.2.0/debs/`
(sha256 `3bafc960…4ff620`, matches `SHA256SUMS`).

Inspected before installing (`dpkg-deb -I`, `-c`, `-x`, `-e`):

- **Firmware:** `/usr/lib/firmware/rknn3_rk1820.img`, md5 `45dd70f436ae86af5283d01cc7bcb601`, the same
  **M.2 2280** image used on x86. So no separate firmware file is needed.
- **Driver:** `pcie-rkep` 3.3.1 source in `/usr/src/pcie-rkep-3.3.1`. This is Rockchip's own source and builds
  as-is on arm64, so none of the x86 port patch is needed. The postinst builds it with DKMS if present, otherwise
  directly. It writes `/etc/modules-load.d/pcie-rkep.conf` and appends to `/etc/modules`, so the module loads at
  every boot, then `modprobe`s it.
- **`rknn3.service`:** `ExecStartPre=-rknn3_startup` then `ExecStart=rknn3_transfer_proxy`, as root,
  `Restart=on-failure`. `rknn3_startup` rescans PCI, `insmod`s the driver if no `/dev/pcie-rkep-*` exists, lists
  cards with `pcie_upgrade_tool ld`, and runs `pcie_upgrade_tool -s <addr> uf <fw> -reset` on each one. This is
  the same flow as our hand-written `rk1828-up.sh` on x86, but it runs automatically on every boot.
- **`rknn-mdns.service`:** Rockchip's mDNS discovery for cards reached over the network. It isn't needed for a
  local PCIe card, so we disable it.
- **Binaries in `/usr/bin`:** `pcie_upgrade_tool`, `rknn-smi`, `rknn3_transfer_proxy`, `rkllm3-server`,
  `rknn3_llm_cli`, `rknn3_vlm_demo`, `rknn3_model_info`, `pcie_speed_test_rc` and other demos, plus the
  `librknn3_api*.so` libraries in `/usr/lib`. **No need to build the CLI** the way we did on x86.
- Also: a udev rule plus `rknn3_usb_startup@.service` for the USB variant (unused here), and a GStreamer plugin.

## 4. Install

```bash
scp rknn3-rk182x-m2_v1.2.0_arm64.deb opi:rk1828/
ssh -t opi 'cd ~/rk1828 && sudo apt-get install -y dkms \
  && sudo dpkg -i rknn3-rk182x-m2_v1.2.0_arm64.deb \
  && sudo systemctl disable --now rknn-mdns.service'
```

_Result: pending._
