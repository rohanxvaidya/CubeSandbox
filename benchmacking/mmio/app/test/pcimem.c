#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <stdint.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <sys/io.h>
#include <getopt.h>
#include <immintrin.h>
#include <time.h>
#include <sys/types.h>

// please check the ECAM address on your system with "cat /proc/iomem | grep ECAM"
#define ECAM_BASE_ADDRESS  0x80000000  // ECAM base address, adjust it align with your system.
/* ECAM size will cover 256 bus pci device, for 4k configuration space size.
 * Support 256 bus, 32 devices, 8 function(physical function), 4k reg...
 * = ECAM_BASE_ADDRESS + (bus << 20) + (device << 15) + (function << 12) + (offset) 
**/
#define ECAM_SIZE          0x10000000  // ECAM size
//256 bytes for legacy pci space, 4k for extended configuration space.
//TODO: limit the mem map range size, for safety consideration.
#define PCI_CONFIG_SPACE_SIZE  0x100  // PCI config space size, 

// legacy IO mode for PCIe configuration space access
#define PCI_CONFIG_ADDRESS 0xCF8
#define PCI_CONFIG_DATA    0xCFC

#define DEFAULT_MAP_SIZE    0x1000  //4k
enum mem_mode {
    MODE_PCI=0,
    MODE_MMIO
};

// Function prototypes
uint32_t create_pci_config_address(uint8_t bus, uint8_t device, uint8_t function, uint8_t offset);
uint32_t pci_read_config_legacy(uint8_t bus, uint8_t device, uint8_t function, uint8_t offset);
uint32_t pci_read_config_legacy(uint8_t bus, uint8_t device, uint8_t function, uint8_t offset);

uint64_t get_ecam_address(uint8_t bus, uint8_t device, uint8_t function, uint8_t offset);
uint64_t get_pcie_ecam_base_address(uint8_t bus, uint8_t device, uint8_t function);
void pci_write_config(uint8_t bus, uint8_t device, uint8_t function, uint8_t offset, uint32_t value);
uint32_t pci_read_config(uint8_t bus, uint8_t device, uint8_t function, uint8_t offset);
void mmio_write(uintptr_t mmio_base, uint32_t offset, uint32_t value);
uint32_t mmio_read(uintptr_t mmio_base, uint32_t offset);
void print_usage(const char *prog_name);

__attribute__((noinline)) int heavy_execution_function(void);

static inline void serialize_instruction(void);
int dummy_function(void);

void print_usage(const char *prog_name) {
    fprintf(stderr, "Usage: %s -m <pci|memio> -b <bdf|bar_base_hex> -s <bar_size_hex> -o <r|w> -r <reg_offset_hex> [-v <value>]\n", prog_name);
    fprintf(stderr, "Options:\n");
    fprintf(stderr, "  -m <pci|memio>      Specify the mode of operation.\n");
    fprintf(stderr, "  -b <bdf|bar_base>   Specify BDF for PCI or BAR base address for MMIO. (e.g.0x80000000)\n");
    fprintf(stderr, "  -s <bar_size_hex>   Specify the size of the BAR in hexadecimal.\n");
    fprintf(stderr, "  -o <r|w>            Specify the operation: read (r) or write (w).\n");
    fprintf(stderr, "  -r <reg_offset_hex> Specify the register offset in hexadecimal.\n");
    fprintf(stderr, "  -v <value>          Specify the value to write (required for write operations).\n");
    fprintf(stderr, "  -l <count>          Specify the loop count to read/write operations.\n");
    fprintf(stderr, "  -h                  Show help usage.\n");

    exit(EXIT_FAILURE);
}

// Function to get the current timestamp counter
static uint64_t get_rdtsc()  {
  asm("rdtsc");
}

// Function to get the current timestamp counter
static inline uint64_t my_rdtsc() {
    unsigned int lo, hi;
    __asm__ __volatile__ (
        "rdtsc"            // Read the time-stamp counter
        : "=a" (lo), "=d" (hi)  // Output: low and high parts
    );
    return ((uint64_t)hi << 32) | lo; // Combine high and low parts
}

static inline void serialize_instruction(void){
    asm volatile(".byte 0xf, 0x1, 0xe8" ::: "memory");
}

__attribute__((noinline)) int heavy_execution_function(void)
{
    //TODO: do something heavy computing.
    return 0;
}

int dummy_function(void) {
    serialize_instruction();
    return 0;
}


/*** Legacy mode for PCIe configuration space access ***/
// Function to create the configuration address
uint32_t create_pci_config_address(uint8_t bus, uint8_t device, uint8_t function, uint8_t offset)
{
    return (uint32_t)(0x80000000 | (bus << 16) | (device << 11) | (function << 8) | (offset & 0xFC));
}

// Function to write to a PCI configuration register
void pci_write_config_legacy(uint8_t bus, uint8_t device, uint8_t function, uint8_t offset, uint32_t value)
{
    uint32_t address = create_pci_config_address(bus, device, function, offset);

    // Write address to the PCI config address port
    outl(PCI_CONFIG_ADDRESS, address);
    
    // Write value to the PCI config data port
    outl(PCI_CONFIG_DATA, value);
}

// Function to read from a PCI configuration register
uint32_t pci_read_config_legacy(uint8_t bus, uint8_t device, uint8_t function, uint8_t offset)
{
    uint32_t address = create_pci_config_address(bus, device, function, offset);
    
    // Write address to the PCI config address port
    outl(PCI_CONFIG_ADDRESS, address);
    
    // Read value from the PCI config data port
    return inl(PCI_CONFIG_DATA);
}

/*** ECAM mode for PCIe configuration space access */
// Function to calculate ECAM address
uint64_t get_ecam_address(uint8_t bus, uint8_t device, uint8_t function, uint8_t offset) 
{
    uint64_t conf_address = ECAM_BASE_ADDRESS + (bus << 20) + (device << 15) + (function << 12) + (offset);
    printf("PCI Configuration Space MMIO Address for BDF %hhx:%hhx.%hhx at offset 0x%X is [ 0x%llx ] \n", bus, device, function, offset, conf_address);

    return (uint64_t)(conf_address);
}

uint64_t get_pcie_ecam_base_address(uint8_t bus, uint8_t device, uint8_t function) 
{
    return get_ecam_address(bus, device, function, 0);
}

// Write to PCI configuration register
void pci_write_config(uint8_t bus, uint8_t device, uint8_t function, uint8_t offset, uint32_t value) 
{
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
uint32_t pci_read_config(uint8_t bus, uint8_t device, uint8_t function, uint8_t offset) 
{
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
void mmio_write(uintptr_t mmio_base, uint32_t offset, uint32_t value) 
{
    *(volatile uint32_t *)(mmio_base + offset) = value;
}

// Read from MMIO
uint32_t mmio_read(uintptr_t mmio_base, uint32_t offset) 
{
    return *(volatile uint32_t *)(mmio_base + offset);
}

// Main function
int main(int argc, char *argv[]) 
{
    uint64_t bar_base_addr = 0;
    size_t bar_size = DEFAULT_MAP_SIZE;
    char operation = 0;
    off_t reg_offset = 0;
    uint32_t loop_count = 1, value = 0;
    int write_value_set = 0, reg_offset_set = 0, base_address_set = 0, loop_count_set;
    int m_mode = MODE_MMIO;  // 0 for pcie ECAM mode , 1 for MMIO mode.
    char *mode = NULL;
    char *b_arg = NULL;
    uint64_t t1 = 0, t2 = 0;

    int opt;
    while ((opt = getopt(argc, argv, "m:b:s:o:r:v:l:h")) != -1) {
        switch (opt) {
            case 'm':
                mode = optarg;
                if (strcmp(mode, "pci") == 0 ) {
                    m_mode = MODE_PCI;
                } else if (strcmp(mode, "memio") == 0) {
                    m_mode = MODE_MMIO;
                }else {
                    /* if (strcmp(mode, "pci") != 0 && (strcmp(mode, "memio") != 0) */
                    fprintf(stderr, "Invalid mode: %s\n", mode);
                    print_usage(argv[0]);
                }
                break;
            case 'b':
                //bar_base_addr = strtoull(optarg, NULL, 0);
                b_arg = optarg;
                break;
            case 's':
                //bar_size = strtoul(optarg, NULL, 10);
                bar_size = strtoull(optarg, NULL, 0);
                //size_t bar_size = (size_t)strtol(size_arg, NULL, 16);
                break;
            case 'o':
                operation = optarg[0];
                if (operation != 'r' && operation != 'w') {
                    fprintf(stderr, "Invalid operation. Use 'r' for read or 'w' for write.\n");
                    print_usage(argv[0]);
                }
                break;
            case 'r':
                reg_offset = strtoull(optarg, NULL, 0);
                reg_offset_set = 1;
                break;
            case 'v':
                value = strtoul(optarg, NULL, 0);
                write_value_set = 1;
                break;
            case 'l':
                loop_count = strtoul(optarg, NULL, 0);
                loop_count_set = 1;
                break;
            case 'h':
                print_usage(argv[0]);
                break;
            default:
                print_usage(argv[0]);
        }
    }


    // Parse the Address for pcie/mmio mode
    if (mode) {
        if ( m_mode == MODE_PCI ) {
            uint8_t bus, device, function;
            sscanf(b_arg, "%hhx:%hhx.%hhx", &bus, &device, &function);
            bar_base_addr = get_pcie_ecam_base_address(bus, device, function);
            base_address_set = 1;

        } else if ( m_mode == MODE_MMIO ) {
            bar_base_addr = (uint64_t)strtol(b_arg, NULL, 16);
            //size_t bar_size = (size_t)strtol(size_arg, NULL, 16);
            base_address_set = 1;
        }
    }

    if (operation == 'w' && !write_value_set) {
        fprintf(stderr, "Value must be specified for write operation.\n");
        print_usage(argv[0]);
    }

    // Check required parameters
    if (!base_address_set || !reg_offset_set || !bar_size || !operation ) {
        print_usage(argv[0]);
    }

    // each read/write , it's dword.
    if ( bar_size + 4 <  reg_offset) {
        fprintf(stderr, "Offset size [%x] is out of the map range [%x].\n", reg_offset, bar_size);
        print_usage(argv[0]);
    }

// Function execution
    // 1. Open /dev/mem for MMIO
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        perror("Failed to open /dev/mem");
        exit(EXIT_FAILURE);
    }

    // 2. map the memory range
    void *mmio_base = mmap(NULL, bar_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, bar_base_addr);
    // For pci ECAM space, we call map all ECAM space once time.
    //void *mmio_base = mmap(NULL, ECAM_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, ECAM_BASE_ADDRESS);

    if (mmio_base == MAP_FAILED) {
        perror("mmap failed");
        close(fd);
        exit(EXIT_FAILURE);
    }

    // Here we can add some heavy execution before MMIO read/write
    // heavy_execution_function();

    // 3. Do read/write operatons. 
    if ((operation == 'w' && write_value_set == 1)) {
        for(int i = 0; i < loop_count; i++){
            //reg_offset += i * 4;

            t1 = get_rdtsc();
            mmio_write((uintptr_t)mmio_base, reg_offset, value);
            dummy_function();
            t2 = get_rdtsc();

            printf("Written value 0x%X to MMIO at offset 0x%X, duration cycle: %lld\n", value, reg_offset, t2 - t1);
        }
    } else if (operation == 'r') {
        for(int i = 0; i < loop_count; i++){
            //reg_offset += i * 4;

            t1 = get_rdtsc();
            value = mmio_read((uintptr_t)mmio_base, reg_offset);
            dummy_function();
            t2 = get_rdtsc();

            //printf("Read value 0x%X from MMIO at offset 0x%X\n", value, reg_offset);
            printf("Read value 0x%X from MMIO at offset 0x%X, duration cycle: %lld\n", value, reg_offset, t2-t1);
        }
    } else {
        fprintf(stderr, "Invalid operation: %s\n", operation);
        print_usage(argv[0]);
    }

    // 4. Clean up mem map and close handler.
    munmap(mmio_base, bar_size);
    //munmap(mmio_base, ECAM_SIZE);
    close(fd);

    return 0;
}