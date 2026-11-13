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

Copied to a working folder in the home directory (normal user, no sudo) and unpacked there for inspection:

```bash
ssh opi 'mkdir -p ~/rk1828'
scp rknn3-rk182x-m2_v1.2.0_arm64.deb SHA256SUMS opi:rk1828/
ssh opi 'cd ~/rk1828 && dpkg-deb -x rknn3-rk182x-m2_v1.2.0_arm64.deb x && dpkg-deb -e rknn3-rk182x-m2_v1.2.0_arm64.deb x/ctl'
# ~/rk1828/x = reference copy of the package contents; not used at runtime, safe to delete
```

What it contains (`dpkg-deb -I`, `-c`, plus the unpacked scripts):

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
ssh -t opi 'cd ~/rk1828 && sudo apt-get install -y dkms \
  && sudo dpkg -i rknn3-rk182x-m2_v1.2.0_arm64.deb \
  && sudo systemctl disable --now rknn-mdns.service'
```

**Result: OK.** DKMS built `pcie-rkep` 3.3.1 into `/lib/modules/6.1.0-1025-rockchip/updates/dkms/` (unsigned, which is
fine: the kernel has no module signing). The driver bound to the card (`/dev/pcie-rkep-0000:01:00.0`, root-only `0600`),
and `rknn3.service` started. The postinst's `Failed to stop rknn3-firmware.service / rknn3-transfer-proxy.service ...
not loaded` lines are just it removing units from older package versions, so they're harmless.

Firmware load from `journalctl -u rknn3.service`:
- before the load the card reported `magic=18` (uninitialised, the same state as x86 with no firmware)
- `Device boot state: 0x00004c42` → writes `node2_os`, `node4_os` → `Reseting device...OK` → `Downloading firmware OK`
- the proxy then started a per-card child, `rknn3_transfer_proxy_b98e6c51 -s 0000:01:00.0`, pinned to the A76 cores
  (`mask 0xf0`)

```
$ rknn3_transfer_proxy devices
Serial         Hash        Type
0000:01:00.0   0xb98e6c51  PCIE
```

Notes:
- **`[ETH] config file read failed ... /tmp/rk-mdns.ini`** repeats in the proxy log. That's the proxy looking for
  network-attached cards, a file `rknn-mdns` would write. It's harmless with `rknn-mdns` disabled.
- **`rknn-smi` needs root.** As a normal user it prints nothing and exits 255. Use `sudo rknn-smi info -l`. Its logs
  are in `/var/log/rknn-smi.log*`.

## 5. Unexpected hard reset during the first model download ⚠️

At 19:05, a minute after the install, the board **reset itself** while `hf download` was fetching Qwen3-1.7B
(network plus SD-card writes) with the card now running firmware.

- The previous boot has no shutdown record, and its journal stops mid-activity. That points to **power loss or a
  hard reset, not a kernel panic** (no new pstore entry).
- The same board had already reset under full CPU load *before* the card was installed (an unrelated October NPU
  test). So the supply was already marginal, and the active RK1828 adds load on the M.2 3.3 V rail.
- **Good news from the reboot:** `rknn3.service` reloaded the firmware by itself (`Downloading firmware OK` about
  40 s after power-on) and restarted the proxy, with no manual step.

_To check: the Orange Pi's own supply (needs a solid 5 V / 4 A USB-C). The card's external power is connected._

### Firmware confirmed running (after the reset): `sudo rknn-console`

```
open rkep: /dev/pcie-rkep-0000:01:00.0 Success.
 - id=182a1d87
 - magic=524b4550, ver=2          <- "RKEP": firmware running
 - rc_cc_version=30302
 - ep_cc_version=30300
 - bar2 bar2_phy_addr=0x1200000000
 - gen2x1
chip info: rk3588
Console started (Device: PCIE)    <- console into the card's own OS; Ctrl+X exits
```

`rknn-console` (root) is the quickest "is the firmware alive" check: the same `magic=524b4550` / `ep_cc_version=30300`
as the x86 bring-up. Card's external power: connected.



## 6. `rknn-smi` usage (root only)

Options go **after** a subcommand: `rknn-smi -l` only prints the help text, and as a normal user it prints nothing (exit 255).

```bash
sudo rknn-smi info              # summary
sudo rknn-smi info -l           # topology
sudo rknn-smi info -w           # live, refreshing
sudo rknn-smi info -t <type>    # temp, power, voltage, memory, npu_freq, health, reset_reason, pcie_err, ...
```

```
| rknn-smi      Version: 1.3.0                                                  |
| Device        Status   | Health        | Power(mW)     | Npu(%)               |
| Chip          Name     | Bus-Id        | Temp(C)       | Memory-Usage(MB)     |
| 0             Online   | OK            | NA            | 0                    |
| 0             RK1828   | 0000:01:00.0  | 45            | 32   / 5120          |
```

Idle: online and healthy, 45 °C, 32 MB of 5 GB used. Power reads `NA` on this M.2 module.

## 7. Models

Same pinned script as on x86 (`../x86_64-linux-ubuntu/scripts/download-models.sh`), copied to `~/rk1828/scripts/`
with `models/checksums/` next to it, and `hf` in a venv (`~/rk1828/.venv`).

### ⚠️ The §5 reset corrupted files written just before it
The first attempt was cut off by the reset. After reboot the venv's files were still there but **0 bytes** (685 of
2097). pip had written them seconds before the power loss, and the data never reached the SD card. `hf` then
"succeeded" silently (exit 0, nothing downloaded), and `download-models.sh` only failed at the checksum step.

- Checked everything written in that window. System files were fine: `dpkg --verify rknn3-rk182x-m2 dkms` is
  clean and `pcie-rkep.ko` is intact. The only other 0-byte files were ones that are normally empty (dpkg
  locks, tracker WALs, HF marker files).
- Fix: `rm -rf .venv models/<model>/.cache`, recreate the venv, re-run the download. Lesson: after an unexpected
  reset on an SD-card root, **check recent writes before trusting them**.

### Qwen3-1.7B
```
$ ./scripts/download-models.sh qwen3-1.7b
Qwen3-1.7B.embed.bin: OK      (622 MB)
Qwen3-1.7B.rknn: OK
Qwen3-1.7B.tokenizer.gguf: OK
Qwen3-1.7B.weight: OK         (1.08 GB)
...
matches tested build
```
1.7 GB in about 40 s, with the card active. **No reset this time**, so the §5 reset doesn't reproduce simply
from network plus SD-card load.

## 8. First run: Qwen3-1.7B, all on the card ✅

Using the CLI that comes with the deb (`/usr/bin/rknn3_llm_cli`), as a **normal user** (the root proxy from
`rknn3.service` handles the device):

```bash
cd ~/rk1828
M=models/RK182X-LLM-Qwen3-1.7B/Qwen3-1.7B-w4a16-8-32256/Qwen3-1.7B.rknn
rknn3_llm_cli --model $M --core-mask 0xff --bench 128 128
```

| Stage | Tokens | ms/token | **tok/s** |
|---|---:|---:|---:|
| Prefill | 128 | 0.494 | **2022.5** |
| Generate | 127 | 8.661 | **115.5** |

TTFT 63 ms. 9 s wall time including model load (1.7 GB over the Gen2 x1 link). The board stayed up.
Raw log: [`results/bench-qwen3-1.7b-128x128.log`](results/bench-qwen3-1.7b-128x128.log).

**Comparison** (same card, same model build, same command):

| Host | Prefill tok/s | Generate tok/s |
|---|---:|---:|
| x86 Ubuntu (Threadripper, adapter card) | 1220 | 99 |
| x86 Manjaro (Ryzen 5 5600GT, adapter card) | 2130 | 118 |
| **Orange Pi 5 Plus (onboard M.2)** | **2022** | **115** |

An ARM single-board computer drives the card as fast as the x86 desktops. Generation runs from the card's own memory, so
the host hardly matters once the model is loaded.

The bench's generated text is nonsense (it once read "**[ERROR]** The system has encountered an error..."). That's
the model replying to 128 dummy prompt tokens, **not a real error**. A real prompt:

```
$ rknn3_llm_cli --model $M --core-mask 0xff -n 200 --once \
    --prompt "In two sentences: what is a Raspberry Pi-class single board computer good for?"
A Raspberry Pi-class single board computer is good for educational and hobbyist projects, as well as simple home
automation and embedded systems.
```
Raw log: [`results/prompt-qwen3-1.7b.log`](results/prompt-qwen3-1.7b.log).
