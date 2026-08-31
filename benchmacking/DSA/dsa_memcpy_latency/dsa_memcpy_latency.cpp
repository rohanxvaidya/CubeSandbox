#include <dirent.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>
#include <algorithm>
#include <vector>
#include <linux/idxd.h>
#include <x86intrin.h>
#include <libpmem.h>
//#include <libpmem2.h>
#include <immintrin.h>
#include <time.h>
#include <sys/types.h>
#include <unistd.h>
#include <linux/memfd.h>
#include <linux/mempolicy.h>
//#include <sys/mempolicy.h>
#include <stdint.h>
#include <errno.h>

//For NUMA memory allocation
#include <sys/syscall.h>
#include <numa.h>

#define DSA_BENCH_VERSION   "1.5"

double TSC_GHZ = 3;  //// assume it's 3, need to check the system if you want to more accurate.
unsigned int platform_crystal_hz;
unsigned long long tsc_hz;
unsigned long long tsc_mhz;

#define PAGE_SIZE_INDEX     0 // 0-4k, 1,2M, 

static size_t block_size = 4 * 1024ULL;
static char dev_path[512];
static char dsa_wq_path[512];
static void* dsa_wq_portal = NULL;
static size_t iteration = 10000ULL;
static size_t dev_size = 1024ULL * 1024ULL * 1024ULL;
static char* device_mem_ptr;
static int is_write = 0;
static int cpu_num = 0;
static int use_mem = 0;
static size_t iodepth = 1;
static int data_model = 0;  // 0- both header + DATA; 1- only header;  2 - only DATA;

static size_t submit_retry = 0;
static uint32_t idle_interval = 10;
static int do_with_cpu = 0;
static uint32_t print_threshold = 16000;    //only print the latency value large than 16us 
static uint32_t usleep_time  = 30;   //by default sleep 30us between two ops;
static int mlock_enable = 1;
static int use_tsc = 1;
static int with_fence = 0;
static int debug_mode = 0;
static int wq_portal_sw = 0;
static int wait_function = 1;   // 0- usleep ; 1- busyloop.
static int dedicated_wq = 0;    //shared wq; dedicated wq;
static int dsa_readback_mode = 1; // DSA with readback flag;


static int verify_data = 0;     // verify data or not after memcopy.
static int strict_ordering_enable = 0;  // set the strict ordering for DSA copy.
static uint64_t aggregate_ops = 1;  // we calculate the avrage latency for aggregated ops. 
static int dsa_wq_used = 0;
static int cpu_readback_mode = 0;   // 0; no readback for cpu; 1- readback last address; 2 - readback all;
static int prefill_data = 1;    // prefille data before memory copy.
static int fence_type = 1;  // 0-no fence; 1-sfence; 2-mfence;

// for NUMA node:
static int numa_node = 999; // default is 999, no numa setting.
static int set_numa_node = 0;
static int dax_dev_set = 0;

static int message_mode = 2;
off_t reg_offset = 0;
char operation = 0;
uint32_t loop_count = 1, write_value = 0, write_count = 4;
int write_value_set = 0, reg_offset_set = 0, base_address_set = 0, loop_count_set, single_latency_mode = 0;
uint64_t t1 = 0, t2 = 0;


typedef struct {
    struct dsa_completion_record comp __attribute__((aligned(64)));
    struct dsa_hw_desc desc __attribute__((aligned(64)));
} dsa_task_t; // 96 bytes

// typedef struct {
//     struct dsa_completion_record comp;
//     struct dsa_hw_desc desc;
// } dsa_task_t; // 96 bytes

// Structure to hold CPUID register outputs (EAX/EBX/ECX/EDX)
typedef struct {
    uint32_t eax;  // Primary return register for CPUID function results
    uint32_t ebx;  // Secondary return register
    uint32_t ecx;  // Tertiary return register (subleaf/flags)
    uint32_t edx;  // Quaternary return register
} cpuid_regs_t;

/**
 * Execute the CPUID instruction with specified leaf and subleaf
 * @param leaf: Main CPUID function number (e.g., 0x15)
 * @param subleaf: Subfunction number (0 for basic 0x15 usage)
 * @param regs: Pointer to struct to store register results
 */
static inline void cpuid(uint32_t leaf, uint32_t subleaf, cpuid_regs_t *regs) {
    // Memory barrier to prevent instruction reordering (critical for accuracy)
    __asm__ __volatile__ (
        "cpuid"  // x86 CPUID instruction
        : "=a"(regs->eax), "=b"(regs->ebx), "=c"(regs->ecx), "=d"(regs->edx)  // Outputs
        : "a"(leaf), "c"(subleaf)                                            // Inputs (EAX=leaf, ECX=subleaf)
        : "memory"  // Tell compiler memory may change (disable optimizations)
    );
}

/**
 * Check if CPUID 0x15 is supported by the processor
 * @return true if supported, false otherwise
 */
bool is_cpuid_0x15_supported() {
    cpuid_regs_t regs;
    // First read CPUID 0x0 to get maximum supported leaf number
    cpuid(0x0, 0, &regs);
    uint32_t max_supported_leaf = regs.eax;

    // CPUID 0x15 is only valid if max leaf >= 0x15 (Intel x86 CPUs only)
    return (max_supported_leaf >= 0x15);
}

/**
 * Read and parse CPUID 0x15 register values
 * CPUID 0x15: TSC (Time Stamp Counter) / Core Clock Ratio (Intel-specific)
 */
void check_tsc_frequency_cpuid() {
    cpuid_regs_t regs;
    //set default:
    tsc_mhz = (uint64_t) (TSC_GHZ * 1000);

    // Validate CPU support first
    if (!is_cpuid_0x15_supported()) {
        fprintf(stderr, "Error: CPU does not support CPUID 0x15 (non-Intel x86 or legacy architecture)\n");
        fprintf(stderr, "Warning: crystal hz is not ready from cpuid, set tsc frequency to default %ld MHz\n", tsc_mhz);
        return;
    }

    // Execute CPUID 0x15 with subleaf=0 (standard usage)
    cpuid(0x15, 0, &regs);

    // // Print raw register values (hex + decimal)
    // printf("=== CPUID 0x15 Raw Register Values ===\n");
    // printf("EAX: 0x%08X (%u)\n", regs.eax, regs.eax);
    // printf("EBX: 0x%08X (%u)\n", regs.ebx, regs.ebx);
    // printf("ECX: 0x%08X (%u)\n", regs.ecx, regs.ecx);
    // printf("EDX: 0x%08X (%u)\n", regs.edx, regs.edx);
    // printf("\n");

    // Parse TSC/core clock ratio (core logic for CPUID 0x15)
    if (regs.ebx == 0) {
        fprintf(stderr, "Error: EBX=0 - CPU does not provide TSC/core clock ratio data\n");
        fprintf(stderr, "Warning: crystal hz is not ready from cpuid, set tsc frequency to default %ld MHz\n", tsc_mhz);
        return;
    }
    uint32_t eax_crystal = regs.eax;
	uint32_t ebx_tsc = regs.ebx;
    uint32_t crystal_hz = regs.ecx;

    /*
    * CPUID 15H TSC/Crystal ratio, possibly Crystal Hz
    */
    if (ebx_tsc != 0) {
        // printf("CPUID(0x15): eax_crystal: %d ebx_tsc: %d ecx_crystal_hz: %d\n", eax_crystal, ebx_tsc, crystal_hz);

        if (crystal_hz == 0){
            //crystal_hz = platform_crystal_hz;
            fprintf(stderr, "Warning: crystal hz is not ready from cpuid, set tsc frequency to default %ld MHz\n", tsc_mhz);
            return;
        }

        if (crystal_hz) {
            tsc_hz = (unsigned long long)crystal_hz *ebx_tsc / eax_crystal;
            tsc_mhz = tsc_hz / 1000000;
            TSC_GHZ = (double) tsc_mhz / 1000;
                printf("TSC: %lld MHz (%d Hz * %d / %d / 1000000)\n",
                    tsc_mhz, crystal_hz, ebx_tsc, eax_crystal);
        }
    }

}

#define TSCRD1	"lfence; rdtsc;"
#define TSCRD10 TSCRD1 TSCRD1 TSCRD1 TSCRD1 TSCRD1 TSCRD1 TSCRD1 TSCRD1 TSCRD1 TSCRD1 
#define TSCRD100 TSCRD10 TSCRD10 TSCRD10 TSCRD10 TSCRD10 TSCRD10 TSCRD10 TSCRD10 TSCRD10 TSCRD10 

uint32_t rdtsc_overhead = 0;

#define THE_TSC rdtsc()
static inline unsigned long
rdtsc()
{
	unsigned long var;
	unsigned int hi, lo;
	asm volatile(
		"lfence\n\r"
		"rdtsc\n\r" 
		: "=a"(lo), "=d"(hi));
	var = ((unsigned long long int) hi << 32) | lo;
	return var;
}

uint32_t rdtsc_latency() {
    uint64_t a, b;
    
    a = THE_TSC;
    asm (
        TSCRD100
        TSCRD100
    :: );
    b = THE_TSC;
    return (uint32_t)((b-a)/200);
}
     
uint32_t compute_rdtsc_latency()
{
    uint32_t oh=0xffffff, result=0;
    for (int i=0; i < 4; i++) {
        result = rdtsc_latency();
        if (result < oh) oh = result;
    }
    //printf("overhead = %d\n", result);
    return result;
    
}

/* hold_count cycles. */
void busy_loop_cycle_delay(int hold_count)
{
    uint64_t begin, end;
  
    if (hold_count==0) 
        return;

    begin = THE_TSC;
 
    while(1)
    {
        _mm_pause();
        end = THE_TSC;
        if ((end-begin) >= (uint64_t)hold_count - 2*rdtsc_overhead)
            break;
    }
 
}

static uint64_t __always_inline get_rdtscp(void) {
    uint32_t lo, hi;
    __asm__ __volatile__ (
        "rdtscp" : "=a" (lo), "=d" (hi) :: "%rcx"
    );
    return ((uint64_t)hi << 32) | lo;
}

static __always_inline unsigned char enqcmd(void* dst, const void* src) {
    unsigned char ret;

    asm volatile(".byte 0xf2, 0x0f, 0x38, 0xf8, 0x02\t\n"
                 "setz %0\t\n"
                 : "=r"(ret)
                 : "a"(dst), "d"(src));
    return ret;
}

static __always_inline void movdir64b(void* dst, const void* src) {
    asm volatile(".byte 0x66, 0x0f, 0x38, 0xf8, 0x02\t\n"
                 :
                 : "a"(dst), "d"(src));
}

static uint8_t dsa_status(uint8_t status) {
    return status & DSA_COMP_STATUS_MASK;
}

static __always_inline uintptr_t
next_cache_line(uintptr_t curr_addr)
{
	uintptr_t off = curr_addr & 0xfff;
	uintptr_t base = curr_addr & ~0xfff;

	off += 0x40;
	off &= 0xfff;

	return base + off;
}

static __always_inline void *
incr_portal_addr(void *curr_portal_addr)
{
		return (void *)(next_cache_line((uintptr_t)curr_portal_addr));
}

static __always_inline int dsa_desc_submit(void* wq_portal,
                           struct dsa_hw_desc* hw) {
    size_t retry = 0;

    if (with_fence) {
        /* ensure previous writes are ordered */
        _mm_sfence();
    }
    //printf("wq addr before %p \n", wq_portal);
    if (dedicated_wq) {
        movdir64b(wq_portal, hw);
    } else {
        while (enqcmd(wq_portal, hw)) {
            if (retry++ > 10000ULL) {
                return 1;
            }
        }
    }

    submit_retry += retry;

    return 0;
}

static __always_inline void dsa_retry_prep(struct dsa_hw_desc* desc,
                           struct dsa_completion_record* comp) {
    int is_write = comp->status & DSA_COMP_STATUS_WRITE;
    volatile char* addr;

    addr = (char*)comp->fault_addr;
    is_write ? * addr = *addr : *addr;

    desc->src_addr += comp->bytes_completed;
    desc->dst_addr += comp->bytes_completed;
    desc->xfer_size -= comp->bytes_completed;

    comp->status = DSA_COMP_NONE;
}

static void* mmap_dsa_wq(const char* dsa_wq_path) {
    int fd = open(dsa_wq_path, O_RDWR);
    if (fd < 0) {
        printf("failed to open %s\n", dsa_wq_path);
        return NULL;
    }

    void* wq_portal =
        mmap(NULL, 0x1000, PROT_WRITE, MAP_SHARED | MAP_POPULATE, fd, 0);
    if (wq_portal == MAP_FAILED) {
        printf("failed to mmap %s", dsa_wq_path);
        close(fd);
        return NULL;
    }

    close(fd);
    return wq_portal;
}

static void print_usage() {
    printf("\tOptions: (V%s). ", DSA_BENCH_VERSION);
    printf("This tool is used for testing dsa memmove latency\n");
    printf("\t[-a x, Calculate the average latency for x operations]\n");
    printf("\t[-d dax device path]\n");
    printf("\t[-N x, NUMA node for memory test ]\n");
    printf("\t[-s dax device size]\n");
    printf("\t[-b memcpy block size]\n");
    printf("\t[-f pre-fill data with memset for buffers, 0- not fille, 1- prefill]\n");
    printf("\t[-F Use the fence instruction before DSA operation]\n");
    printf("\t[-i memcpy iteration number]\n");
    printf("\t[-k bind cpu num]\n");
    printf("\t[-w write from local memory to device, otherwise read]\n");
    printf("\t[-m use local memory as write/read destination, otherwise it will use dax device on CXL device]\n");
    printf("\t[-q dsa wq path, e.g. /dev/dsa/wq0.0]\n");
    printf("\t[-o iodepth, defined request depth in each operaton iteration]\n");
    printf("\t[-C memcpy operator: 0-DSA; 1-CPU glibc memcpy; 2-CPU libpmem, NT store; ]\n");  
    printf("\t[-D Data Model for operation; 0- 4k header + 16k header; 1 - only 4k header; 2 - only 16k data]\n");
    printf("\t[-I usleep interval, i.e. -I 10, then compete 10 ops, will have x us sleep]\n");  
    printf("\t[-T print threshold (ns), only print the latency large than this threshold]\n");  
    printf("\t[-S sleep time(us) between two OPs]\n");  
    printf("\t[-F Enable fence before submit; bydefault it's disabled. Enable it if BOF is enabled.]\n");  
    printf("\t[-g debug mode, 0-logging whole ops; 1-logging each phase; 2- log more; bydefault 0]\n"); 
    printf("\t[-P Enable DSA WQ portal address increase (switch with round robin in 4k)]\n");
    printf("\t[-W Wait function, 0: usleep or 1: busy loop. bydefault is 0;]\n");
    printf("\t[-v Enable verify data after memcopy]\n");
    printf("\t[-t Set the timestamp method, 0-sys time api; 1-rdtsc]\n");
    printf("\t[-O Ordering flag, 0- relaxed ordering; 1- Strict ordering; bydefault it's 0]\n");
    printf("\t[-Z Post fence after memcopy, 0-NON fence; 1-sfence;2-mfence]\n");
    // for Single operaton test mode.
    printf("\t[-X <r|w|m> Test with single IO mode, specify the operation: read (r) or write (w) or mixed r/w (m).]\n");
        printf("\t\t *** for Single IO test mode ***\n");
        printf("\t\t[-l loop_count, Test with single IO mode, specify loop count for read/write]\n");
        printf("\t\t[-r reg_offset, Test with single IO mode, specify register offset on based address]\n");
        printf("\t\t[-V value, Test with single IO mode, specify write value]\n");
}

//#if 0
static inline
int set_mempolicy(int mode, const unsigned long *nodemask, unsigned long maxnode)
{
	return syscall(__NR_set_mempolicy, mode, nodemask, maxnode);
}

static off_t
file_sz(int fd)
{
	return lseek(fd, 0, SEEK_END);
}

static inline uint64_t
page_align_sz(uint64_t len)
{
	static const uint64_t pg_sz_arr[] = {4*1024, 2 * 1024 * 1024, 1024 * 1024 * 1024};
	int pg_size = PAGE_SIZE_INDEX;
	uint64_t align_sz;

	align_sz = len;

	align_sz = (align_sz + pg_sz_arr[pg_size] - 1) & ~(pg_sz_arr[pg_size] - 1);

	return align_sz;
}
/// @brief : map the memory buffer for device, by NUMA node;
/// @param sz : map size:
/// @param n : numa node number:
/// @param paddr : return address;
/// @return 
static int alloc_node_mem(uint64_t sz, int n, void **paddr)
{
	uint32_t huge_flags[] = {0, MFD_HUGETLB | MFD_HUGE_2MB, MFD_HUGETLB | MFD_HUGE_1GB};
	uint64_t node_mask;
	int fd;
	int rc;

	if (sz == 0) {
		*paddr = 0;
		return 0;
	}

	fd = memfd_create("temp", huge_flags[PAGE_SIZE_INDEX]);
	if (fd < 0) {
		rc = -errno;
		printf("Error creating memfd failed: %s\n", strerror(errno));
		return rc;
	}

	rc = ftruncate(fd, page_align_sz(sz));
	if (rc < 0) {
		rc = -errno;
		printf("Error in ftruncate: %s\n", strerror(errno));
		return rc;
	}

	node_mask = 1ULL << n;
	rc = set_mempolicy(MPOL_BIND, &node_mask, 64);
	if (rc) {
		rc = -errno;
		printf("failed to bind memory range %s\n", strerror(errno));
		return rc;
	}

	*paddr = mmap(NULL, file_sz(fd), PROT_READ | PROT_WRITE,
		MAP_POPULATE | MAP_SHARED, fd, 0);
	close(fd);
	rc = set_mempolicy(MPOL_DEFAULT, NULL, 64);
	if (rc || *paddr == MAP_FAILED) {
		rc = -errno;
		if (*paddr != MAP_FAILED)
			munmap(*paddr, file_sz(fd));
		else
			printf("Failed to mmap %lu from node %d\n",
				page_align_sz(sz), n);
		return rc;
	}

	return 0;
}
//#endif

static void mmap_device(const char* dev_path, unsigned long long dev_size) {

    if (dax_dev_set && set_numa_node){
        fprintf(stderr, "NUMA node[%d] and devcie path[%s] are both specified, please use one devcie for memory test\n", numa_node,dev_path);
        _exit(0);
    }

    if (!use_mem) {
        if (set_numa_node == 1) {
            if (alloc_node_mem(dev_size, numa_node, (void **)&device_mem_ptr)){
                fprintf(stderr, "Failed to allocate memory for NUMA node %d\n", numa_node);
                _exit(1);
            }
        } else {
            // use the dax device;
            int device_fd = open(dev_path, O_RDWR, 0666);
            if (device_fd < 0) {
                fprintf(stderr, "Failed to open %s\n", dev_path);
                _exit(1);
            }

            device_mem_ptr = (char*)mmap(NULL, dev_size, PROT_WRITE | PROT_READ,
                                        MAP_SHARED, device_fd, 0);
            if (device_mem_ptr == MAP_FAILED) {
                fprintf(stderr, "Failed to mmap %s, ptr is %p\n", dev_path,
                        device_mem_ptr);
                close(device_fd);
                _exit(1);
            }
        }

    } else {
        device_mem_ptr = (char*)mmap(NULL, dev_size, PROT_WRITE | PROT_READ,
                                     MAP_ANONYMOUS | MAP_PRIVATE, -1, 0);
    }

    if (mlock_enable && device_mem_ptr != NULL) {
        if (prefill_data == 1)
            memset(device_mem_ptr, 0x5A, dev_size);
        mlock(device_mem_ptr, dev_size);
    }
}

static int parse_args(int argc, char* argv[]) {
    int opt;

    while ((opt = getopt(argc, argv, "a:b:C:d:D:g:i:I:f:k:N:X:q:s:S:T:r:R:V:t:l:o:O:W:Z:FLwmhPQv")) != -1) {
        switch (opt) {
        case 'a':
            aggregate_ops = strtoull(optarg, NULL, 10);
            if (aggregate_ops == 0 ) {
                printf("Aggretation count is not support, set default value 1\n");
                aggregate_ops = 1; 
            }
            break;
        case 'b':
            block_size = strtoull(optarg, NULL, 10);
            break;
        case 'd':
            strncpy(dev_path, optarg, sizeof(dev_path));
            dax_dev_set = 1;
            break;
        case 'i':
            iteration = strtoull(optarg, NULL, 10);
            break;
        case 'q':
            strncpy(dsa_wq_path, optarg, sizeof(dsa_wq_path));
            dsa_wq_used = 1;
            break;
        case 's':
            dev_size = strtoull(optarg, NULL, 10);
            break;
        case 'w':
            is_write = 1;
            break;
        case 'W':
            wait_function = atoi(optarg);
            if (wait_function >= 1)
                wait_function = 1;
            break;
        case 'k':
            cpu_num = atoi(optarg);
            break;
        case 'g':
            debug_mode = atoi(optarg);
            break;
        case 'm':
            use_mem = 1;
            break;
        case 'L':
            mlock_enable = 1;
            break;
        case 't':
            use_tsc = atoi(optarg);
            if (use_tsc >= 1)
                use_tsc = 1;
            break;
        case 'O':
            strict_ordering_enable = atoi(optarg);
            if (strict_ordering_enable >= 1)
                strict_ordering_enable = 1;
            break;
        case 'f':
            prefill_data = atoi(optarg);
            break;
        case 'F':
            with_fence = 1;
            break;
        case 'P':
            wq_portal_sw = 1;
            break;
        case 'Q':
            dedicated_wq = 1;
            break;
        case 'v':
            verify_data = 1;
            break;
        case 'D':
            data_model = atoi(optarg);
            break;
        case 'I':
            idle_interval = atoi(optarg);
            break;
        case 'o':
            iodepth = strtoull(optarg, NULL, 10);
            break;
        case 'C':
            do_with_cpu = atoi(optarg);
            break;
        case 'S':
            usleep_time = atoi(optarg);
            printf("Waiting sleep between ops: %u us\n", usleep_time);
            break;
        case 'l':
            loop_count = strtoul(optarg, NULL, 0);
            loop_count_set = 1;
            break;
        case 'N':
            numa_node = atoi(optarg);
            set_numa_node = 1;
            break;
        case 'T':
            print_threshold = atoi(optarg);
            if (print_threshold <= 0 )
                print_threshold = 16000;
            break;
        case 'X':
            operation = optarg[0];
            if (operation != 'r' && operation != 'w' && operation != 'm') {
                fprintf(stderr, "Invalid operation. Use 'r' for read or 'w' for write or 'm' for mixed r/w.\n");
                print_usage();
            }
            single_latency_mode = 1;
            break;
        case 'r':
            reg_offset = strtoull(optarg, NULL, 0);
            reg_offset_set = 1;
            break;
        case 'R':
            cpu_readback_mode = atoi(optarg);
            break;
        case 'Z':
            fence_type = atoi(optarg);
            break;
        case 'V':
            write_value = strtoul(optarg, NULL, 0);
            write_value_set = 1;
            break;
        case 'h':
            print_usage();
            return 1;
        default:
            print_usage();
            return 1;
        }
    }

    return 0;
}

static int generate_index(size_t block_num) {
    int index = rand() % block_num;

    return index;
}

static inline void sfence(void) {
    __asm__ __volatile__ ("sfence" ::: "memory");
}

// Ensure memory operations are completed with mfence
static inline void mfence(void)
{
    __asm__ __volatile__ ("mfence" ::: "memory");
}

// Write to 
void __always_inline write_32(uintptr_t mmio_base, uint32_t offset, uint32_t value) 
{
    value = value & 0xFFFFFFFF;
    *(volatile uint32_t *)(mmio_base + offset) = value;
    sfence();
}

// Read from 
uint32_t __always_inline read_32(uintptr_t mmio_base, uint32_t offset) 
{
    return *(volatile uint32_t *)(mmio_base + offset);
}

static void mmio_latency_test( void * mem_base )
{
    uint32_t value = write_value;

    // 3. Do read/write operatons. 
    if ((operation == 'w' && write_value_set == 1)) {
        for(int i = 0; i < loop_count; i++){
            reg_offset += i * 64;

            //t1 = get_rdtsc();
            _mm_mfence();
            t1 = get_rdtscp();
            for (int j = 0 ; j < write_count; j++ ) {
                write_32((uintptr_t)mem_base, reg_offset, value);
                value = value + 0x5A;
            }
            // write_32((uintptr_t)mem_base, reg_offset, value);
            // value = value + 0x5A;
            // write_32((uintptr_t)mem_base, reg_offset, value);
            // value = value + 0x80;
            // write_32((uintptr_t)mem_base, reg_offset, value);
            // value = value + 0xF0;
            // write_32((uintptr_t)mem_base, reg_offset, value);
            mfence();
            t2 = get_rdtscp();
            _mm_lfence();

            if (message_mode == 2) 
                printf("Written value 0x%X to MMIO at address 0x%lX, duration ns: %.1f\n", value, mem_base + reg_offset, (double)(t2 - t1) / TSC_GHZ);
            else if (message_mode == 1)
                printf("Written 0x%X, TSC %.1f\n", value, (double)(t2 - t1) /TSC_GHZ );
        }
    } else if (operation == 'r') {
        for(int i = 0; i < loop_count; i++){
            reg_offset += i * 64;

            _mm_mfence();
            t1 = get_rdtscp();
            value = read_32((uintptr_t)mem_base, reg_offset);
            mfence();
            t2 = get_rdtscp();
            _mm_lfence();

            if (message_mode == 2) 
                printf("Read value 0x%X from MMIO at offset 0x%lX, duration ns: %.1f\n", value, mem_base + reg_offset, (double)(t2 - t1) /TSC_GHZ );
            else if (message_mode == 1)
                printf("Read 0x%X, TSC %.1f\n", value, (double)(t2 - t1) /TSC_GHZ );
        }
    } else if (operation == 'm') {
        value = 0x55AA55AA;
        for(int i = 0; i < loop_count; i++){

            t1 = get_rdtscp();

            // value = value + 0x5A;
            // write_32((uintptr_t)mem_base, reg_offset, value);    //write first
            for (int j = 0 ; j < write_count; j++ ) {
                reg_offset += j * 64;
                write_32((uintptr_t)mem_base, reg_offset, value);
                value = value + 0x5A;
            }
            mfence();
            value = read_32((uintptr_t)mem_base, reg_offset);    //then read
            t2 = get_rdtscp();
            _mm_lfence();

            if (message_mode == 2) 
                printf("Read value 0x%X from MMIO at offset 0x%lX, duration cycle: %.0f\n", value, mem_base + reg_offset, (double)(t2 - t1) /TSC_GHZ );
            else if (message_mode == 1)
                printf("Read 0x%X, TSC %.0f\n", value, (double)(t2 - t1) /TSC_GHZ );
        }
    } else {
        fprintf(stderr, "Invalid operation: %c\n", operation);
        print_usage();
    }

}


void* task(void* args) {
    size_t block_num = dev_size / (block_size + 4096);
    size_t body_buffer_size = block_size * iodepth * 2;
    char* buffer = (char*)malloc(body_buffer_size);
    char* header_buffer = (char*)malloc(4096);
    size_t finished_task_num = 0;
    char* dsa_tasks_buffer;
    size_t das_task_size = 2 * iodepth * sizeof(dsa_task_t);
    struct timeval start, end, begin;
    uint64_t accumlative_count = 0;

    uint64_t t0_begin = 0, t1_start = 0, t2_end = 0, submit1 = 0, submit2 = 0;

    if (mlock_enable && buffer != NULL) {
        mlock(buffer, body_buffer_size);
        if (prefill_data == 1)
            memset(buffer, 0x5A, body_buffer_size);
    }

    if (mlock_enable && header_buffer != NULL) {
        mlock(header_buffer, 4096);
        if (prefill_data == 1)
            memset(header_buffer, 0x5A, 4096);
    }

    if (posix_memalign((void**)&dsa_tasks_buffer, 0x1000,
                        das_task_size )) {
        printf("allocate dsa task buffer failed\n");
        _exit(1);
    }

    if (mlock_enable && dsa_tasks_buffer != NULL) {
        mlock(dsa_tasks_buffer, das_task_size );
    }

    mmap_device(dev_path, dev_size);
    srand(time(NULL));

    if (do_with_cpu == 0 && dsa_wq_used) {
        dsa_wq_portal = mmap_dsa_wq(dsa_wq_path);
        if (dsa_wq_portal == NULL) {
            printf("mmap dsa wq portal failed\n");
            _exit(1);
        }
    }

    if (do_with_cpu == 0 && dsa_wq_portal == NULL) {
        printf("mmap dsa wq portal failed\n");
        _exit(1);
    }

    if (!use_tsc)
        gettimeofday(&begin, NULL);
    else 
        t0_begin = get_rdtscp();

    if (single_latency_mode) {
        mmio_latency_test((void * )device_mem_ptr);
        goto _end_and_clear;
    }

    for (size_t i = 0; i < iteration; i++) {
        int index = generate_index(block_num);
        char* tmp_buffer = buffer;
        char* device_buffer = device_mem_ptr + index * (block_size + 4096);

        _mm_sfence();

        if ( (aggregate_ops > 0) && !(i % aggregate_ops)) {
            accumlative_count = 0;
            if (!use_tsc) {
                gettimeofday(&start, NULL);
            }
            else {
                _mm_mfence();
                t1_start = get_rdtscp();
                _mm_lfence();
            }
        }
        // memcpy(dst, src, tcfg->blen);

        // submit header
        if (data_model == 0 || data_model == 1){

            dsa_task_t* dsa_task = (dsa_task_t*)dsa_tasks_buffer;

            dsa_task->desc.opcode = DSA_OPCODE_MEMMOVE;
            if (strict_ordering_enable == 1) {
//                dsa_task->desc.flags = IDXD_OP_FLAG_RCR | IDXD_OP_FLAG_CRAV | IDXD_OP_FLAG_DRDBK | IDXD_OP_FLAG_BOF | IDXD_OP_FLAG_STORD;
                dsa_task->desc.flags = IDXD_OP_FLAG_RCR | IDXD_OP_FLAG_CRAV | IDXD_OP_FLAG_BOF | IDXD_OP_FLAG_STORD;
            } else {
//                dsa_task->desc.flags = IDXD_OP_FLAG_RCR | IDXD_OP_FLAG_CRAV | IDXD_OP_FLAG_DRDBK | IDXD_OP_FLAG_BOF;
                dsa_task->desc.flags = IDXD_OP_FLAG_RCR | IDXD_OP_FLAG_CRAV | IDXD_OP_FLAG_BOF;
            }
            if (dsa_readback_mode) {
                dsa_task->desc.flags = dsa_task->desc.flags | IDXD_OP_FLAG_DRDBK;
            }
//            dsa_task->desc.flags = IDXD_OP_FLAG_RCR | IDXD_OP_FLAG_CRAV | IDXD_OP_FLAG_BOF;
//            dsa_task->desc.flags = IDXD_OP_FLAG_RCR | IDXD_OP_FLAG_CRAV | IDXD_OP_FLAG_CC;
            dsa_task->desc.xfer_size = 4096;
            dsa_task->comp.status = 0;
            dsa_task->desc.completion_addr = (uint64_t)&dsa_task->comp;

            if (is_write) {
                dsa_task->desc.src_addr = (uint64_t)header_buffer;             
                dsa_task->desc.dst_addr = (uint64_t)device_buffer;
            } else {
                dsa_task->desc.src_addr = (uint64_t)device_buffer;
                dsa_task->desc.dst_addr = (uint64_t)header_buffer;
            }

            if (do_with_cpu == 1) {
                memcpy((char *) (dsa_task->desc.dst_addr), (char *) (dsa_task->desc.src_addr), dsa_task->desc.xfer_size);
            } else if (do_with_cpu == 2) {
                //void *pmem_memcpy_persist(void *pmemdest, const void *src, size_t len);
                pmem_memcpy_persist((char *) (dsa_task->desc.dst_addr), (char *) (dsa_task->desc.src_addr), dsa_task->desc.xfer_size);
                if (fence_type == 1){
                    _mm_sfence();
                } else if (fence_type == 2 ) {
                    _mm_mfence();
                }
                // readback
                if (cpu_readback_mode == 1) {
                    // readback last address;
                    uint64_t last_address = 0; 
                    if (dsa_task->desc.xfer_size % 64) 
                        last_address = (dsa_task->desc.dst_addr + 64 * (dsa_task->desc.xfer_size / 64));
                    else 
                        last_address = (dsa_task->desc.dst_addr + 63 * (dsa_task->desc.xfer_size / 64));
                    memcpy((char *) (dsa_task->desc.src_addr), (char *) last_address, 64);
                    if (fence_type == 1){
                        _mm_sfence();
                    } else if (fence_type == 2 ) {
                        _mm_mfence();
                    }
                } else if (cpu_readback_mode == 2) {
                    // readback all ;
                    memcpy((char *) (dsa_task->desc.src_addr), (char *) (dsa_task->desc.dst_addr), dsa_task->desc.xfer_size);
                    if (fence_type == 1){
                        _mm_sfence();
                    } else if (fence_type == 2 ) {
                        _mm_mfence();
                    }
                }
                // readback
            } else {
                if (dsa_desc_submit(dsa_wq_portal, &dsa_task->desc)) {
                    printf("submit task failed\n");
                    _exit(1);
                }
                //printf("wq addr before %p \n", dsa_wq_portal);
                if (wq_portal_sw) {
                    dsa_wq_portal = incr_portal_addr(dsa_wq_portal);
                }
                //printf("wq addr after %p \n", dsa_wq_portal);
                if ( (aggregate_ops > 0) && !(i % aggregate_ops)) {
                    if ((debug_mode >= 1) && (use_tsc == 1) )
                        submit1 = get_rdtscp() - t1_start;
                }
            }

        }
_handler_data_submit:
        // submit data
        if (data_model == 0 || data_model == 2){

            // dsa_task_t* dsa_task2 = (dsa_task_t*)(dsa_tasks_buffer + sizeof(dsa_task_t));
            dsa_task_t* dsa_task2 = (dsa_task_t*)(dsa_tasks_buffer + 1 * sizeof(dsa_task_t));   //16k body data use second task buffer;

            dsa_task2->desc.opcode = DSA_OPCODE_MEMMOVE;
            if (strict_ordering_enable == 1) {
//                dsa_task2->desc.flags = IDXD_OP_FLAG_RCR | IDXD_OP_FLAG_CRAV | IDXD_OP_FLAG_DRDBK | IDXD_OP_FLAG_BOF | IDXD_OP_FLAG_STORD;
                dsa_task2->desc.flags = IDXD_OP_FLAG_RCR | IDXD_OP_FLAG_CRAV | IDXD_OP_FLAG_BOF | IDXD_OP_FLAG_STORD;
            } else {
//                dsa_task2->desc.flags = IDXD_OP_FLAG_RCR | IDXD_OP_FLAG_CRAV | IDXD_OP_FLAG_DRDBK | IDXD_OP_FLAG_BOF;
                dsa_task2->desc.flags = IDXD_OP_FLAG_RCR | IDXD_OP_FLAG_CRAV | IDXD_OP_FLAG_BOF;
            }
            if (dsa_readback_mode) {
                dsa_task2->desc.flags = dsa_task2->desc.flags | IDXD_OP_FLAG_DRDBK;
            }

            dsa_task2->desc.xfer_size = block_size;
            dsa_task2->comp.status = 0;
            dsa_task2->desc.completion_addr = (uint64_t)&dsa_task2->comp;

            if (is_write) {
                dsa_task2->desc.src_addr = (uint64_t)tmp_buffer;             
                dsa_task2->desc.dst_addr = (uint64_t)(device_buffer + 4096);
            } else {
                dsa_task2->desc.src_addr = (uint64_t)(device_buffer + 4096);
                dsa_task2->desc.dst_addr = (uint64_t)tmp_buffer;
            }

            // if (dsa_desc_submit(dsa_wq_portal, &dsa_task2->desc)) {
            //     printf("submit task failed\n");
            //     _exit(1);
            // }
            if (do_with_cpu == 1) {
                memcpy((char *) (dsa_task2->desc.dst_addr), (char *) (dsa_task2->desc.src_addr), dsa_task2->desc.xfer_size);
            } else if (do_with_cpu == 2) {
                //void *pmem_memcpy_persist(void *pmemdest, const void *src, size_t len);
                pmem_memcpy_persist((char *) (dsa_task2->desc.dst_addr), (char *) (dsa_task2->desc.src_addr), dsa_task2->desc.xfer_size);
                if (fence_type == 1){
                    _mm_sfence();
                } else if (fence_type == 2 ) {
                    _mm_mfence();
                }

                if (cpu_readback_mode == 1) {
                    // readback last address;
                    uint64_t last_address = 0; 
                    if (dsa_task2->desc.xfer_size % 64) 
                        last_address = (dsa_task2->desc.dst_addr + 64 * (dsa_task2->desc.xfer_size / 64));
                    else 
                        last_address = (dsa_task2->desc.dst_addr + 63 * (dsa_task2->desc.xfer_size / 64));
                    memcpy((char *) (dsa_task2->desc.src_addr), (char *) last_address, 64);

                    if (fence_type == 1){
                        _mm_sfence();
                    } else if (fence_type == 2 ) {
                        _mm_mfence();
                    }
                } else if (cpu_readback_mode == 2){
                    // readback all 
                    memcpy((char *) (dsa_task2->desc.src_addr), (char *) (dsa_task2->desc.dst_addr), dsa_task2->desc.xfer_size);

                    if (fence_type == 1){
                        _mm_sfence();
                    } else if (fence_type == 2 ) {
                        _mm_mfence();
                    }
                }

            } else {
                if (dsa_desc_submit(dsa_wq_portal, &dsa_task2->desc)) {
                    printf("submit task failed\n");
                    _exit(1);
                }
                //printf("wq addr before %p \n", dsa_wq_portal);
                if (wq_portal_sw) {
                    dsa_wq_portal = incr_portal_addr(dsa_wq_portal);
                }
                //printf("wq addr after %p \n", dsa_wq_portal);
                if ( (aggregate_ops > 0) && !(i % aggregate_ops)) {
                    if ((debug_mode >= 1) && (use_tsc == 1) )
                        submit2 = get_rdtscp() - t1_start;
                }
            }
        }
        finished_task_num = 0;

        do {
            if (do_with_cpu != 0)
                break;

            if (data_model == 0 || data_model == 1){

                dsa_task_t* dsa_task = (dsa_task_t*)(dsa_tasks_buffer);

                if (dsa_status(dsa_task->comp.status) == DSA_COMP_NONE) {
                    _mm_pause();
                    _mm_pause();
                    continue;
                }

                if (dsa_status(dsa_task->comp.status) == DSA_COMP_PAGE_FAULT_NOBOF) {
                    dsa_retry_prep(&dsa_task->desc, &dsa_task->comp);

                    if (dsa_desc_submit(dsa_wq_portal, &dsa_task->desc)) {
                        printf("submit task failed\n");
                        _exit(1);
                    }

                    continue;
                }

                if (dsa_status(dsa_task->comp.status) != DSA_COMP_SUCCESS) {
                    printf("dsa task failed, status is %d\n", dsa_status(dsa_task->comp.status));
                    _exit(1);
                }

                finished_task_num++;

            }

            if (data_model == 0 || data_model == 2){

                //  dsa_task_t* dsa_task2 = (dsa_task_t*)(dsa_tasks_buffer + sizeof(dsa_task_t));
                 dsa_task_t* dsa_task2 = (dsa_task_t*)(dsa_tasks_buffer + 1 * sizeof(dsa_task_t));   //16k body data use second task buffer;

                if (dsa_status(dsa_task2->comp.status) == DSA_COMP_NONE) {
                    _mm_pause();
                    _mm_pause();

                    continue;
                }

                if (dsa_status(dsa_task2->comp.status) == DSA_COMP_PAGE_FAULT_NOBOF) {
                    dsa_retry_prep(&dsa_task2->desc, &dsa_task2->comp);

                    if (dsa_desc_submit(dsa_wq_portal, &dsa_task2->desc)) {
                        printf("submit task failed\n");
                        _exit(1);
                    }

                    continue;
                }

                if (dsa_status(dsa_task2->comp.status) != DSA_COMP_SUCCESS) {
                    printf("dsa task failed, status is %d\n", dsa_status(dsa_task2->comp.status));
                    _exit(1);
                }

                finished_task_num++;
            }

            finished_task_num = 2;
        } while (finished_task_num == 0);

        uint64_t time_elapsed = 0, running_time = 0;

        if ( (aggregate_ops > 0) && (accumlative_count + 1 == aggregate_ops ) ) {
        // if ( (aggregate_ops > 0) && !(i % aggregate_ops) ) {

            // if ((accumlative_count + 1 < aggregate_ops)) {
            //     printf(" aggregate_ops: %d, accumlative count: %d \n", aggregate_ops, accumlative_count);
            // }
            //print_threshold is nano seconds
            if (!use_tsc) {
                /* Warning:  if use system api getimeofday, the time elapsed will be not accurate for aggreate > 1
                 * Suggest to use TSC to calculate the time.
                 */
                gettimeofday(&end, NULL);
                time_elapsed = ( (end.tv_sec - start.tv_sec) * 1000000 + (end.tv_usec - start.tv_usec) );   // us;
                //time_elapsed = ( (end.tv_sec - start.tv_sec) * 1000000 + (end.tv_usec - start.tv_usec) - (aggregate_ops - 1) * usleep_time ) / aggregate_ops;   // us;
                double cur_latency_us = (double)(time_elapsed - (aggregate_ops - 1) * usleep_time) / aggregate_ops;     //us;
                running_time = (end.tv_sec - begin.tv_sec) * 1000 +  (end.tv_usec - begin.tv_usec) /1000 ;

                if (debug_mode >= 2) {
                    printf("aggregated elapsed time : %.1f us \n", (double)time_elapsed /1000);
                }
                // only log the latency > 1600ns;
                if (time_elapsed * 1000 > print_threshold) {
                    printf("Running: %lu ms, completed %lu OPs (%.2f ops/ms), submit_retry: %lu , elapsed time: %lu us for %lu ops, cur_latency: %.1f us\n", 
                        running_time , i, (double)i / (double)running_time, submit_retry, time_elapsed, aggregate_ops, cur_latency_us);
                }
            }else {
                _mm_mfence();
                t2_end = get_rdtscp();
                _mm_lfence();
                time_elapsed = (t2_end - t1_start);  //cycles
                running_time = (t2_end - t0_begin);  //cycles
                double time_elapsed_ns = (double ) time_elapsed / TSC_GHZ;  //ns
                double running_time_ns = (double ) running_time / TSC_GHZ;  //ns
                //printf("tsc ghz = : %.1f \n", TSC_GHZ);

                double running_time_ms = (double)running_time_ns /1000/1000; //ms
                if (debug_mode >= 2) {
                    printf("aggregated elapsed time : %.1f us \n", (double)time_elapsed_ns /1000);
                }
                // double cur_latency_us = (double)time_elapsed_ns /1000 /aggregate_ops;  // average latency.
                double cur_latency_us = ( (double)time_elapsed_ns /1000 - (aggregate_ops - 1) * usleep_time ) /aggregate_ops;  // average latency.
                if (debug_mode >= 1) {
                    double submit1_duration_ns = 0, submit2_duration_ns = 0 ;
                    if (do_with_cpu == 0) {
                        // only for DSA memcpy
                        submit1_duration_ns  = (double)submit1 / TSC_GHZ ;
                        submit2_duration_ns = (double)(submit2 - submit1) / TSC_GHZ;
                       //printf("submit1 time %lld, submit2 time %lld,\n", submit1, submit2);
 
                        if (submit1 == 0)
                            submit1_duration_ns = 0;
                        if (submit2 == 0)
                            submit2_duration_ns = 0; 
                    }
                    if (aggregate_ops > 1) {
                        submit1_duration_ns = 0;
                        submit2_duration_ns = 0;
                    }

                    // only log the latency > 1600ns;
                    if ((uint64_t)time_elapsed_ns > (uint64_t)print_threshold ) {
                        printf("Running: %lu ms, completed %lu OPs(%.2f ops/ms), submit1_lat[%lu ns], submit2_lat[%lu ns], dsa_wq_addr: %p, submit_retry: %lu cur_lat: %lf us\n", 
                            (uint64_t)running_time_ms, i,  
                            ((double)i/running_time_ms), 
                            (uint64_t)submit1_duration_ns, 
                            (uint64_t)submit2_duration_ns, 
                            dsa_wq_portal, 
                            submit_retry, 
                            cur_latency_us);
                        submit2_duration_ns = 0;
                        submit2_duration_ns = 0;
                    }
                } else { //debug mode 0
                    // only log the latency > 1600ns;
                    if ((uint64_t)time_elapsed_ns > (uint64_t)print_threshold ) {
                        printf("Running: %lu ms, completed %lu OPs(%.2f ops/ms), dsa_wq_addr: %p, submit_retry: %lu cur_lat: %lf us\n", 
                            (uint64_t)running_time_ms, i,  
                            ((double)i/running_time_ms), 
                            dsa_wq_portal, 
                            submit_retry, 
                            cur_latency_us);

                    }

                } // debug mode or not
            } //use tsc or not
        }

// for data verify
        if (verify_data == 1) {
//        for (size_t j = 0; j < iodepth; j++) {
//            dsa_task_t* dsa_task = (dsa_task_t*)(dsa_tasks_buffer + j * sizeof(dsa_task_t));

            dsa_task_t* dsa_task = (dsa_task_t*)(dsa_tasks_buffer + sizeof(dsa_task_t));
            if (memcmp((void*)dsa_task->desc.src_addr, (void*)dsa_task->desc.dst_addr, dsa_task->desc.xfer_size)) {
                printf("memcmp failed for packet header!!!!\n");
                if (buffer)
                   free(buffer);
                if (dsa_tasks_buffer)
                    free(dsa_tasks_buffer);

                // if (dsa_wq_portal && dsa_wq_portal != MAP_FAILED) {
                //     munmap(dsa_wq_portal, 0x1000);
                // }

                _exit(200);
            }

            dsa_task_t* dsa_task2 = (dsa_task_t*)(dsa_tasks_buffer + 1 * sizeof(dsa_task_t));   //16k body data use second task buffer;

            if (memcmp((void*)dsa_task2->desc.src_addr, (void*)dsa_task2->desc.dst_addr, dsa_task2->desc.xfer_size)) {
                printf("memcmp failed for data body!!!!\n");


                if (buffer)
                   free(buffer);
                if (dsa_tasks_buffer)
                    free(dsa_tasks_buffer);

                // if (dsa_wq_portal && dsa_wq_portal != MAP_FAILED) {
                //     munmap(dsa_wq_portal, 0x1000);
                // }

                _exit(200);
            }
//        }
        }

        submit_retry = 0;
        accumlative_count++;

        if (idle_interval > 0 && !(i % idle_interval) ) {
            if (wait_function == 1) {
                busy_loop_cycle_delay(usleep_time * tsc_mhz);
            } else { 
                if (usleep_time >= 1000000)
                    sleep(usleep_time / 1000/1000);
                else 
                    usleep(usleep_time);
            }
        }
    }

_end_and_clear:
    if (buffer) {
        if (mlock_enable)
            munlock(buffer, body_buffer_size);
        free(buffer);
    }

    if (dsa_tasks_buffer) {
        if (mlock_enable)
            munlock(dsa_tasks_buffer, das_task_size);
        free(dsa_tasks_buffer);
    }

    if (header_buffer) {
        if (mlock_enable)
            munlock(header_buffer, 4096);
        free(header_buffer);
    }

    if (device_mem_ptr){
        if (mlock_enable)
            munlock(device_mem_ptr, dev_size);
        munmap(device_mem_ptr, dev_size);
    }

    return 0;
}

int main(int argc, char* argv[]) {
    if (parse_args(argc, argv)) {
        return 0;
    }

    if (aggregate_ops > 1 && verify_data == 1) {
        printf("Warnning, if the data verification enabled, the accumlative and average latency may NOT be acurate.\n");
    }

    if (wait_function == 1)
        rdtsc_overhead = compute_rdtsc_latency();
    
    check_tsc_frequency_cpuid();

    pthread_t thread;
    if (pthread_create(&thread, NULL, task, NULL) != 0) {
        fprintf(stderr, "Failed to create thread\n");
        return 1;
    }

    cpu_set_t cpuset;
    CPU_ZERO(&cpuset);
    CPU_SET(cpu_num, &cpuset);

    if (pthread_setaffinity_np(thread, sizeof(cpu_set_t), &cpuset) != 0) {
        fprintf(stderr, "Failed to set thread affinity\n");
        return 1;
    }

    if (pthread_join(thread, NULL) != 0) {
        fprintf(stderr, "Failed to join thread\n");
        return 1;
    }

    printf("Memcopy benchmark is completed.\n");
    return 0;
}
