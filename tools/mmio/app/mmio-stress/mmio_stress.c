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

#define FORCE_BUILD_INLINE  0
#define PM_VERSION  "1.1c"
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

enum instruction_post {
    POST_NON=0,
    POST_SERIALIZE=1,
    POST_LOCK=2,
    POST_PAUSE=3,
    POST_MFENCE=4,

    POST_LAST,
    POST_PAUSE_100=100
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

static __attribute__((noinline)) int heavy_execution_function(void);
#if FORCE_BUILD_INLINE
static inline __attribute__((always_inline)) void lock_inc(uint64_t * addr);
static inline __attribute__((always_inline)) void serialize_instruction(void);
static inline __attribute__((always_inline)) int dummy_function(int flag);
#else 
static inline void lock_inc(uint64_t * addr);
static void serialize_instruction(void);
static inline int dummy_function(int flag);

#endif

const char* get_instruction_name(int flag);

static uint64_t inline get_rdtscp(void);
static inline void sfence(void);
static inline void mfence(void);
void pause_cycle(uint64_t iterations);

void print_usage(const char *prog_name) {
    fprintf(stderr, "Usage: %s -b <bar_base_hex> -s <bar_size_hex> -o <r|w> -r <reg_offset_hex> [-v <value>] [other options]\n", prog_name);
    fprintf(stderr, "Options: (V%s)\n", PM_VERSION);
    fprintf(stderr, "  -b <bar_base>       Specify the PCI BAR base address for MMIO. \n");
    fprintf(stderr, "  -s <bar_size_hex>   Specify the size of the BAR in hexadecimal.\n");
    fprintf(stderr, "  -o <r|w|m>          Specify the operation: read (r) or write (w) or mixed r/w (m).\n");
    fprintf(stderr, "  -r <reg_offset_hex> Specify the register offset in hexadecimal.\n");
    fprintf(stderr, "  -v <value>          Specify the value to write (required for write operations).\n");
    fprintf(stderr, "  -l <count>          Specify the loop count to read/write operations.\n");
    fprintf(stderr, "  -M <0|1|2>          Ouput messsage mode, by default is full message (2), \n\
                        0 - Quiet mode for MMIO ops, no message output \n\
                        1 - Simple message mode for MMIO ops, \n\
                        2 - Full message mode for MMIO ops, \n");
    fprintf(stderr, "  -c <write_ops>      Specify the Write ops count for each cycle test, default is 4\n");
    fprintf(stderr, "  -h                  Show help usage.\n");

    exit(EXIT_FAILURE);
}

//#define PAUSE1        __asm__ __volatile__(".byte 0x0F, 0x1F")// nop?
#define PAUSE2  __asm__ __volatile__(".byte 0xF3, 0x90")
#define PAUSE3  do {__asm__ __volatile__("pause");} while (0);

void pause_cycle(uint64_t iterations) {
    for (uint64_t i = 0; i < iterations; i++) {
        //__asm__ __volatile__("pause");
        PAUSE2;
    }
}

#if FORCE_BUILD_INLINE
static inline __attribute__((always_inline)) void lock_inc(uint64_t * addr)
#else
static inline void lock_inc(uint64_t * addr)
#endif
{
    __asm__ __volatile__ (
        "lock;"
        "incq %0;"
        : "+m" (*addr)
        :
        : "memory"
    );
}

#if 0
enum {
THIS_STATE_IDLE = 0,
THIS_STATE_RUN = 1,
};

static inline int lock_test_and_set_bit(int bit, uint32_t *addr) {
    int old_value;

    // Use inline assembly to atomically set the bit
    __asm__ __volatile__ (
        "lock;"
        "bts %1, %2\n\t"  // Atomically set the bit
        "sbb %0, %0"           // Set old_value to 1 if bit was already set, otherwise 0
        : "=r"(old_value), "+m"(*addr) // Output: old_value, address modified
        : "Ir"(bit)            // Input: bit index
        : "memory"             // Clobbers memory
    );
    return old_value; // Return the previous value of the bit
}
#endif

// Function to get the current timestamp counter
static uint64_t get_rdtsc()  {
  asm("rdtsc");
}

static inline void sfence(void) {
    __asm__ __volatile__ ("sfence" ::: "memory");
}

// Ensure memory operations are completed with mfence
static inline void mfence(void)
{
    __asm__ __volatile__ ("mfence" ::: "memory");
}

static uint64_t inline get_rdtscp(void) {
    uint32_t lo, hi;
    __asm__ __volatile__ (
        "rdtscp" : "=a" (lo), "=d" (hi) :: "%rcx"
    );
    return ((uint64_t)hi << 32) | lo;
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

#if FORCE_BUILD_INLINE
static inline __attribute__((always_inline)) void serialize_instruction(void)
#else 
static void serialize_instruction(void)
#endif
{
    asm volatile(".byte 0xf, 0x1, 0xe8" ::: "memory");
}

__attribute__((noinline)) int heavy_execution_function(void)
{
    //TODO: do something heavy computing.
    pause_cycle(1);
    return 0;
}

#if FORCE_BUILD_INLINE
static inline __attribute__((always_inline)) int dummy_function(int flag)
#else 
static inline int dummy_function(int flag)
#endif
{
    uint64_t value = 0x5A;
    switch ((enum instruction_post) flag) {
        case POST_NON:
            break;
        case POST_SERIALIZE:
            serialize_instruction();
            break;
        case POST_LOCK:
            lock_inc(&value);
            break;
        case POST_PAUSE:
            pause_cycle(1);
            break;
        case POST_MFENCE:
            mfence();
            break;
        default:
            return 0;
    }

    return 0;
}

const char* get_instruction_name(int flag)
{
    switch ((enum instruction_post) flag) {
        case POST_NON:
            return "NONE";
            break;
        case POST_SERIALIZE:
            return "serialize";
            break;
        case POST_LOCK:
            return "LOCK#";
            break;
        case POST_PAUSE:
            return "PAUSE";
            break;
        case POST_MFENCE:
            return "mFENCE";
            break;
        default:
            return NULL;
    }

    return NULL;    
}

/*** ECAM mode for PCIe configuration space access */
// Function to calculate ECAM address
uint64_t get_ecam_address(uint8_t bus, uint8_t device, uint8_t function, uint8_t offset) 
{
    uint64_t conf_address = ECAM_BASE_ADDRESS + (bus << 20) + (device << 15) + (function << 12) + (offset);
    printf("PCI Configuration Space MMIO Address for BDF %hhx:%hhx.%hhx at offset 0x%X is [ 0x%lx ] \n", \
    bus, device, function, offset, conf_address);

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
    value = value & 0xFFFFFFFF;
    *(volatile uint32_t *)(mmio_base + offset) = value;
    sfence();
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
    uint32_t loop_count = 1, value = 0, post_flag = POST_LOCK, message_mode = 2, write_count = 4;
    int write_value_set = 0, reg_offset_set = 0, base_address_set = 0, loop_count_set;
    int m_mode = MODE_MMIO;  // 0 for pcie ECAM mode , 1 for MMIO mode.
    char *mode = "MMIO";
    char *b_arg = NULL;
    uint64_t t1 = 0, t2 = 0;

    int opt;
    while ((opt = getopt(argc, argv, "b:s:o:r:v:l:M:c:h")) != -1) {
        switch (opt) {
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
                if (operation != 'r' && operation != 'w' && operation != 'm') {
                    fprintf(stderr, "Invalid operation. Use 'r' for read or 'w' for write or 'm' for mixed r/w.\n");
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
            case 'M':
                message_mode = strtoul(optarg, NULL, 0);
                if (message_mode >= 2)
                    message_mode = 2;
                break;
            case 'c':
                write_count = strtoul(optarg, NULL, 0);
                if (write_count < 1 ) {
                    fprintf(stderr, "Write ops count should be >= 1 !!\n");
                    print_usage(argv[0]);
                }
                break;
            case 'h':
                print_usage(argv[0]);
                break;
            default:
                print_usage(argv[0]);
        }
    }

    // Parse the Address for pcie/mmio mode
//    if (mode) {
        if ( m_mode == MODE_PCI ) {
            uint8_t bus, device, function;
            sscanf(b_arg, "%hhx:%hhx.%hhx", &bus, &device, &function);
            bar_base_addr = get_pcie_ecam_base_address(bus, device, function);
            base_address_set = 1;

        } else if ( m_mode == MODE_MMIO ) {
            if (b_arg) {
                bar_base_addr = (uint64_t)strtol(b_arg, NULL, 16);
                //size_t bar_size = (size_t)strtol(size_arg, NULL, 16);
                base_address_set = 1;
            }
        }
//    }

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
        fprintf(stderr, "Offset size [%lx] is out of the map range [%lx].\n", reg_offset, bar_size);
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

    //Do execution
    printf("Selected '%s' Mode, Do [%s] ops to MMIO address 0x%lx at offset 0x%lX, with [%s] instruction, loop count:%d, write ops count: %d\n", \
    mode, (operation == 'w') ? "Write" : "Read", \
    bar_base_addr, reg_offset, \
    get_instruction_name(post_flag), \
    loop_count, write_count);

    struct timespec start_run, end_run;
    unsigned long duration_us, nanoseconds, seconds;
    // Get the starting time
    clock_gettime(CLOCK_MONOTONIC, &start_run);

    // Here we can add some heavy execution before MMIO read/write
    // heavy_execution_function();

    // 3. Do read/write operatons. 
    if ((operation == 'w' && write_value_set == 1)) {
        for(int i = 0; i < loop_count; i++){
            //reg_offset += i * 4;

            //t1 = get_rdtsc();
            t1 = get_rdtscp();
            for (int j = 0 ; j < write_count; j++ ) {
                mmio_write((uintptr_t)mmio_base, reg_offset, value);
                value = value + 0x5A;
            }
            // mmio_write((uintptr_t)mmio_base, reg_offset, value);
            // value = value + 0x5A;
            // mmio_write((uintptr_t)mmio_base, reg_offset, value);
            // value = value + 0x80;
            // mmio_write((uintptr_t)mmio_base, reg_offset, value);
            // value = value + 0xF0;
            // mmio_write((uintptr_t)mmio_base, reg_offset, value);

            dummy_function(post_flag);  //serialize /lock#/ pause instrution
            t2 = get_rdtscp();
            //t2 = get_rdtsc();

            if (message_mode == 2) 
                printf("Written value 0x%X to MMIO at offset 0x%lX\n", value, reg_offset);
            else if (message_mode == 1)
                printf("Written 0x%X\n", value);
        }
    } else if (operation == 'r') {
        for(int i = 0; i < loop_count; i++){
            //reg_offset += i * 4;

            t1 = get_rdtscp();
            value = mmio_read((uintptr_t)mmio_base, reg_offset);
            dummy_function(post_flag);
            t2 = get_rdtscp();

            if (message_mode == 2) 
                printf("Read value 0x%X from MMIO at offset 0x%lX \n", value, reg_offset);
            else if (message_mode == 1)
                printf("Read 0x%X\n", value);
        }
    } else if (operation == 'm') {
        value = 0x55AA55AA;
        for(int i = 0; i < loop_count; i++){

            t1 = get_rdtscp();

            // value = value + 0x5A;
            // mmio_write((uintptr_t)mmio_base, reg_offset, value);    //write first
            for (int j = 0 ; j < write_count; j++ ) {
                mmio_write((uintptr_t)mmio_base, reg_offset, value);
                value = value + 0x5A;
            }
            dummy_function(post_flag);
            value = mmio_read((uintptr_t)mmio_base, reg_offset);    //then read
            //dummy_function(post_flag);
            t2 = get_rdtscp();

            if (message_mode == 2) 
                printf("Read value 0x%X from MMIO at offset 0x%lX \n", value, reg_offset);
            else if (message_mode == 1)
                printf("Read 0x%X \n", value);
        }
    } else {
        fprintf(stderr, "Invalid operation: %c\n", operation);
        print_usage(argv[0]);
    }

    // End of the execution
    // Get the ending time
    clock_gettime(CLOCK_MONOTONIC, &end_run);

    // Calculate the duration in microseconds
    seconds = end_run.tv_sec - start_run.tv_sec;
    nanoseconds = end_run.tv_nsec - start_run.tv_nsec;
    duration_us = (seconds * 1e6) + (nanoseconds / 1000);

    printf("End of the test! \n");
    //printf("Duration of the total execution: %ld us \n", duration_us);


    // 4. Clean up mem map and close handler.
    munmap(mmio_base, bar_size);
    //munmap(mmio_base, ECAM_SIZE);
    close(fd);

    return 0;
}
