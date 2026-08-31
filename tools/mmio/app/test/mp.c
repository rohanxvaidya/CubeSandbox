#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <stdint.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <getopt.h>

#define ECAM_BASE_ADDRESS  0xE0000000  // ECAM base address
#define ECAM_SIZE          0x10000000  // ECAM size
#define PCI_CONFIG_SPACE_SIZE  0x100  // PCI config space size

// Function prototypes
uint64_t get_ecam_address(uint8_t bus, uint8_t device, uint8_t function, uint8_t offset);
void pci_write_config(uint8_t bus, uint8_t device, uint8_t function, uint8_t offset, uint32_t value);
uint32_t pci_read_config(uint8_t bus, uint8_t device, uint8_t function, uint8_t offset);
void mmio_write(uintptr_t mmio_base, uint32_t offset, uint32_t value);
uint32_t mmio_read(uintptr_t mmio_base, uint32_t offset);
void print_usage(const char *prog_name);

void print_usage(const char *prog_name) {
    fprintf(stderr, "Usage: %s -t <pci|memio> -b <bdf|bar_offset> -s <bar_size_hex> -m <r|w> -r <reg_offset_hex> [-v <value>]\n", prog_name);
    fprintf(stderr, "Options:\n");
    fprintf(stderr, "  -t <pci|memio>      Specify the mode of operation.\n");
    fprintf(stderr, "  -b <bdf|bar_offset> Specify BDF for PCI or BAR offset for MMIO.\n");
    fprintf(stderr, "  -s <bar_size_hex>   Specify the size of the BAR in hexadecimal.\n");
    fprintf(stderr, "  -m <r|w>            Specify the operation: read (r) or write (w).\n");
    fprintf(stderr, "  -r <reg_offset_hex> Specify the register offset in hexadecimal.\n");
    fprintf(stderr, "  -v <value>          Specify the value to write (required for write operations).\n");
    fprintf(stderr, "  -h                  Show this help message.\n");
    exit(EXIT_FAILURE);
}

// Function to calculate ECAM address
uint64_t get_ecam_address(uint8_t bus, uint8_t device, uint8_t function, uint8_t offset) {
    return (uint64_t)(ECAM_BASE_ADDRESS + (bus << 20) + (device << 15) + (function << 12) + (offset));
}

// Write to PCI configuration register
void pci_write_config(uint8_t bus, uint8_t device, uint8_t function, uint8_t offset, uint32_t value) {
    uint64_t address = get_ecam_address(bus, device, function, offset);

    // Open /dev/mem for MMIO
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        perror("Failed to open /dev/mem");
        exit(EXIT_FAILURE);
    }

    void *mmio_base = mmap(NULL, ECAM_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, ECAM_BASE_ADDRESS);
    if (mmio_base == MAP_FAILED) {
        perror("mmap failed");
        close(fd);
        exit(EXIT_FAILURE);
    }

    // Write to the configuration register
    *(volatile uint32_t *)(mmio_base + (address - ECAM_BASE_ADDRESS)) = value;

    // Clean up
    munmap(mmio_base, ECAM_SIZE);
    close(fd);
}

// Read from PCI configuration register
uint32_t pci_read_config(uint8_t bus, uint8_t device, uint8_t function, uint8_t offset) {
    uint64_t address = get_ecam_address(bus, device, function, offset);

    // Open /dev/mem for MMIO
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        perror("Failed to open /dev/mem");
        exit(EXIT_FAILURE);
    }

    void *mmio_base = mmap(NULL, ECAM_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, ECAM_BASE_ADDRESS);
    if (mmio_base == MAP_FAILED) {
        perror("mmap failed");
        close(fd);
        exit(EXIT_FAILURE);
    }

    // Read from the configuration register
    uint32_t value = *(volatile uint32_t *)(mmio_base + (address - ECAM_BASE_ADDRESS));

    // Clean up
    munmap(mmio_base, ECAM_SIZE);
    close(fd);

    return value;
}

// Write to MMIO
void mmio_write(uintptr_t mmio_base, uint32_t offset, uint32_t value) {
    *(volatile uint32_t *)(mmio_base + offset) = value;
}

// Read from MMIO
uint32_t mmio_read(uintptr_t mmio_base, uint32_t offset) {
    return *(volatile uint32_t *)(mmio_base + offset);
}

// Main function
int main(int argc, char *argv[]) {
    char *mode = NULL;
    char *b_arg = NULL;
    char *size_arg = NULL;
    char *operation = NULL;
    char *reg_offset_str = NULL;
    char *value_str = NULL;

    int opt;
    while ((opt = getopt(argc, argv, "t:b:s:m:r:v:h")) != -1) {
        switch (opt) {
            case 't':
                mode = optarg;
                break;
            case 'b':
                b_arg = optarg;
                break;
            case 's':
                size_arg = optarg;
                break;
            case 'm':
                operation = optarg;
                break;
            case 'r':
                reg_offset_str = optarg;
                break;
            case 'v':
                value_str = optarg;
                break;
            case 'h':
                print_usage(argv[0]);
                break;
            default:
                print_usage(argv[0]);
        }
    }
#if 0
    // Check required parameters
    if (!mode || !b_arg || !size_arg || !operation || !reg_offset_str) {
        print_usage(argv[0]);
    }

    if (strcmp(mode, "pci") == 0) {
        uint8_t bus, device, function;
        sscanf(b_arg, "%hhx:%hhx.%hhx", &bus, &device, &function);
        uint8_t reg_offset = (uint8_t)strtol(reg_offset_str, NULL, 16);
        
        if (strcmp(operation, "w") == 0) {
            if (!value_str) {
                fprintf(stderr, "Value must be provided for write operation.\n");
                print_usage(argv[0]);
            }
            uint32_t value = (uint32_t)strtol(value_str, NULL, 16);
            pci_write_config(bus, device, function, reg_offset, value);
            printf("Written value 0x%X to PCIe BDF %hhx:%hhx.%hhx at offset 0x%X\n", value, bus, device, function, reg_offset);
        } else if (strcmp(operation, "r") == 0) {
            uint32_t value = pci_read_config(bus, device, function, reg_offset);
            printf("Read value 0x%X from PCIe BDF %hhx:%hhx.%hhx at offset 0x%X\n", value, bus, device, function, reg_offset);
        } else {
            fprintf(stderr, "Invalid operation: %s\n", operation);
            print_usage(argv[0]);
        }

    } else if (strcmp(mode, "memio") == 0) {
        uintptr_t bar_offset = (uintptr_t)strtol(b_arg, NULL, 16);
        size_t bar_size = (size_t)strtol(size_arg, NULL, 16);
        uint8_t reg_offset = (uint8_t)strtol(reg_offset_str, NULL, 16);

        // Open /dev/mem for MMIO
        int fd = open("/dev/mem", O_RDWR | O_SYNC);
        if (fd < 0) {
            perror("Failed to open /dev/mem");
            exit(EXIT_FAILURE);
        }

        void *mmio_base = mmap(NULL, bar_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, bar_offset);
        if (mmio_base == MAP_FAILED) {
            perror("mmap failed");
            close(fd);
            exit(EXIT_FAILURE);
        }

        if (strcmp(operation, "w") == 0) {
            if (!value_str) {
                fprintf(stderr, "Value must be provided for write operation.\n");
                print_usage(argv[0]);
            }
            uint32_t value = (uint32_t)strtol(value_str, NULL, 16);
            mmio_write((uintptr_t)mmio_base, reg_offset, value);
            printf("Written value 0x%X to MMIO at offset 0x%X\n", value, reg_offset);
        } else if (strcmp(operation, "r") == 0) {
            uint32_t value = mmio_read((uintptr_t)mmio_base, reg_offset);
            printf("Read value 0x%X from MMIO at offset 0x%X\n", value, reg_offset);
        } else {
            fprintf(stderr, "Invalid operation: %s\n", operation);
            print_usage(argv[0]);
        }

        // Clean up
        munmap(mmio_base, bar_size);
        close(fd);
    } else {
        fprintf(stderr, "Invalid mode: %s\n", mode);
        print_usage(argv[0]);
    }
#endif
    return 0;
}