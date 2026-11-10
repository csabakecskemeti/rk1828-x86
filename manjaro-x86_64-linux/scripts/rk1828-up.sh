#!/bin/bash
# Bring up the RK1828 on this x86_64 Linux host, after EVERY power-on:
#   IOMMU passthrough -> pcie-rkep driver -> firmware load (pcie_upgrade_tool) -> rknn3_transfer_proxy
# Run with: sudo ./rk1828-up.sh
# Env: FW_IMG (default m2-2280), FW_WAIT (s, default 90), SKIP_FW=1, NO_IOMMU_PT=1
# Adapted from csabakecskemeti/rk1828-x86's scripts/rk1828-up.sh (same card, prior Ubuntu bring-up).
set -e
ROOT=$(cd "$(dirname "$0")" && pwd)
RUN=$ROOT/run; mkdir -p "$RUN"
exec > >(tee "$RUN/rk1828-up.log") 2>&1

KO=$ROOT/pcie-rkep/pcie-rkep.ko
PROXY=$ROOT/rknn3-toolkit/rknn3-runtime/rknn3_transfer_proxy/linux-x86_64/rknn3_transfer_proxy
UPG=$ROOT/rk182x-host-pkg/x86_64-deb-extracted/usr/bin/pcie_upgrade_tool
FW=$ROOT/rk182x-host-pkg/firmware/rknn3_rk1820_${FW_IMG:-m2-2280}.img
FW_WAIT=${FW_WAIT:-90}

[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
[ -f "$KO" ] || { echo "driver not built: cd $ROOT/pcie-rkep && make" >&2; exit 1; }
[ -f "$FW" ] || { echo "firmware image not found: $FW" >&2; exit 1; }

# Find the RK182x by vendor:device ID - NEVER trust a fixed bus address (it changes between boots,
# and touching the wrong device would unbind e.g. a NIC).
BDF=""
for d in /sys/bus/pci/devices/*; do
  if [ "$(cat "$d/vendor")" = "0x1d87" ] && [ "$(cat "$d/device")" = "0x182a" ]; then
    BDF=$(basename "$d"); break
  fi
done
if [ -z "$BDF" ]; then
  echo "RK182x (1d87:182a) not on the PCI bus. Is the card's EXTERNAL POWER connected? (must be on before boot)" >&2
  exit 1
fi
echo "RK182x found at $BDF"

# process name is truncated to 15 chars by the kernel; don't use pgrep -f (matches sudo wrappers)
if pgrep -x rknn3_transfer_ >/dev/null; then
  echo "proxy already running:"; pgrep -a rknn3_transfer_; exit 0
fi

# 1. IOMMU passthrough (harmless; never proven necessary). Must be set while no driver is bound.
GROUP=$(basename "$(readlink /sys/bus/pci/devices/$BDF/iommu_group 2>/dev/null)" 2>/dev/null || true)
if [ "${NO_IOMMU_PT:-0}" != 1 ] && [ -n "$GROUP" ] && [ -e /sys/kernel/iommu_groups/$GROUP/type ]; then
  if [ "$(ls /sys/kernel/iommu_groups/$GROUP/devices | wc -l)" != 1 ]; then
    echo "IOMMU group $GROUP contains other devices; leaving it alone:"; ls /sys/kernel/iommu_groups/$GROUP/devices
  elif [ "$(cat /sys/kernel/iommu_groups/$GROUP/type)" != "identity" ]; then
    [ -e /sys/bus/pci/devices/$BDF/driver ] && echo $BDF > /sys/bus/pci/devices/$BDF/driver/unbind
    echo identity > /sys/kernel/iommu_groups/$GROUP/type || echo "could not set identity (ok)"
  fi
  echo "IOMMU group $GROUP: $(cat /sys/kernel/iommu_groups/$GROUP/type)"
fi

# 2. driver (no PCI alias in upstream source -> never autoloads -> insmod)
if ! lsmod | grep -q '^pcie_rkep'; then
  insmod "$KO"
elif [ ! -e /sys/bus/pci/devices/$BDF/driver ]; then
  echo $BDF > /sys/bus/pci/drivers/pcie-rkep/bind
fi
sleep 1
ls -la /dev/pcie-rkep-* 2>&1 || true
dmesg | grep pcie-rkep | tail -3 || true

# 3. firmware. The card does NOT boot its eMMC firmware by itself at power-on; load it over PCIe every
#    time (same as Rockchip's rknn3_startup). BAR0 offset 0 is NOT a valid "running" check (reads 0x1f4);
#    the tool's own "magic=524b4550" line is. Exit 0 = loaded from boot ROM (needs ~1-2 min to boot);
#    exit 234 = "check ddr load addr request failed" = not in boot ROM = firmware already running.
if [ "${SKIP_FW:-0}" != 1 ]; then
  echo "loading firmware $(basename "$FW") ..."
  rc=0; "$UPG" -s "$BDF" uf "$FW" -reset > "$RUN/fw-load.log" 2>&1 || rc=$?
  sed 's/\x1b\[[0-9;]*m//g' "$RUN/fw-load.log" | grep -E 'magic=|Device boot state|Downloading firmware OK|check ddr' | sed 's/^/  /' | head -6
  case $rc in
    0)   echo "firmware loaded from boot ROM; waiting ${FW_WAIT}s for it to boot"; sleep "$FW_WAIT" ;;
    234) echo "card not in boot ROM (exit 234) -> firmware already running, continuing" ;;
    *)   echo "pcie_upgrade_tool exit $rc (see run/fw-load.log); continuing anyway" >&2 ;;
  esac
fi

# 4. proxy (root; clients run as normal user)
nohup "$PROXY" > "$RUN/proxy.log" 2>&1 &
sleep 2
pgrep -a rknn3_transfer_
"$PROXY" devices
