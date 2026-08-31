
/**
 * OceanBase Atomic CAS Timestamp Tool


 多线程模型的micro-benchmark程序编写，请基于Linux使用C语言写一个程序，能启动若干个(可以参数指定)worker线程，启动1个master线程，所有worker线程维护若干个tablet数组（可以参数指定数量），而每个tablet数组都有一个锁保护，当前所属的worker和master线程能抢锁访问这些tablet数组。每个tablet数组中维护30个(可以参数指定) MacroBlock，而每个MacroBlock是一个结构体，包含元素有：timestamp 和一个计数器，和所属的worker ID。另外，希望能指定线程的core 绑定方式，使用对于master线程和worker线程能分别指定。 
工作模式是： 每个worker 定期去增加自己所属的tablet中的MacroBlock中的计算器和timestamp，可以考虑每sleep 100ms(可以参数指定)之后抢tablet锁，更新一次timestamp。 同时Master线程一直循环去scan所有worker对应的tablet，拿到锁，检查tablet中MacroBlocks 的timestamp，参考这个函数：
int ObTablet::refresh_macro_new_timestamp(int64_t timestamp)
{
  int ret = OB_SUCCESS;

  if (NULL == meta_image_) {
    TBSYS_LOG(ERROR, "not initialize tablet, cannot mark.");
    ret = OB_NOT_INIT;
  } else {
    for (int64_t i = 0;
         OB_SUCCESS == ret && i < macro_block_count_;
         ++i) {

      ObMacroBlockMeta *meta =
          const_cast<ObMacroBlockMeta *>(get_macro_block_meta(i));

      if (NULL == meta) {
        ret = OB_ERR_UNEXPECTED;
      } else {

        int64_t old_timestamp = meta->timestamp_;

        while (old_timestamp < timestamp) {

          if (old_timestamp ==
              ATOMIC_CAS(&meta->timestamp_,
                         old_timestamp,
                         timestamp)) {
            break;
          }

          old_timestamp = meta->timestamp_;
        }
      }
    }
  }

  return ret;
}

统计refresh_macro_new_timestamp的函数执行时延
统计worker update的throughput
统计Master 做CAS的throughput



 * How to use this tool:
  * numactl -m 0 -C 0-15,64-79 ./ob_cas_timestamp -w 32 -t 200000 -m 20 -s 100 -d 120 -M 31 -W 0 -l spin -i 4



 */




#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <pthread.h>
#include <sched.h>
#include <unistd.h>
#include <time.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <ctype.h>
#include <getopt.h>

#define OB_SUCCESS 0
#define OB_ERR_UNEXPECTED -1

// ATOMIC_CAS 宏定义：模拟返回交换前值的行为
// 如果返回值 == expected，则CAS成功
// 如果返回值 != expected，则CAS失败且返回当前值
#define ATOMIC_CAS(ptr, expected, new_val) \
    ({ \
        int64_t __old_val = (expected); \
        int64_t __ret; \
        if (atomic_compare_exchange_strong_explicit( \
                (ptr), &__old_val, (new_val), \
                memory_order_release, memory_order_relaxed)) { \
            __ret = (expected); \
        } else { \
            __ret = __old_val; \
        } \
        __ret; \
    })

// ================= 数据结构定义 =================

// 显式对齐至 64 字节，防止不同 MacroBlock 的频繁更新导致 Cache Line Bouncing
typedef struct {
    _Atomic int64_t timestamp;
    uint64_t counter;
    int worker_id;
    // 填充字节，确保结构体大小为 64 字节
    char padding[64 - sizeof(_Atomic int64_t) - sizeof(uint64_t) - sizeof(int)];
} __attribute__((aligned(64))) ObMacroBlockMeta;

typedef struct {
    pthread_mutex_t mutex;
    pthread_spinlock_t spin;
    int macro_block_count;
    ObMacroBlockMeta *macro_blocks;
} ObTablet;

typedef struct {
    int worker_id;
    int tablet_count;
    ObTablet *tablets;
    int sleep_ms;
    int core_id; 
} WorkerContext;

typedef struct {
    int worker_count;
    WorkerContext *workers;
    int core_id;
} MasterContext;

typedef enum {
    LOCK_MODE_MUTEX = 0,
    LOCK_MODE_SPIN = 1,
} TabletLockMode;

// ================= 全局统计与状态控制 =================
_Atomic bool g_running = true;
_Atomic uint64_t g_worker_updates = 0;
_Atomic uint64_t g_master_updates = 0;
_Atomic uint64_t g_master_cas_success = 0;
TabletLockMode g_lock_mode = LOCK_MODE_MUTEX;

// ================= 时延统计 =================
typedef struct {
    _Atomic uint64_t count;           // 调用次数
    _Atomic uint64_t total_ns;        // 总耗时（纳秒）
    _Atomic uint64_t min_ns;          // 最小耗时（纳秒）
    _Atomic uint64_t max_ns;          // 最大耗时（纳秒）
} LatencyStats;

LatencyStats g_refresh_latency = {
    .count = 0,
    .total_ns = 0,
    .min_ns = UINT64_MAX,
    .max_ns = 0
};

// Master一轮完整扫描的时延统计
LatencyStats g_master_round_latency = {
    .count = 0,
    .total_ns = 0,
    .min_ns = UINT64_MAX,
    .max_ns = 0
};

// ================= 辅助函数 =================

static inline int64_t get_current_time_ms() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

// 获取当前时间（纳秒级精度）
static inline uint64_t get_current_time_ns() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
    return (uint64_t)ts.tv_sec * 1000000000UL + ts.tv_nsec;
}

// 绑定当前线程到指定的 CPU Core
int bind_thread_to_core(int core_id) {
    if (core_id < 0) return 0; // -1 表示不绑定
    
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset);
    CPU_SET(core_id, &cpuset);
    
    pthread_t current_thread = pthread_self();
    int ret = pthread_setaffinity_np(current_thread, sizeof(cpu_set_t), &cpuset);
    if (ret != 0) {
        fprintf(stderr, "Warning: Failed to bind thread to core %d\n", core_id);
    }
    return ret;
}

static int hex_char_to_int(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return 10 + (c - 'a');
    if (c >= 'A' && c <= 'F') return 10 + (c - 'A');
    return -1;
}

static const char *lock_mode_to_str(TabletLockMode mode)
{
    return mode == LOCK_MODE_SPIN ? "spin" : "mutex";
}

static int init_tablet_lock(ObTablet *tablet)
{
    if (g_lock_mode == LOCK_MODE_SPIN) {
        return pthread_spin_init(&tablet->spin, PTHREAD_PROCESS_PRIVATE);
    }
    return pthread_mutex_init(&tablet->mutex, NULL);
}

static void destroy_tablet_lock(ObTablet *tablet)
{
    if (g_lock_mode == LOCK_MODE_SPIN) {
        pthread_spin_destroy(&tablet->spin);
    } else {
        pthread_mutex_destroy(&tablet->mutex);
    }
}

static inline void tablet_lock(ObTablet *tablet)
{
    if (g_lock_mode == LOCK_MODE_SPIN) {
        pthread_spin_lock(&tablet->spin);
    } else {
        pthread_mutex_lock(&tablet->mutex);
    }
}

static inline void tablet_unlock(ObTablet *tablet)
{
    if (g_lock_mode == LOCK_MODE_SPIN) {
        pthread_spin_unlock(&tablet->spin);
    } else {
        pthread_mutex_unlock(&tablet->mutex);
    }
}

// 解析 Core 掩码（可变长度16进制位掩码，支持超过64位）
// 例如：0x0E -> core 1,2,3；0x10000000000000001 -> core 0,64
// 允许在掩码中使用 '_' 或 ',' 作为分隔符提升可读性
void parse_core_mask(const char *str, int *cores, int max_cores) {
    for (int i = 0; i < max_cores; ++i) cores[i] = -1; // 初始化为不绑定
    if (!str) return;

    const char *p = str;
    if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) {
        p += 2;
    }

    // 收集所有hex字符，忽略分隔符和空白
    char hex_digits[1024];
    int hex_len = 0;
    for (; *p != '\0' && hex_len < (int)sizeof(hex_digits); ++p) {
        if (isxdigit((unsigned char)*p)) {
            hex_digits[hex_len++] = *p;
        } else if (*p == '_' || *p == ',' || isspace((unsigned char)*p)) {
            continue;
        } else {
            fprintf(stderr, "Warning: Invalid mask character '%c' in -W option.\n", *p);
            return;
        }
    }

    if (hex_len == 0) {
        return;
    }

    int core_idx = 0;
    int bit_index = 0;

    // 从最低有效hex位开始解析（字符串末尾）
    for (int i = hex_len - 1; i >= 0 && core_idx < max_cores; --i) {
        int v = hex_char_to_int(hex_digits[i]);
        if (v < 0) {
            continue;
        }

        for (int b = 0; b < 4 && core_idx < max_cores; ++b, ++bit_index) {
            if (bit_index >= CPU_SETSIZE) {
                break;
            }
            if (v & (1 << b)) {
                cores[core_idx++] = bit_index;
            }
        }
    }
}

// ================= 核心业务逻辑 =================

// Master的CAS逻辑，完全按照原始OceanBase代码逻辑
// 使用ATOMIC_CAS宏，返回交换前的值
// 若返回值 == old_timestamp，则CAS成功
__attribute__((noinline))
int refresh_macro_new_timestamp(ObTablet *tablet, int64_t scan_timestamp, uint64_t *cas_success) {
    // 记录函数执行时延
    uint64_t start_ns = get_current_time_ns();
    
    int ret = OB_SUCCESS;

    if (NULL == tablet || NULL == tablet->macro_blocks) {
        ret = OB_ERR_UNEXPECTED;
    } else {
        for (int i = 0; OB_SUCCESS == ret && i < tablet->macro_block_count; ++i) {
            ObMacroBlockMeta *meta = &tablet->macro_blocks[i];

            if (NULL == meta) {
                ret = OB_ERR_UNEXPECTED;
            } else {
                // 初始读取当前timestamp
                int64_t old_timestamp = atomic_load_explicit(&meta->timestamp, memory_order_relaxed);

                while (old_timestamp < scan_timestamp) {
                    // ATOMIC_CAS 返回交换前的值
                    if (old_timestamp == ATOMIC_CAS(&meta->timestamp, old_timestamp, scan_timestamp)) {
                        // CAS成功
                        (*cas_success)++;
                        break;
                    }

                    // CAS失败，重新读取当前值
                    old_timestamp = atomic_load_explicit(&meta->timestamp, memory_order_relaxed);
                }
            }
        }
    }

    // 记录时延统计
    uint64_t end_ns = get_current_time_ns();
    uint64_t latency_ns = end_ns - start_ns;
    
    atomic_fetch_add_explicit(&g_refresh_latency.count, 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&g_refresh_latency.total_ns, latency_ns, memory_order_relaxed);
    
    // 更新最小值
    uint64_t cur_min = atomic_load_explicit(&g_refresh_latency.min_ns, memory_order_relaxed);
    while (latency_ns < cur_min) {
        if (atomic_compare_exchange_weak_explicit(&g_refresh_latency.min_ns, &cur_min, latency_ns,
                memory_order_relaxed, memory_order_relaxed)) {
            break;
        }
    }
    
    // 更新最大值
    uint64_t cur_max = atomic_load_explicit(&g_refresh_latency.max_ns, memory_order_relaxed);
    while (latency_ns > cur_max) {
        if (atomic_compare_exchange_weak_explicit(&g_refresh_latency.max_ns, &cur_max, latency_ns,
                memory_order_relaxed, memory_order_relaxed)) {
            break;
        }
    }

    return ret;
}

// Worker 线程入口
void* worker_routine(void *arg) {
    WorkerContext *ctx = (WorkerContext*)arg;
    bind_thread_to_core(ctx->core_id);
    
    while (atomic_load_explicit(&g_running, memory_order_relaxed)) {
        int64_t now = get_current_time_ms();
        
        for (int i = 0; i < ctx->tablet_count; ++i) {
            ObTablet *tablet = &ctx->tablets[i];

            tablet_lock(tablet);
            for (int j = 0; j < tablet->macro_block_count; ++j) {
                tablet->macro_blocks[j].counter++;
                // 覆盖写入时间戳
                atomic_store_explicit(&tablet->macro_blocks[j].timestamp, now, memory_order_relaxed);
            }
            tablet_unlock(tablet);

//mz            atomic_fetch_add_explicit(&g_worker_updates, 1, memory_order_relaxed);
        }
        
        if (ctx->sleep_ms > 0) {
            usleep(ctx->sleep_ms * 1000);
        }
    }
    return NULL;
}

// Master 线程入口
void* master_routine(void *arg) {
    MasterContext *ctx = (MasterContext*)arg;
    bind_thread_to_core(ctx->core_id);
    
    while (atomic_load_explicit(&g_running, memory_order_relaxed)) {
        uint64_t round_start_ns = get_current_time_ns();
        
        int64_t scan_timestamp = get_current_time_ms();
        uint64_t current_cas_success = 0;
        
        for (int w = 0; w < ctx->worker_count; ++w) {
            WorkerContext *wctx = &ctx->workers[w];
            
            for (int t = 0; t < wctx->tablet_count; ++t) {
                ObTablet *tablet = &wctx->tablets[t];
                
                // Master 抢锁并执行 CAS 检查
                tablet_lock(tablet);
                refresh_macro_new_timestamp(tablet, scan_timestamp, &current_cas_success);
                tablet_unlock(tablet);
            }
            atomic_fetch_add_explicit(&g_master_updates, 1, memory_order_relaxed);


        }
        atomic_fetch_add_explicit(&g_master_cas_success, current_cas_success, memory_order_relaxed);

        uint64_t round_end_ns = get_current_time_ns();
        uint64_t round_latency_ns = round_end_ns - round_start_ns;

        atomic_fetch_add_explicit(&g_master_round_latency.count, 1, memory_order_relaxed);
        atomic_fetch_add_explicit(&g_master_round_latency.total_ns, round_latency_ns, memory_order_relaxed);

        uint64_t cur_min = atomic_load_explicit(&g_master_round_latency.min_ns, memory_order_relaxed);
        while (round_latency_ns < cur_min) {
            if (atomic_compare_exchange_weak_explicit(&g_master_round_latency.min_ns, &cur_min, round_latency_ns,
                    memory_order_relaxed, memory_order_relaxed)) {
                break;
            }
        }

        uint64_t cur_max = atomic_load_explicit(&g_master_round_latency.max_ns, memory_order_relaxed);
        while (round_latency_ns > cur_max) {
            if (atomic_compare_exchange_weak_explicit(&g_master_round_latency.max_ns, &cur_max, round_latency_ns,
                    memory_order_relaxed, memory_order_relaxed)) {
                break;
            }
        }
    }
    return NULL;
}

// ================= 主函数与参数解析 =================

void print_usage(const char* prog_name) {
    printf("Usage: %s [options]\n", prog_name);
    printf("Options:\n");
    printf("  -w <num>   Number of worker threads (default: 4)\n");
    printf("  -t <num>   Total tablets across all workers (default: 10)\n");
    printf("  -m <num>   MacroBlocks per tablet (default: 30)\n");
    printf("  -s <ms>    Worker sleep interval in ms (default: 100)\n");
    printf("  -d <sec>   Benchmark duration in seconds (default: 10)\n");
    printf("  -i <sec>   Monitor print interval in seconds (default: 1)\n");
    printf("  -M <core>  Bind master thread to a specific core ID (default: -1, no bind)\n");
    printf("  -W <mask>  Hex bitmask for worker core binding (supports >64 bits, e.g., 0x10000000000000001 for cores 0,64)\n");
    printf("  -l <type>  Tablet lock type: mutex|spin (default: mutex)\n");
    printf("  -h         Show help\n");
}

int main(int argc, char* argv[]) {
    int num_workers = 4;
    int total_tablets = 10;
    int macro_blocks_per_tablet = 30;
    int worker_sleep_ms = 100;
    int duration_seconds = 10;
    int monitor_interval_sec = 1;
    int master_core = -1;
    char worker_cores_str[256] = "";
    char lock_type_str[16] = "mutex";

    int opt;
    while ((opt = getopt(argc, argv, "w:t:m:s:d:i:M:W:l:h")) != -1) {
        switch (opt) {
            case 'w': num_workers = atoi(optarg); break;
            case 't': total_tablets = atoi(optarg); break;
            case 'm': macro_blocks_per_tablet = atoi(optarg); break;
            case 's': worker_sleep_ms = atoi(optarg); break;
            case 'd': duration_seconds = atoi(optarg); break;
            case 'i': monitor_interval_sec = atoi(optarg); break;
            case 'M': master_core = atoi(optarg); break;
            case 'W': strncpy(worker_cores_str, optarg, sizeof(worker_cores_str)-1); break;
            case 'l': strncpy(lock_type_str, optarg, sizeof(lock_type_str)-1); break;
            case 'h': print_usage(argv[0]); return 0;
            default: print_usage(argv[0]); return 1;
        }
    }

    if (strcmp(lock_type_str, "mutex") == 0) {
        g_lock_mode = LOCK_MODE_MUTEX;
    } else if (strcmp(lock_type_str, "spin") == 0) {
        g_lock_mode = LOCK_MODE_SPIN;
    } else {
        fprintf(stderr, "Error: invalid lock type '%s', expected mutex or spin\n", lock_type_str);
        return 1;
    }

    if (num_workers <= 0) {
        fprintf(stderr, "Error: -w must be > 0\n");
        return 1;
    }
    if (total_tablets < 0) {
        fprintf(stderr, "Error: -t must be >= 0\n");
        return 1;
    }
    if (duration_seconds <= 0) {
        fprintf(stderr, "Error: -d must be > 0\n");
        return 1;
    }
    if (monitor_interval_sec <= 0) {
        fprintf(stderr, "Error: -i must be > 0\n");
        return 1;
    }

    int *worker_cores = malloc(num_workers * sizeof(int));
    parse_core_mask(worker_cores_str, worker_cores, num_workers);

    int base_tablets = total_tablets / num_workers;
    int rem_tablets = total_tablets % num_workers;

    printf("========== Benchmark Topology ==========\n");
    printf("Workers                : %d\n", num_workers);
    printf("Total Tablets          : %d\n", total_tablets);
    printf("Tablet Distribution    : base=%d, remainder=%d\n", base_tablets, rem_tablets);
    printf("MacroBlocks/Tablet     : %d\n", macro_blocks_per_tablet);
    printf("Worker Sleep           : %d ms\n", worker_sleep_ms);
    printf("Monitor Interval       : %d sec\n", monitor_interval_sec);
    printf("Tablet Lock Type       : %s\n", lock_mode_to_str(g_lock_mode));
    printf("Master Core Binding    : %d\n", master_core);
    printf("Worker Core Bindings   : ");
    for (int i = 0; i < num_workers; ++i) printf("%d ", worker_cores[i]);
    printf("\n========================================\n");

    // 内存分配与初始化
    WorkerContext *workers = malloc(num_workers * sizeof(WorkerContext));
    for (int i = 0; i < num_workers; ++i) {
        workers[i].worker_id = i;
        workers[i].tablet_count = base_tablets + (i < rem_tablets ? 1 : 0);
        workers[i].sleep_ms = worker_sleep_ms;
        workers[i].core_id = worker_cores[i];
        workers[i].tablets = workers[i].tablet_count > 0 ?
            malloc((size_t)workers[i].tablet_count * sizeof(ObTablet)) : NULL;
        
        for (int j = 0; j < workers[i].tablet_count; ++j) {
            if (init_tablet_lock(&workers[i].tablets[j]) != 0) {
                fprintf(stderr, "Error: failed to init tablet lock for worker=%d tablet=%d\n", i, j);
                return 1;
            }
            workers[i].tablets[j].macro_block_count = macro_blocks_per_tablet;
            workers[i].tablets[j].macro_blocks = aligned_alloc(64, macro_blocks_per_tablet * sizeof(ObMacroBlockMeta));
            
            int64_t init_time = get_current_time_ms();
            for (int k = 0; k < macro_blocks_per_tablet; ++k) {
                atomic_init(&workers[i].tablets[j].macro_blocks[k].timestamp, init_time);
                workers[i].tablets[j].macro_blocks[k].counter = 0;
                workers[i].tablets[j].macro_blocks[k].worker_id = i;
            }
        }
    }

    MasterContext master_ctx = {
        .worker_count = num_workers,
        .workers = workers,
        .core_id = master_core
    };

    pthread_t master_thread;
    pthread_t *worker_threads = malloc(num_workers * sizeof(pthread_t));

    // 启动线程
    for (int i = 0; i < num_workers; ++i) {
        pthread_create(&worker_threads[i], NULL, worker_routine, &workers[i]);
    }
    pthread_create(&master_thread, NULL, master_routine, &master_ctx);

    // 采样监控循环（打印间隔可配置，单位：秒）
    int64_t total_sec = duration_seconds;
    int64_t elapsed_sec = 0;
    int sample_idx = 0;
    while (elapsed_sec < total_sec) {
        int64_t remaining_sec = total_sec - elapsed_sec;
        int cur_interval_sec = remaining_sec < monitor_interval_sec ? (int)remaining_sec : monitor_interval_sec;

        struct timespec req;
        req.tv_sec = cur_interval_sec;
        req.tv_nsec = 0;
        nanosleep(&req, NULL);

        elapsed_sec += cur_interval_sec;
        sample_idx++;

        uint64_t w_ops = atomic_exchange_explicit(&g_worker_updates, 0, memory_order_relaxed);
        uint64_t m_updates = atomic_exchange_explicit(&g_master_updates, 0, memory_order_relaxed);
        uint64_t m_cas = atomic_exchange_explicit(&g_master_cas_success, 0, memory_order_relaxed);

        // 获取时延统计
        uint64_t count = atomic_load_explicit(&g_refresh_latency.count, memory_order_relaxed);
        uint64_t total_ns = atomic_load_explicit(&g_refresh_latency.total_ns, memory_order_relaxed);
        uint64_t min_ns = atomic_load_explicit(&g_refresh_latency.min_ns, memory_order_relaxed);
        uint64_t max_ns = atomic_load_explicit(&g_refresh_latency.max_ns, memory_order_relaxed);

        // 获取Master一轮扫描的时延统计
        uint64_t round_count = atomic_load_explicit(&g_master_round_latency.count, memory_order_relaxed);
        uint64_t round_total_ns = atomic_load_explicit(&g_master_round_latency.total_ns, memory_order_relaxed);
        uint64_t round_min_ns = atomic_load_explicit(&g_master_round_latency.min_ns, memory_order_relaxed);
        uint64_t round_max_ns = atomic_load_explicit(&g_master_round_latency.max_ns, memory_order_relaxed);

         double scale = 1.0 / (double)cur_interval_sec;
         double w_rate = (double)w_ops * scale;
         double m_rate = (double)m_updates * scale;
         double cas_rate = (double)m_cas * scale;

         printf("[Sample %02d @ %4ds] Worker Upd: %10.2f/s | Master Upd: %10.2f/s | Master CAS Ok: %10.2f/s\n",
             sample_idx, cur_interval_sec, w_rate, m_rate, cas_rate);
        
        // 输出时延统计（仅当有数据时）
        if (count > 0) {
            uint64_t avg_ns = total_ns / count;
            printf("         Latency (refresh_macro_new_timestamp): min=%lu ns, avg=%lu ns, max=%lu ns, calls=%lu\n",
                   min_ns, avg_ns, max_ns, count);
            
            // 重置统计数据
             atomic_store_explicit(&g_refresh_latency.count, 0, memory_order_relaxed);
             atomic_store_explicit(&g_refresh_latency.total_ns, 0, memory_order_relaxed);
            atomic_store_explicit(&g_refresh_latency.min_ns, UINT64_MAX, memory_order_relaxed);
            atomic_store_explicit(&g_refresh_latency.max_ns, 0, memory_order_relaxed);
        }

        // 输出Master一轮扫描的时延统计
        if (round_count > 0) {
            uint64_t round_avg_ns = round_total_ns / round_count;
            printf("         Latency (master_round_scan): min=%lu ns, avg=%lu ns, max=%lu ns, calls=%lu\n",
                   round_min_ns, round_avg_ns, round_max_ns, round_count);

            // 重置Master时延统计数据
            atomic_store_explicit(&g_master_round_latency.count, 0, memory_order_relaxed);
            atomic_store_explicit(&g_master_round_latency.total_ns, 0, memory_order_relaxed);
            atomic_store_explicit(&g_master_round_latency.min_ns, UINT64_MAX, memory_order_relaxed);
            atomic_store_explicit(&g_master_round_latency.max_ns, 0, memory_order_relaxed);
        }
    }

    // 终止与资源回收
    atomic_store_explicit(&g_running, false, memory_order_relaxed);

    for (int i = 0; i < num_workers; ++i) {
        pthread_join(worker_threads[i], NULL);
    }
    pthread_join(master_thread, NULL);

    for (int i = 0; i < num_workers; ++i) {
        for (int j = 0; j < workers[i].tablet_count; ++j) {
            free(workers[i].tablets[j].macro_blocks);
            destroy_tablet_lock(&workers[i].tablets[j]);
        }
        free(workers[i].tablets);
    }
    free(workers);
    free(worker_threads);
    free(worker_cores);

    printf("Benchmark finished.\n");
    return 0;
}
