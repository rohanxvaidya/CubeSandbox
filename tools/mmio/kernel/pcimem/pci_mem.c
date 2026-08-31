#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/pci.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/mm.h>
#include <linux/kobject.h>
#include <linux/sched.h>
#include <linux/delay.h>
#include <linux/workqueue.h>


/*
* user guide,
* 1. load kernel module:  
*   - sudo insmod pcie_mmio.ko bus_number=0 device_number=1 function_number=0
*   Set Loop Count:
    echo 10 > /sys/kernel/pcimem/loop_count

    Set Register Offset:
    echo 0x10 > /sys/kernel/pcimem/offset

    Set Operation (read/write):
    echo "write" > /sys/kernel/pcimem/ops

    Set Value to Write:
    echo 0xDEADBEEF > /sys/kernel/pcimem/value

    Start the Operation:
    echo 1 > /sys/kernel/pcimem/start

    Stop the Operation:
    echo 0 > /sys/kernel/pcimem/start
*/

#define DEVICE_BAR 0  // Assume the device uses the first BAR
#define PCIE_DOMAIN     0 // by default domain = 0
#define DEVICE_NAME "pci_mmio"
#define SYSFS_DIR_NAME "pcimem"
#define MAX_LOOP_COUNT 100

static unsigned int bus_number;
static unsigned int device_number;
static unsigned int function_number;

static struct pci_dev *pdev;
static void __iomem *mmio_base;
static phys_addr_t base_phys_addr;
static unsigned long bar_address_range;


static unsigned int loop_count = 1;
static unsigned int offset = 0;
static char operation[8] = "read"; // Default operation
static unsigned int value = 0;
static bool operation_enabled = false; // Flag to control the operation
static struct work_struct my_work; // Work structure for delayed execution

module_param(bus_number, uint, 0);
MODULE_PARM_DESC(bus_number, "Bus number of the PCIe device");

module_param(device_number, uint, 0);
MODULE_PARM_DESC(device_number, "Device number of the PCIe device");

module_param(function_number, uint, 0);
MODULE_PARM_DESC(function_number, "Function number of the PCIe device");


noinline int heavy_execution_function(void);
int dummy_function(void);
static uint64_t inline get_rdtscp(void);

static uint64_t inline get_rdtscp(void) {
    uint32_t lo, hi;
    __asm__ __volatile__ (
        "rdtscp" : "=a" (lo), "=d" (hi) :: "%rcx"
    );
    return ((uint64_t)hi << 32) | lo;
}

// Function to read the time-stamp counter
static inline unsigned long long read_tsc(void) {
    unsigned long long tsc;
    asm volatile ("rdtsc" : "=A"(tsc));
    return tsc;
}

static inline void serialize_instruction(void){
    asm volatile(".byte 0xf, 0x1, 0xe8" ::: "memory");
}

noinline int heavy_execution_function(void)
{
    //TODO: do something heavy computing.
    return 0;
}

int dummy_function(void) {
    serialize_instruction();
    return 0;
}

// Write to MMIO
static void mmio_write( uintptr_t * base, uint32_t offset, uint32_t value) 
{
    *(volatile uint32_t *)(base + offset) = value;
}

// Read from MMIO
static uint32_t mmio_read( uintptr_t * base, uint32_t offset) 
{
    return *(volatile uint32_t *)(base + offset);
}


// Function to perform read/write operations
static void perform_operations(struct work_struct *work) {
    if (operation_enabled) {

        printk(KERN_INFO "Start the operation for %s.. \n", operation);

        for (unsigned int i = 0; i < loop_count; i++) {
            unsigned long long start, end, duration;

            if (strcmp(operation, "write") == 0) {

                //start = read_tsc(); // Read TSC before the operation
                start = get_rdtscp();
                //*((volatile unsigned int *)(mmio_base + offset)) = value;
                mmio_write(mmio_base, offset, value);
                serialize_instruction();
                wmb();

                //end = read_tsc(); // Read TSC after the operation
                end = get_rdtscp();

                duration = end - start; // Calculate duration
                printk(KERN_INFO "Write operation: TSC duration = %llu cycles, value = 0x%X on address 0x%pa with offset %x \n", duration, value, &base_phys_addr, offset);
            } else if (strcmp(operation, "read") == 0) {

                //start = read_tsc(); // Read TSC before the operation
                start = get_rdtscp();
                //value = *((volatile unsigned int *)(mmio_base + offset));
                value = mmio_read((uintptr_t *)mmio_base, offset);
                serialize_instruction();
                wmb();
                end = get_rdtscp();
                //end = read_tsc(); // Read TSC after the operation

                duration = end - start; // Calculate duration
                printk(KERN_INFO "Read operation: TSC duration = %llu cycles, value = 0x%X on address 0x%pa with offset %x \n", duration, value, &base_phys_addr, offset);
            }
            // Add a small delay to prevent overwhelming the bus
            udelay(10);
        }

        msleep(1000);  // sleep 1s before next cycle loop.

        // Re-schedule the work if still enabled
        // schedule_work(&my_work);
    }
}

// Sysfs attribute show/store functions
static ssize_t loop_count_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf) {
    return sprintf(buf, "%u\n", loop_count);
}

static ssize_t loop_count_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count) {
    sscanf(buf, "%u", &loop_count);
    if (loop_count > MAX_LOOP_COUNT) {
        loop_count = MAX_LOOP_COUNT; // Limit the loop count
    }
    return count;
}

static ssize_t offset_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf) {
    return sprintf(buf, "0x%x\n", offset);
}

static ssize_t offset_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count) {
    sscanf(buf, "0x%x", &offset);
    return count;
}

static ssize_t ops_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf) {
    return sprintf(buf, "%s\n", operation);
}

static ssize_t ops_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count) {
    sscanf(buf, "%6s", operation);
    return count;
}

static ssize_t value_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf) {
    return sprintf(buf, "%u\n", value);
}

static ssize_t value_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count) {
    sscanf(buf, "%u", &value);
    return count;
}

// New sysfs attribute for starting/stopping the operation
static ssize_t start_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf) {
    return sprintf(buf, "%d\n", operation_enabled);
}

static ssize_t start_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count) {
    int tmp;
    sscanf(buf, "%d", &tmp);
    if (tmp == 1) {
        operation_enabled = true; // Enable the operation
        printk(KERN_INFO "Start the operation... \n");
        //perform_operations(&my_work);
        schedule_work(&my_work);      // Start the operation loop
    } else if (tmp == 0) {
        operation_enabled = false; // Disable the operation
        printk(KERN_INFO "Stop the operation... \n");
    }
    return count;
}

// Define the attribute group
static struct kobj_attribute loop_count_attr = __ATTR(loop_count, 0664, loop_count_show, loop_count_store);
static struct kobj_attribute offset_attr = __ATTR(offset, 0664, offset_show, offset_store);
static struct kobj_attribute ops_attr = __ATTR(ops, 0664, ops_show, ops_store);
static struct kobj_attribute value_attr = __ATTR(value, 0664, value_show, value_store);
static struct kobj_attribute start_attr = __ATTR(start, 0664, start_show, start_store);

static struct attribute *attrs[] = {
    &loop_count_attr.attr,
    &offset_attr.attr,
    &ops_attr.attr,
    &value_attr.attr,
    &start_attr.attr,
    NULL, // Null terminate the array
};

static struct attribute_group attr_group = {
    .attrs = attrs,
};

static struct kobject *pcie_kobj;

static int __init pcie_mmio_init(void) {
    int ret;
    int pci_domain = PCIE_DOMAIN, dev_bar_id = DEVICE_BAR;

    // Get the PCI device
    pdev = pci_get_domain_bus_and_slot(pci_domain, bus_number, PCI_DEVID(device_number, function_number));
    if (!pdev) {
        printk(KERN_ERR "Device not found (Bus: 0x%x, Device: 0x%x, Function: 0x%x)\n", bus_number, device_number, function_number);
        return -ENODEV;
    }

    // Enable the PCI device
    ret = pci_enable_device(pdev);
    if (ret) {
        printk(KERN_ERR "Failed to enable device\n");
        return ret;
    }

    // Get the physical address from the BAR
    base_phys_addr = pci_resource_start(pdev, dev_bar_id);
    printk(KERN_INFO "Physical address: 0x%pa, on PCI device %hhx:%hhx:%hhx.%hhx \n", &base_phys_addr, dev_bar_id, bus_number, device_number, function_number);
    bar_address_range = pci_resource_len(pdev, dev_bar_id);

    printk(KERN_INFO "Memory map range is 0x%lx \n", bar_address_range);
    // Map the MMIO region using the size of the BAR
    mmio_base = ioremap(base_phys_addr, bar_address_range);
    // ioremap_wc(); //write combine.
    //mmio_base = ioremap_cache(base_phys_addr, pci_resource_len(pdev, dev_bar_id));
    if (!mmio_base) {
        printk(KERN_ERR "Failed to ioremap\n");
        pci_disable_device(pdev);
        return -EIO;
    }

    // Initialize the work structure
    INIT_WORK(&my_work, perform_operations);

    // Create sysfs directory
    pcie_kobj = kobject_create_and_add(SYSFS_DIR_NAME, kernel_kobj);
    if (!pcie_kobj) {
        printk(KERN_ERR "Failed to create sysfs directory\n");
        iounmap(mmio_base);
        pci_disable_device(pdev);
        return -ENOMEM;
    }

    // Create sysfs files
    ret = sysfs_create_group(pcie_kobj, &attr_group);
    if (ret) {
        kobject_put(pcie_kobj);
        iounmap(mmio_base);
        pci_disable_device(pdev);
        return ret;
    }

    printk(KERN_INFO "PCIe MMIO module loaded for Bus: 0x%x, Device: 0x%x, Function: 0x%x\n", bus_number, device_number, function_number);
    return 0;
}

static void __exit pcie_mmio_exit(void) {
    // Clean up
    cancel_work_sync(&my_work); // Ensure the work is stopped
    sysfs_remove_group(pcie_kobj, &attr_group);
    kobject_put(pcie_kobj);
    iounmap(mmio_base);
    pci_disable_device(pdev);
    printk(KERN_INFO "PCIe MMIO module unloaded\n");
}

module_init(pcie_mmio_init);
module_exit(pcie_mmio_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Your Name");
MODULE_DESCRIPTION("PCIe MMIO Access Module with TSC Timing");