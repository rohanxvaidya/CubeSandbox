CONFIG_MODULE_SIG=n
MODULE_NAME = spinlock_bench
ifneq ($(KERNELRELEASE),) 
		obj-m += $(MODULE_NAME).o
#		$(MODULE_NAME)-objs := spinlock_bench.o 
# libcha_hash.o
else
KERNELDIR ?= /lib/modules/$(shell uname -r)/build 
PWD := $(shell pwd)
default: 
		$(MAKE) -C $(KERNELDIR) M=$(PWD) modules
endif 
clean:
		$(MAKE) -C $(KERNELDIR) M=$(PWD) clean
