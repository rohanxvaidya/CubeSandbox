#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/mm.h>
#include <linux/sysfs.h>
#include <linux/kobject.h>

static struct kobject *example_kobj;
static char buffer[20]; // Buffer to hold the input address

// Function to read from a physical address
static ssize_t phy_address_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf) {
    unsigned long phys_addr;
    unsigned long value;

    // Convert input address to a number
    if (sscanf(buffer, "%lx", &phys_addr) != 1) {
        return -EINVAL;
    }

    // Using __va to convert the physical address to a virtual address
    value = *(unsigned long *)__va(phys_addr);
    
    // Return the value as a string
    return snprintf(buf, PAGE_SIZE, "Value at 0x%lx: 0x%lx\n", phys_addr, value);
}

// Function to write to the sysfs node
static ssize_t phy_address_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count) {
    // Copy the input from user space to kernel space
    if (count > sizeof(buffer) - 1) {
        return -EINVAL; // Buffer overflow
    }
    
    strncpy(buffer, buf, count);
    buffer[count] = '\0'; // Null-terminate the string
    return count;
}

// Declare the attribute with the show and store functions
static struct kobj_attribute phy_address_attribute = __ATTR(phy_address, 0664, phy_address_show, phy_address_store);

static int __init phy_address_init(void) {
    int error;

    // Create a kobject in /sys/kernel/
    example_kobj = kobject_create_and_add("phy_address_example", kernel_kobj);
    if (!example_kobj)
        return -ENOMEM;

    // Create the sysfs entry
    error = sysfs_create_file(example_kobj, &phy_address_attribute.attr);
    if (error) {
        kobject_put(example_kobj);
        return error;
    }

    printk(KERN_INFO "phy_address module loaded\n");
    return 0;
}

static void __exit phy_address_exit(void) {
    kobject_put(example_kobj); // Remove the kobject
    printk(KERN_INFO "phy_address module unloaded\n");
}

module_init(phy_address_init);
module_exit(phy_address_exit);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("A sysfs example for reading physical memory addresses");
MODULE_AUTHOR("michael.m.zhang@intel.com");
