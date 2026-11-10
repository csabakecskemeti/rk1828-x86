// rk-smi: minimal nvidia-smi-style status tool for Rockchip RK182x coprocessors
// on an x86_64 Linux host. Uses the public RKNN3 runtime API (librknn3_api.so)
// through a running rknn3_transfer_proxy, plus sysfs/procfs for PCIe and driver info.
//
// Usage: rk-smi [-l SECONDS] [-n] [-h]
//   -l N   refresh every N seconds (like nvidia-smi -l)
//   -n     skip opening a runtime context (no version/core query)

#include <dirent.h>
#include <getopt.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "rknn3_api.h"

#define GiB (1024.0 * 1024.0 * 1024.0)
#define MiB (1024.0 * 1024.0)

static int read_line(const char* path, char* buf, size_t len)
{
  FILE* f = fopen(path, "r");
  if (!f)
    return -1;
  if (!fgets(buf, (int)len, f)) {
    fclose(f);
    return -1;
  }
  fclose(f);
  buf[strcspn(buf, "\n")] = 0;
  return 0;
}

static int proxy_running(void)
{
  DIR* d = opendir("/proc");
  if (!d)
    return -1;
  struct dirent* e;
  int found = 0;
  char path[300], comm[256];
  while ((e = readdir(d))) {
    if (e->d_name[0] < '0' || e->d_name[0] > '9')
      continue;
    snprintf(path, sizeof(path), "/proc/%s/comm", e->d_name);
    if (read_line(path, comm, sizeof(comm)) == 0 && strncmp(comm, "rknn3_transfer", 14) == 0)
      found++;
  }
  closedir(d);
  return found;
}

// Print PCIe/driver info for every Rockchip RK182x function found in sysfs.
static void print_pci(void)
{
  DIR* d = opendir("/sys/bus/pci/devices");
  if (!d)
    return;
  struct dirent* e;
  char p[512], v[128], dev[128], drv[512], spd[64], wid[16], mspd[64], mwid[16];
  printf("PCIe:\n");
  int any = 0;
  while ((e = readdir(d))) {
    if (e->d_name[0] == '.')
      continue;
    snprintf(p, sizeof(p), "/sys/bus/pci/devices/%s/vendor", e->d_name);
    if (read_line(p, v, sizeof(v)) || strcmp(v, "0x1d87"))
      continue;
    snprintf(p, sizeof(p), "/sys/bus/pci/devices/%s/device", e->d_name);
    if (read_line(p, dev, sizeof(dev)) || strncmp(dev, "0x182", 5))
      continue;
    any = 1;
    snprintf(p, sizeof(p), "/sys/bus/pci/devices/%s/driver", e->d_name);
    ssize_t n = readlink(p, drv, sizeof(drv) - 1);
    const char* dname = "(none)";
    if (n > 0) {
      drv[n] = 0;
      dname = strrchr(drv, '/') ? strrchr(drv, '/') + 1 : drv;
    }
#define RD(name, buf)                                                          \
  snprintf(p, sizeof(p), "/sys/bus/pci/devices/%s/" name, e->d_name);          \
  if (read_line(p, buf, sizeof(buf)))                                          \
    strcpy(buf, "?");
    RD("current_link_speed", spd);
    RD("current_link_width", wid);
    RD("max_link_speed", mspd);
    RD("max_link_width", mwid);
#undef RD
    printf("  %s  [1d87:%s]  driver=%s\n", e->d_name, dev + 2, dname);
    printf("    link: %s x%s  (max %s x%s)\n", spd, wid, mspd, mwid);
  }
  if (!any)
    printf("  no RK182x PCIe device found\n");
  closedir(d);
}

static void bar(double frac, int width)
{
  int fill = (int)(frac * width + 0.5);
  if (fill < 0) fill = 0;
  if (fill > width) fill = width;
  putchar('[');
  for (int i = 0; i < width; i++)
    putchar(i < fill ? '#' : '.');
  putchar(']');
}

static void print_runtime(int no_ctx)
{
  static rknn3_devices devs; // large struct; keep off the stack
  memset(&devs, 0, sizeof(devs));
  int ret = rknn3_find_devices(&devs);
  if (ret != 0) {
    printf("Runtime: rknn3_find_devices failed (%d) - is rknn3_transfer_proxy running?\n", ret);
    return;
  }
  printf("Devices: %u\n", devs.n_devices);
  for (uint32_t i = 0; i < devs.n_devices; i++) {
    rknn3_device* d = &devs.devices[i];
    rknn3_dev_mem_info* m = &d->mem_info;
    printf("\n[%u] id=%s  type=%s\n", i, d->id, d->type);

    if (m->sys_total) {
      double used = (double)(m->sys_total - m->sys_free);
      printf("    System mem : %7.0f / %7.0f MiB  ", used / MiB, m->sys_total / MiB);
      bar(used / m->sys_total, 30);
      printf(" %5.1f%%\n", 100.0 * used / m->sys_total);
    }
    uint32_t nn = m->node_num < RKNN3_MAX_NPU_NODE_NUM ? m->node_num : RKNN3_MAX_NPU_NODE_NUM;
    uint64_t nt = 0, nf = 0;
    for (uint32_t k = 0; k < nn; k++) {
      nt += m->node_mem_info[k].total;
      nf += m->node_mem_info[k].free;
    }
    if (nn) {
      double used = (double)(nt - nf);
      printf("    NPU mem    : %7.0f / %7.0f MiB  ", used / MiB, nt / MiB);
      bar(nt ? used / nt : 0, 30);
      printf(" %5.1f%%  (%u nodes)\n", nt ? 100.0 * used / nt : 0, nn);
      for (uint32_t k = 0; k < nn; k++) {
        rknn3_node_mem_info* nm = &m->node_mem_info[k];
        double u = (double)(nm->total - nm->free);
        printf("      node %-3u: %7.0f / %7.0f MiB  ", k, u / MiB, nm->total / MiB);
        bar(nm->total ? u / nm->total : 0, 20);
        putchar('\n');
      }
    }

    if (no_ctx)
      continue;
    rknn3_context ctx = 0;
    rknn3_init_extend ext;
    memset(&ext, 0, sizeof(ext));
    ext.device_id = d->id;
    if (rknn3_init(&ctx, &ext) != 0) {
      printf("    (rknn3_init failed; version/core info unavailable)\n");
      continue;
    }
    rknn3_sdk_version ver;
    memset(&ver, 0, sizeof(ver));
    if (rknn3_query(ctx, RKNN3_QUERY_SDK_VERSION, &ver, sizeof(ver)) == 0) {
      printf("    API version: %s\n", ver.api_version);
      printf("    Device drv : %s\n", ver.drv_version);
    }
    uint32_t cores[16] = {0}; // query struct size varies; first field is the count
    if (rknn3_query(ctx, RKNN3_QUERY_CORE_NUMBER, cores, sizeof(cores)) == 0)
      printf("    NPU cores  : %u\n", cores[0]);
    rknn3_destroy(ctx);
  }
}

int main(int argc, char** argv)
{
  int loop = 0, no_ctx = 0, c;
  while ((c = getopt(argc, argv, "l:nh")) != -1) {
    switch (c) {
    case 'l': loop = atoi(optarg); break;
    case 'n': no_ctx = 1; break;
    default:
      printf("usage: %s [-l SECONDS] [-n]\n  -l N  refresh every N seconds\n  -n    skip runtime context (no version/core query)\n", argv[0]);
      return c == 'h' ? 0 : 1;
    }
  }
  do {
    if (loop)
      printf("\033[H\033[2J");
    time_t t = time(NULL);
    char ts[64];
    strftime(ts, sizeof(ts), "%a %b %d %H:%M:%S %Y", localtime(&t));
    printf("rk-smi  %s\n", ts);
    printf("==============================================================\n");
    char mv[64] = "not loaded";
    FILE* f = fopen("/proc/modules", "r");
    if (f) {
      char line[512];
      while (fgets(line, sizeof(line), f))
        if (!strncmp(line, "pcie_rkep ", 10)) {
          strcpy(mv, "loaded");
          break;
        }
      fclose(f);
    }
    int pr = proxy_running();
    printf("Kernel module pcie_rkep: %s   transfer proxy: %s\n", mv,
           pr > 0 ? "running" : (pr == 0 ? "NOT running" : "?"));
    print_pci();
    printf("--------------------------------------------------------------\n");
    if (pr == 0)
      printf("Start the proxy first: sudo rknn3_transfer_proxy &\n");
    else
      print_runtime(no_ctx);
    fflush(stdout);
    if (loop)
      sleep(loop);
  } while (loop);
  return 0;
}
