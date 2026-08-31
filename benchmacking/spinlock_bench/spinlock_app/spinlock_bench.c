#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <getopt.h>
#include <sched.h>
#include <time.h>
#include <stdatomic.h>
#include <stdint.h>
#include <unistd.h>
#include <sys/timeb.h>
#include <sys/time.h>
#include <sys/mman.h>

#include <fcntl.h>
#include <string.h>
#include <assert.h>
#include <sys/shm.h>
#include <errno.h>
#include <signal.h>
#include <sys/syscall.h>
#include <ctype.h>
#include <stddef.h>
#include <stdint.h>

#define VERSION  "1.1"

#define TSCRD1	"lfence; rdtsc;"
#define TSCRD10 TSCRD1 TSCRD1 TSCRD1 TSCRD1 TSCRD1 TSCRD1 TSCRD1 TSCRD1 TSCRD1 TSCRD1 
#define TSCRD100 TSCRD10 TSCRD10 TSCRD10 TSCRD10 TSCRD10 TSCRD10 TSCRD10 TSCRD10 TSCRD10 TSCRD10 
// GCC internal atmonic funtion
typedef uint64_t atomic_uint64_t;
#define MAX_CPU 512

int rdtsc_overhead=0;
double tsc_freq = 2.0;  //GHz
uint64_t start_time, stop_time;

struct __attribute__((aligned(64))) cacheline_var_t {
    uint64_t shared_value;
    char padding[64 - sizeof(uint64_t)];
};

//struct cacheline_var_t global_shared_var = {0};

uint16_t cpu_list[MAX_CPU] = {0};
static volatile char hole0[64];
__attribute__((aligned(64)))
static pthread_spinlock_t spinlock;
static volatile char hole1[64];
__attribute__((aligned(64)))
static pthread_mutex_t mutex;  
static volatile char hole2[64];
__attribute__((aligned(64)))
volatile uint64_t shared_counter = 0;
static volatile char hole3[64];

static int online_cpus = 16;    //match with current system.

static inline uint64_t my_atomic_fetch_add (volatile uint64_t *ptr, uint64_t val)
{
    return __sync_fetch_and_add(ptr, val);
}
// static inline void my_atomic_store(atomic_uint64_t *ptr, uint64_t val) {
//     __sync_lock_test_and_set(ptr, val);
// }
// static inline uint64_t my_atomic_load(atomic_uint64_t *ptr) {
//     return *ptr;
// }


// // (TSC)
// static inline uint64_t rdtsc(void) {
//     uint32_t lo, hi;
//     __asm__ __volatile__("rdtsc" : "=a" (lo), "=d" (hi));
//     return ((uint64_t)hi << 32) | lo;
// }

// try to simulate the C++ new keyword in critical section.
// people added new operation in critical section, then the latency should be long, 
//------
// lock
// int *c = new(int)
// *c++;  
// unlock
// delete(c)
//------
#define new(type) ((type*)malloc(sizeof(type)))
#define delete(ptr) free(ptr)

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
static inline unsigned long
rdtscp(void)
{
	unsigned long var;
	unsigned int hi, lo;
	asm volatile(
		"rdtscp\n\r" 
		: "=a"(lo), "=d"(hi));
	var = ((unsigned long long int) hi << 32) | lo;
	return var;
}

int rdtsc_latency(void) {
    uint64_t a, b;
    
    a = THE_TSC;
    asm (
        TSCRD100
        TSCRD100
    :: );
    b = THE_TSC;
    return (int)((b-a)/200);
}
     
int compute_rdtsc_latency(void)
{
    int oh=0xffffff, result=0;
    for (int i=0; i < 4; i++) {
        result = rdtsc_latency();
        //printf("Overhead%d\t%d\n", i, result);
        if (result < oh) oh = result;
    }
    //printf("overhead = %d\n", result);
    return result;
    
}

static inline void busy_loop_delay(int hold_count)
{
    int64_t begin, end;
  
    if (hold_count==0) 
        return;

    begin = THE_TSC;
 
    while(1)
    {
        end = THE_TSC;
        if ((end-begin) >= (int64_t)hold_count - 2*rdtsc_overhead)
            break;
    }
 
}

void get_tsc_frequency( double * tsc_frequency) {

    // Read the TSC frequency
    uint64_t tsc_start = THE_TSC;
    usleep(500000); // Wait for 500 msecond
    uint64_t tsc_end = THE_TSC;
    uint64_t tsc = (tsc_end - tsc_start);
    
    *tsc_frequency = (double)tsc/500000000;
    //printf("TSC duration %lu\n", tsc);

    //printf("TSC Frequency: %.3f GHz\n", *tsc_frequency);
}

/*
static int read_msr(int cpu, unsigned int reg, uint64_t *value);

#define MSR_IA32_MPERF 0xE7
#define MSR_IA32_APERF 0xE8

static int read_msr(int cpu, unsigned int reg, uint64_t *value)
{
    char msr_file_name[64];
    int fd;
    ssize_t ret;

    snprintf(msr_file_name, sizeof(msr_file_name), "/dev/cpu/%d/msr", cpu);
    fd = open(msr_file_name, O_RDONLY);
    if (fd < 0) {
        if (errno == ENXIO) {
            fprintf(stderr, "read_msr: No CPU %d\n", cpu);
            return -1;
        } else if (errno == EIO) {
            fprintf(stderr, "read_msr: CPU %d doesn't support MSRs\n", cpu);
            return -1;
        } else {
            perror("read_msr: open");
            return -1;
        }
    }

    ret = pread(fd, value, sizeof(*value), reg);
    if (ret != sizeof(*value)) {
        if (ret < 0)
            perror("read_msr: pread");
        else
            fprintf(stderr, "read_msr: pread returned %zd bytes\n", ret);
        close(fd);
        return -1;
    }

    close(fd);
    return 0;
}
*/


// conver hex char to hex value , 
static int hex_char_to_value(char c)
{
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    return -1;
}

// hex string to bitmap.
// return count
static uint16_t hexstring_to_cpulist(const char *str, uint16_t * list, int max_bits)
{
    const char *p = str;
    int bit_pos = 0;
    int value, str_lengh = strlen(str);
    int i;
    uint16_t idx = 0;

    while (isspace(*p))
        p++;

    if (*p == '\0')
        return -1;    

    if (str_lengh >= 2) {
        if (str[0] == '0' && (str[1] == 'x' || str[1] == 'X') ) {
            str += 2;
            str_lengh -= 2;
        }
    }
    //printf("cpumask string is %s\n", str);
    p = str + str_lengh - 1;
    while (p >= str && !isspace(*p)) {
        value = hex_char_to_value(*p);
        if (value < 0)
            return -1;

        // hex value has 4 bit.
        for (i = 0; i < 4; i++) {
            //printf("bit_pos to %d\n", bit_pos);
            if (bit_pos >= max_bits)
                break;

            if (value & (1 << i)) {
               list[idx++] = bit_pos;
            }
            bit_pos++;
        }

        p--;
    }

    return idx;
}

// 
static inline void spin_wait(uint64_t cycles) {
    uint64_t start = rdtsc();
    while (rdtsc() - start < cycles);
}


// lock algorithm mode selection
enum lock_algo_mode {
    SPINLOCK_LOCK=0,
    MUTEX_LOCK=1,
    BATCH_SPINLOCK=2,
    MUTEX_BATCH_SPINLOCK=3,
    TICKET_LOCK=4,
    ATOMIC_INC=5,

    LAST_LOCK
};

char * lock_mode_str(int mode)
{
    switch (mode) {
        case SPINLOCK_LOCK:
            return "spinlock";
            break;
        case BATCH_SPINLOCK:
            return "Batch_spinlock";
            break;
        case MUTEX_BATCH_SPINLOCK:
            return "Mutex_Batch_spinlock";
            break;
        case TICKET_LOCK:
            return "Ticket_spinlock";
            break;
        case MUTEX_LOCK:
            return "mutex_lock";
            break;
        case ATOMIC_INC:
            return "atomic_inc";
            break;
        case LAST_LOCK:
        default:
            return "NONE";
            break;
    }
    return "NONE";

}

//0-destroy , 1- init
void lock_init_destroy(int lock_mode, int ops)
{

    switch (lock_mode) {
        case SPINLOCK_LOCK:
        case BATCH_SPINLOCK:
            if (ops == 0)
                pthread_spin_destroy(&spinlock);
            else {
                // init;
                if (pthread_spin_init(&spinlock, PTHREAD_PROCESS_PRIVATE) != 0) {
                    perror("pthread_spin_init");
                    exit(EXIT_FAILURE);
                }
            }
            break;
        case MUTEX_BATCH_SPINLOCK:
            if (ops == 0) {
                pthread_spin_destroy(&spinlock);
                pthread_mutex_destroy(&mutex);
            } else {
                //init both;
                if (pthread_spin_init(&spinlock, PTHREAD_PROCESS_PRIVATE) != 0) {
                    perror("pthread_spin_init");
                    exit(EXIT_FAILURE);
                }
                if (pthread_mutex_init(&mutex, NULL) != 0) {
                    perror("pthread_mutex_init");
                    exit(EXIT_FAILURE);
                }                
            }

            break;
        case TICKET_LOCK:
            break;
        case MUTEX_LOCK:
            if (ops == 0)
                pthread_mutex_destroy(&mutex);
            else {
                // init mutex
                if (pthread_mutex_init(&mutex, NULL) != 0) {
                    perror("pthread_mutex_init");
                    exit(EXIT_FAILURE);
                }
            }
            break;
        case LAST_LOCK:
        default:
            break;
    }
}


// 
typedef struct {
    int thread_id;
    int lock_mode;                 // (0=spinlock, 1=mutex)
    pthread_mutex_t *mutex;        // 
    pthread_spinlock_t *spinlock;
    atomic_uint64_t *lock_acquire_count;
    uint64_t holdon_time;
    uint64_t wait_time;
    uint64_t * duration_tsc;
    atomic_int *stop_flag;
    int core_id;
} ThreadArgs;


void atomic_ops(ThreadArgs* args)
{
    atomic_uint64_t local_lock_count = 0;
    int lock_bench_mode = args->lock_mode;

    uint64_t T1 = THE_TSC;
    // major work for spinlcok bench.
    if (lock_bench_mode == ATOMIC_INC) {

        while (!*args->stop_flag) {

// ********* critical section start ***********//
            // increase counter.
            local_lock_count++;
            my_atomic_fetch_add(&shared_counter, 1);
            //__sync_fetch_and_add(&shared_counter, 1);

// ********* critical section end ***********//

            // wait time.
            if (args->wait_time > 0) {
                busy_loop_delay(args->wait_time);
            }
        }
    }

    uint64_t T2 = THE_TSC;

    * (atomic_uint64_t *)(args->lock_acquire_count) = local_lock_count;
    * (atomic_uint64_t *)(args->duration_tsc) = T2 - T1;    

}

void batch_lock( ThreadArgs* args) {

    atomic_uint64_t local_lock_count = 0;
    int lock_bench_mode = args->lock_mode;
    int i, core_count = online_cpus;

    uint64_t T1 = THE_TSC;
    // major work for spinlcok bench.
    while (!*args->stop_flag) {

        //protect with mutext out of the batch spinlock
        if (lock_bench_mode == MUTEX_BATCH_SPINLOCK)
            pthread_mutex_lock(args->mutex);

        /*batch aquiring lock  */
        for (i = 0; i <= core_count; i++) {
            if (*args->stop_flag) 
                goto batch_exit;
            // acquring lock
            pthread_spin_lock(args->spinlock);
// ********* critical section start ***********//
            // increase counter.
            local_lock_count++;
            shared_counter++;
            
            // hold on , simulate the critical section working durtion.
            if (args->holdon_time > 10) {
                busy_loop_delay(args->holdon_time);
            }

// ********* critical section end ***********//
            // release lock 
            pthread_spin_unlock(args->spinlock);
        }
        // wait time.
        if (args->wait_time > 0) {
            busy_loop_delay(args->wait_time);
        }

batch_exit:

        if (lock_bench_mode == MUTEX_BATCH_SPINLOCK)
            pthread_mutex_unlock(args->mutex);

    }

    uint64_t T2 = THE_TSC;

    * (atomic_uint64_t *)(args->lock_acquire_count) = local_lock_count;
    * (atomic_uint64_t *)(args->duration_tsc) = T2 - T1;

}


// thread common function.
void* thread_func(void* arg) {
    ThreadArgs* args = (ThreadArgs*)arg;
    cpu_set_t cpuset;
    atomic_uint64_t local_lock_count = 0;
    int lock_bench_mode = args->lock_mode;

    // core affinity.
    CPU_ZERO(&cpuset);
    // CPU_SET(args->thread_id % CPU_SETSIZE, &cpuset);
    // if (pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset) != 0) {
    //     perror("pthread_setaffinity_np");
    //     exit(EXIT_FAILURE);
    // }

    CPU_SET(args->core_id, &cpuset);
    if (pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset) != 0) {
        perror("pthread_setaffinity_np");
        exit(EXIT_FAILURE);
    }
    
    //printf("Thread %d bound to CPU core %d\n", args->thread_id, args->core_id);

    if (lock_bench_mode == MUTEX_BATCH_SPINLOCK || lock_bench_mode == BATCH_SPINLOCK) {
        batch_lock(args);
        return NULL;
    } else if (lock_bench_mode == ATOMIC_INC) {
        atomic_ops(args);
        return NULL;
    }

    uint64_t T1 = THE_TSC;
    // major work for spinlcok bench.
    while (!*args->stop_flag) {

        // acquring lock
        if (lock_bench_mode == 0) {
            // spinlock
            pthread_spin_lock(args->spinlock);
        } else {
            // mutex
            pthread_mutex_lock(args->mutex);
        }
// ********* critical section start ***********//
        // increase counter.
        // atomic_fetch_add(args->lock_acquire_count, 1);
       // (*(atomic_uint64_t *)(args->lock_acquire_count))++;
#define SIMULATE_CPP_NEW 0
#if SIMULATE_CPP_NEW
       atomic_uint64_t *c = new(atomic_uint64_t);
       if (c) {
            *c = * (atomic_uint64_t *)(args->lock_acquire_count);
            (*c)++;
       }
#endif
        local_lock_count++;
        
        // hold on , simulate the critical section working durtion.
        if (args->holdon_time > 10) {
            busy_loop_delay(args->holdon_time);
        }

#if SIMULATE_CPP_NEW
        if (c) {
            *(atomic_uint64_t *)(args->lock_acquire_count) = *c;
            free(c);
        }
#endif        
// ********* critical section end ***********//
        // release lock 
        if (lock_bench_mode == 0) {
            pthread_spin_unlock(args->spinlock);
        } else {
            pthread_mutex_unlock(args->mutex);
        }

        // wait time.
        if (args->wait_time > 10) {
            busy_loop_delay(args->wait_time);
        }

    }
    uint64_t T2 = THE_TSC;

    * (atomic_uint64_t *)(args->lock_acquire_count) = local_lock_count;
    * (atomic_uint64_t *)(args->duration_tsc) = T2 - T1;

    return NULL;
}

// 
void print_usage(const char* program_name) {
    printf("Usage: %s [options]\n", program_name);
    printf("Options: (V%s)\n", VERSION);
    printf("  -t <thread_num>       Number of threads (required)\n");
    printf("  -h <tsc_cycles>       Hold time in TSC cycles (required)\n");
    printf("  -w <tsc_cycles>       Wait time between lock acquisitions (required), e.g. other works after unlock\n");
    printf("  -d <test_duration>    Test duration in seconds (required)\n");
    printf("  -m <0|1|2|3>          Lock mode (default: 0)\n\
        0 - pthread spinlock, \n\
        1 - pthread mutex, \n\
        2 - batch spinlock, \n\
        3 - mutext with batch spinlock, \n\
        5 - atomic inc, \n");
    printf("  -c <core_num>         Number of CPU cores to use (default: = thread_count)\n");
    printf("  -M <cpumask>          The cpu mask for core selection (e.g. FFFF, or 0xFFFF), this option overwrite the core_num\n");
    printf("  -v <verbose>          Log output mode, 0:only total info; 1 all thread info, by default is 1\n");
}

int main(int argc, char* argv[]) {
    int thread_count = 1;
    uint64_t holdon_time = 0;
    uint64_t wait_time = 0;
    int test_duration = 5;
    int opt;
    int lock_mode = 0, verbose = 1;
    uint16_t core_count = 0;
    char * cpumask_str = NULL;
    int cpumask_set = 0;

    if (argc < 2) {
        print_usage(argv[0]);
        exit(EXIT_FAILURE);
    }
    // 
    while ((opt = getopt(argc, argv, "t:h:w:d:m:c:v:M:")) != -1) {
        switch (opt) {
            case 't':
                thread_count = atoi(optarg);
                break;
            case 'h':
                holdon_time = strtoull(optarg, NULL, 0);
                break;
            case 'w':
                wait_time = strtoull(optarg, NULL, 0);
                break;
            case 'd':
                test_duration = atoi(optarg);
                break;
            case 'm':
                lock_mode = atoi(optarg);
                if (lock_mode < 0 || lock_mode >= LAST_LOCK) {
                    fprintf(stderr, "Invalid lock mode: %d (must be between 0 - %d)\n", lock_mode, LAST_LOCK);
                    print_usage(argv[0]);
                    exit(EXIT_FAILURE);
                } else if (lock_mode == TICKET_LOCK){
                    fprintf(stderr, "lock mode: %d is not supported now\n", lock_mode);
                    print_usage(argv[0]);
                    exit(EXIT_FAILURE);
                }
                break;
            case 'c':
                core_count = atoi(optarg);
                if (core_count <= 0) {
                    fprintf(stderr, "Invalid core count: %d (must be positive)\n", core_count);
                    print_usage(argv[0]);
                    exit(EXIT_FAILURE);
                }
                break;
            case 'v':
                verbose = atoi(optarg); //log berbose, defaulg is 1, 
                break;
            case 'M':
                cpumask_str = optarg;
                cpumask_set = 1;
                break;
            default:
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
        }
    }

    rdtsc_overhead = compute_rdtsc_latency();
    get_tsc_frequency(&tsc_freq);    //tsc_freq
    printf("TSC Frequency: %.3f GHz, RDTSC overhead is %d cycles\n", tsc_freq, rdtsc_overhead);

    if (thread_count <= 0 || test_duration <= 0) {
        fprintf(stderr, "Invalid parameters: thread_count and test_duration must be positive.\n");
        print_usage(argv[0]);
        exit(EXIT_FAILURE);
    }


    // available core count, adjust the core count if exceed the online cores.
    online_cpus = sysconf(_SC_NPROCESSORS_ONLN);
    // if set cpumask, then use the cpumask, but not core_count parameter.
    if (cpumask_set) {
        if (cpumask_str) {
            core_count = hexstring_to_cpulist(cpumask_str, &(cpu_list[0]), (online_cpus < MAX_CPU) ? online_cpus: MAX_CPU);
            if (core_count <=0 ) {
                fprintf(stderr, "Invalid parameters: cpumask should be set right.\n");
                print_usage(argv[0]);
                exit(EXIT_FAILURE);    
            }
        } else {
            fprintf(stderr, "Invalid parameters: no cpumask set.\n");
            print_usage(argv[0]);
            exit(EXIT_FAILURE);
        }
    } else {
        // not set cpumask, use the core_count.
        if (core_count <= 0 ) {
            //if the core_count neither set, then align with thread_count.
            core_count = thread_count;
            if (core_count > online_cpus) {
                fprintf(stderr, "Warning: Requested %d cores, but system has only %d online CPUs\n", 
                        core_count, online_cpus);
                core_count = online_cpus;
            }
        }
    }

    printf("Online CPU count: %d\n", online_cpus);
    printf("Run [%d] seconds benchmark with [%d] threads on [%d] cores for lock mode [ %s ],Critical Section holdon [%lu] TSC cycles, other works duration [%lu] TSC cycles\n",
        test_duration,
        thread_count,
        core_count,
        lock_mode_str(lock_mode),
        holdon_time, 
        wait_time
    );

    // init the spinlcok with pthread spinlock
    if (lock_mode == SPINLOCK_LOCK || lock_mode == BATCH_SPINLOCK) {
        if (pthread_spin_init(&spinlock, PTHREAD_PROCESS_PRIVATE) != 0) {
            perror("pthread_spin_init");
            exit(EXIT_FAILURE);
        }
    } else if (lock_mode == MUTEX_LOCK) {
        // init mutex
        if (pthread_mutex_init(&mutex, NULL) != 0) {
            perror("pthread_mutex_init");
            exit(EXIT_FAILURE);
        }
    } else if (lock_mode == MUTEX_BATCH_SPINLOCK) {
        if (pthread_spin_init(&spinlock, PTHREAD_PROCESS_PRIVATE) != 0) {
            perror("pthread_spin_init");
            exit(EXIT_FAILURE);
        }
        if (pthread_mutex_init(&mutex, NULL) != 0) {
            perror("pthread_mutex_init");
            exit(EXIT_FAILURE);
        }
    }

    // creat threads and init.
    pthread_t* threads = malloc(thread_count * sizeof(pthread_t));
    ThreadArgs* args = malloc(thread_count * sizeof(ThreadArgs));
    atomic_uint64_t* lock_acquire_counts = malloc(thread_count * sizeof(atomic_uint64_t));
    atomic_uint64_t* test_duration_tscs = malloc(thread_count * sizeof(atomic_uint64_t));

    // init the lock aocunt.
    for (int i = 0; i < thread_count; i++) {
        atomic_init(&lock_acquire_counts[i], 0);
        test_duration_tscs[i] = 0;
    }

    atomic_int stop_flag = ATOMIC_VAR_INIT(0);
    //uint64_t test_duration_tsc = 1000;

    // create threads
    for (int i = 0; i < thread_count; i++) {
        int core_id = 0;
        if (cpumask_set) {
            //use the cpumask
            core_id = cpu_list[i % core_count];
        } else {
            core_id = i % core_count;
        }
        args[i] = (ThreadArgs){
            .thread_id = i,
            .lock_mode = lock_mode,         // 
            .spinlock = (lock_mode == SPINLOCK_LOCK || lock_mode == BATCH_SPINLOCK || lock_mode == MUTEX_BATCH_SPINLOCK) ? &spinlock : NULL,
            .mutex = (lock_mode == MUTEX_LOCK || lock_mode == MUTEX_BATCH_SPINLOCK) ? &mutex : NULL,
            .lock_acquire_count = &lock_acquire_counts[i],
            .holdon_time = holdon_time,
            .wait_time = wait_time,
            .duration_tsc = &test_duration_tscs[i],
            .core_id = core_id,
            .stop_flag = &stop_flag
        };
        
        if (pthread_create(&threads[i], NULL, thread_func, &args[i]) != 0) {
            perror("pthread_create");
            exit(EXIT_FAILURE);
        }
    }

    start_time = rdtsc();
    stop_flag = ATOMIC_VAR_INIT(0);
    // sleep wait for test ending...
    printf("Running test for %d seconds...\n", test_duration);
    //fflush(NULL);
    sleep(test_duration);
    
    // stop test 
    //atomic_store(&stop_flag, 1);
    stop_flag = 1;
    stop_time = rdtsc();

    uint64_t elapsed_clocks = (stop_time - start_time);
    double elapsed_time = (double)elapsed_clocks / tsc_freq; //ns
    printf("\elapsed clock %lu, elapsed time= %.3f msec \n", elapsed_clocks, elapsed_time/1000/1000);
    // wait until all thread finished.
    for (int i = 0; i < thread_count; i++) {
        if (pthread_join(threads[i], NULL) != 0) {
            perror("pthread_join");
            exit(EXIT_FAILURE);
        }
    }

    // desctroy lock.
    lock_init_destroy(lock_mode, 0);

    //output result:
    uint64_t total_acquires = 0, total_avg_lat_tsc = 0, lock_avg_lat = 0;
    printf("\nTest Results:\n");
    printf("==========================================================================\n");
    printf("Thread | Acquired Count | Throughput (acquires/sec) | avg-latency(clk) \n");
    printf("--------------------------------------------------------------------------\n");
    for (int i = 0; i < thread_count; i++) {
        uint64_t count = atomic_load(&lock_acquire_counts[i]);
        uint64_t d_tsc = *(args[i].duration_tsc);
        double throughput = (double)count / test_duration;
        //printf("Shared counter: %lu, per thrd count: %lu, tsc: %lu\n", shared_counter, count, d_tsc);
        if (count == 0) continue;
        if (lock_mode == MUTEX_BATCH_SPINLOCK || lock_mode == BATCH_SPINLOCK)
            lock_avg_lat = (d_tsc/count) - (holdon_time + wait_time/online_cpus);
        else if (lock_mode == ATOMIC_INC ) 
            lock_avg_lat = (d_tsc/count) - wait_time;
        else 
            lock_avg_lat = (d_tsc/count) - (holdon_time + wait_time);

        total_acquires += count;
        total_avg_lat_tsc += lock_avg_lat;
        if ( verbose != 0) {
            printf("%6d | %12lu | %18.2f | %18lu\n", i, count, throughput, lock_avg_lat);
        }
    }
    printf("--------------------------------------------------------------------------\n");
    printf("Total  | %12lu | %18.2f | %18lu\n", total_acquires, (double)total_acquires / test_duration, total_avg_lat_tsc/thread_count);
    printf("Shared counter virtual address : %p, counter value: %lu\n", (void*)&shared_counter, shared_counter);

    free(threads);
    free(args);
    free(lock_acquire_counts);
    free(test_duration_tscs);

    return 0;
}  
