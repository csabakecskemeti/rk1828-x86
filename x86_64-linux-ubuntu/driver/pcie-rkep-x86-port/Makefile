obj-m += pcie-rkep.o
ccflags-y += -I$(src) -DCONFIG_PCIE_DW_DMATEST=1
KDIR ?= /lib/modules/$(shell uname -r)/build
all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules
clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
