#!/usr/bin/env python3
# Read-only dump of the RK182x endpoint status block (struct pcie_ep_obj_info) at BAR0 offset 0.
# Run: sudo python3 rk-ep-state.py [0000:01:00.0]
import mmap, os, struct, sys

bdf = sys.argv[1] if len(sys.argv) > 1 else "0000:01:00.0"
path = f"/sys/bus/pci/devices/{bdf}/resource0"
fd = os.open(path, os.O_RDONLY | os.O_SYNC)
m = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ)

def u32(off): return struct.unpack_from("<I", m, off)[0]
def u16(off): return struct.unpack_from("<H", m, off)[0]
def u64(off): return struct.unpack_from("<Q", m, off)[0]

MODES = {1: "BOOTROM", 2: "LOADER", 3: "KERNEL", 4: "FUN0"}
mode, sub = u16(0x8), u16(0xA)
print(f"magic          = 0x{u32(0x0):x}")
print(f"version        = 0x{u32(0x4):08x}")
print(f"devmode        = {mode} ({MODES.get(mode, '?')}), submode={sub}")
print("msi_data       = " + " ".join(f"{u32(0xC + 4*i):08x}" for i in range(8)))
print("err_event      = " + m[0x2C:0x4C].hex())
for i, n in enumerate(["bar0", "bar1", "bar2", "bar5"]):
    print(f"ep_{n}_phy_addr = 0x{u64(0x50 + 8*i):x}")
print(f"irq_type_rc    = 0x{u32(0x1FC):x}")
print(f"dma_status_rc  = wr 0x{u32(0x200):x} rd 0x{u32(0x204):x}")
print(f"irq_type_ep    = 0x{u32(0x208):x}")
print(f"irq_user_rc    = 0x{u32(0x214):x}   irq_user_ep = 0x{u32(0x218):x}")
print(f"irq_rc_msi_en  = {u32(0x21C)}")
print(f"[0x400] cmd    = 0x{u32(0x400):08x}")
m.close(); os.close(fd)
