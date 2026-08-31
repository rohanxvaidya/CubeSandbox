/*
* insmod mtest2.ko
* echo 112 > /sys/kernel/spinlock_bench/counter   // create 112 thread to increase the value with spinlock aquiring.
* echo 1 > /sys/kernel/spinlock_bench/test_on
* echo 0 > /sys/kernel/spinlock_bench/test_on
* sleep 10s
* echo 1 > /sys/kernel/spinlock_bench/stop_threads
* rmmod mtest2
*
* The cpuaffinity node allows users to specify a CPU mask in the form of a string (e.g., F1 or 3F).
* echo F1 > /sys/kernel/spinlock_bench/cpuaffinity  // CPU affinity updated: 0,4-7
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/sysfs.h>
#include <linux/kobject.h>
#include <linux/string.h>
#include <linux/spinlock.h>
#include <linux/kthread.h>
#include <linux/delay.h>
#include <linux/smp.h> // For num_online_cpus()
#include <linux/cache.h>
#include <linux/slab.h>
#include <linux/ctype.h>
// spinlock 
#include <linux/spinlock_api_smp.h>
#include <asm-generic/qspinlock.h>
#include <asm-generic/qspinlock_types.h>
#include <linux/atomic.h>
#include <linux/cpumask.h>
#include <linux/percpu.h>
#include <linux/hardirq.h>
#include <linux/mutex.h>
#include <linux/prefetch.h>
#include <asm/byteorder.h>
#include <asm/qspinlock.h>
#include <asm/mcs_spinlock.h>
//#include <kernel/locking/mcs_spinlock.h>
#include <asm/io.h>
#include <linux/mm.h>
#include <linux/cpumask.h> // For CPU masks
//#include "intel_platform_kernel.h"
// for mutex lock
#include <linux/mutex.h>

#define VERSION     "V1.2"
#define MY_LOCK_TRACE 0
#if MY_LOCK_TRACE
#define CREATE_TRACE_POINTS
//TODO: need to refine this if need trace in module, by default, we need put sh header file in include/trace/events/my_lock.h
#include "my_lock.h"
#endif

#define MAX_CORES 256   //max cpu core support for cpu mask.

#define MY_LOCK_LATENCY 1
#define MY_LOCK_TRACE_PRT 1
#define SPINLOCK_BENCH_DEBUG_ON 0

#define USE_SPINLOCK_IRQ    1
#define USE_RAW_SPINLOCK_IRQ    1
#define USE_MY_RAW_SPINLOCK_IRQ    1
#define MY_SPINLOCK_SLOWPATH    0
//To simulate the fio XFS pwqs flush operations.
#define SIMULATE_XFS_PWQS_FLUSH     0
//used atomic ops to read/write shared value.
#define ATOMIC_OPS  1

// handle more heavier work after locked.
#define LAZY_LOCK_WORK  0

#define SIMPLE_THREAD   0
#if SIMPLE_THREAD
    #define SPINLOCK_NOT_USE_STATIC_MEM 0
#else 
    #define SPINLOCK_NOT_USE_STATIC_MEM 1
#endif 

#if SPINLOCK_NOT_USE_STATIC_MEM
    #define SPINLOCK_ALLOCATE_PAGE_ORDER    8   // 256 pages, 1M bytes.
#endif
//#define START_THREADS_WITH_TEST_ON


#define SYSFS_DIR_NAME "spinlock_bench"
#define MAX_VALUE 1000000000
#define SIM_TIME    10  // million seconds.

#if SPINLOCK_BENCH_DEBUG_ON
#define MAX_VALUE 10000
#define SIM_TIME    100  // million seconds.

#endif

// Worker threads
static struct task_struct *thread1, *thread2;


#if SIMPLE_THREAD 
static int threads_on_spinlock(void);

static int thread_fn1(void *data);
static int thread_fn2(void *data);
#else 
static int thread_fn_common(void *data);
#endif

// Global variables exposed via sysfs
static bool test_on = false;   // Second sysfs value (boolean)
static bool start_threads = false;
static bool stop_threads = false;
static int thread_num = 1;        // Third sysfs value (counter)
static int nr_cpu = 64;      // >= 1 cpu, default is 64 core 


#if ATOMIC_OPS
struct my_struct {
    atomic64_t shared_value;
    char padding[64];
} __cacheline_aligned;

//static atomic64_t shared_value;
static struct my_struct my_shared_data;
static atomic64_t spinlock_bench_value;
#else 
struct my_struct {
    long long shared_value;
} __cacheline_aligned;

static long long spinlock_bench_value = 0;  // First sysfs value
static struct my_struct my_shared_data;
//static long long shared_value = 0;
#endif

// CPU affinity mask
static cpumask_t cpuaffinity_mask = CPU_MASK_CPU0; //mask core 0, CPU_MASK_ALL; // Default to all CPUs

static int test_flag = 0;

static DEFINE_MUTEX(control_lock);

uint64_t g_lock_virt_addr = 0;
uint64_t lock_base_virt_addr = 0;
phys_addr_t lock_base_phys_addr;
phys_addr_t g_lock_phys_addr;
struct page *lock_page;
phys_addr_t lock_page_phys_addr;

int g_cha_id = -1;
// Used for set the memory address offset, 
// the physical address should be maping to the selected cha_id.
uint64_t offset4selected_cha = 0;   

// Spinlock for protecting shared variables
static spinlock_t spinlock_bench_spinlock ____cacheline_aligned_in_smp;
//raw_spinlock_t
spinlock_t *bench_spinlock_ptr = (spinlock_t *)&spinlock_bench_spinlock;

//mutex lock
struct mutex	mutex_bench_lock __cacheline_aligned;
struct mutex    *bench_mutex_ptr = (struct mutex *)&mutex_bench_lock;

// pthread spinlock
typedef struct my_pthread_spinlock {
    atomic64_t value;
    uint64_t padding[7];
} my_pthread_spinlock_t;

static my_pthread_spinlock_t my_pthread_lock __cacheline_aligned;
my_pthread_spinlock_t *my_plock_ptr = (struct my_pthread_spinlock *) &my_pthread_lock;

// Sysfs directory kobject
static struct kobject *spinlock_bench_kobj;

// Dynamic array of threads
static struct task_struct **threads;

// Flag to signal threads to stop
static bool threads_should_stop = false;

// Time tracking variables
static ktime_t thread_start_time;
static ktime_t thread_stop_time;

static bool g_trace_print = false;
static uint64_t g_test_duration_ns;    //ns for test duration
static int g_other_works_pause_us = 0;
static int g_other_works_sleep_us = 0;
static uint64_t g_holdon_time_cycles = 0;   // hold on duration in critical section, with cycles.
static uint64_t g_other_works_wait_time_cycles = 0;
static int g_tsc_freq_mhz_per_us = 2700;   //if tsc frequency is 2.7GHz
static int g_rdtsc_overhead=0;

#if SPINLOCK_NOT_USE_STATIC_MEM
static int g_mem_page_order = SPINLOCK_ALLOCATE_PAGE_ORDER; // 8  // 256 pages, 1M bytes.
static int g_numa_node_id = 0;  //by default use the first numa node memory.
#endif
static int g_dynamic_lock_addr = 1; // by default use the dynamic lock address for spinlock bench.

// Thread states
enum thread_state {
    THREAD_STOPPED=0,
    THREAD_STARTED=1,
    THREAD_RUNNING=2,
};

#define BATCH_LOCK_FLAG     0x80
// lock algorithm mode selection
enum lock_algo_mode {
    QUEUE_LOCK=0,
    RETRY_LOCK=1,
    PTHREAD_LOCK=2,
    MUTEX_LOCK=3,
    TICKET_LOCK=4,

    BATCH_LOCK=BATCH_LOCK_FLAG,
    BATCH_QUEUE_LOCK=BATCH_LOCK_FLAG | QUEUE_LOCK ,
    BATCH_RETRY_LOCK=BATCH_LOCK_FLAG | RETRY_LOCK,
    BATCH_PTHREAD_LOCK=BATCH_LOCK_FLAG | PTHREAD_LOCK,
    BATCH_MUTEX_LOCK=BATCH_LOCK_FLAG | MUTEX_LOCK,
    BATCH_TICKET_LOCK=BATCH_LOCK_FLAG | TICKET_LOCK,

    LAST_LOCK
};

static int g_lock_mode = QUEUE_LOCK;
static int g_batch_lock = 0;

// Per-thread data structure
struct thread_private_data {
    int thread_id;
    int state;                            // Thread's state (running or stopped)
    int cpu_id;
    bool test_on;
    unsigned long thread_private_counter; // Counter incremented after acquiring the lock
    unsigned long flags;                  // Reserved for future use
    unsigned long attempt_count;          // Total attempts to acquire the lock
    unsigned long acquired_count;          // Successful lock acquisitions
    unsigned long acquiring_time;          // getting lock time in ns;
}____cacheline_aligned_in_smp;
//}__aligned(CACHELINE_SIZE);

static struct thread_private_data *threads_data;

static uint64_t kvirt_to_phys(void *virt_addr);

//////////////////////////////////////////////////////////////////////
//  spinlock functions
//////////////////////////////////////////////////////////////////////
#if MY_SPINLOCK_SLOWPATH

/// mcs spinlock
// in kernel/locking/mcs_spinlock.h"
struct mcs_spinlock {
	struct mcs_spinlock *next;
	int locked; /* 1 if lock acquired */
	int count;  /* nesting count, see qspinlock.c */
};

#ifndef arch_mcs_spin_lock_contended
/*
 * Using smp_cond_load_acquire() provides the acquire semantics
 * required so that subsequent operations happen after the
 * lock is acquired. Additionally, some architectures such as
 * ARM64 would like to do spin-waiting instead of purely
 * spinning, and smp_cond_load_acquire() provides that behavior.
 */
#define arch_mcs_spin_lock_contended(l)					\
do {									\
	smp_cond_load_acquire(l, VAL);					\
} while (0)
#endif

#ifndef arch_mcs_spin_unlock_contended
/*
 * smp_store_release() provides a memory barrier to ensure all
 * operations in the critical section has been completed before
 * unlocking.
 */
#define arch_mcs_spin_unlock_contended(l)				\
	smp_store_release((l), 1)
#endif


// qspinlock slowpath
//kernel/locking/qspinlock.c
//
/*
 * Generate the native code for queued_spin_unlock_slowpath(); provide NOPs for
 * all the PV callbacks.
 */

static __always_inline void __pv_init_node(struct mcs_spinlock *node) { }
static __always_inline void __pv_wait_node(struct mcs_spinlock *node,
					   struct mcs_spinlock *prev) { }
static __always_inline void __pv_kick_node(struct qspinlock *lock,
					   struct mcs_spinlock *node) { }
static __always_inline u32  __pv_wait_head_or_lock(struct qspinlock *lock,
						   struct mcs_spinlock *node)
						   { return 0; }

#define pv_enabled()		false

#define pv_init_node		__pv_init_node
#define pv_wait_node		__pv_wait_node
#define pv_kick_node		__pv_kick_node
#define pv_wait_head_or_lock	__pv_wait_head_or_lock


noinline void __lockfunc my_queued_spin_lock_slowpath(struct qspinlock *lock, u32 val);
#define my_queued_spin_lock_slowpath    my_native_queued_spin_lock_slowpath


//////
#define MAX_NODES	4

/*
 * On 64-bit architectures, the mcs_spinlock structure will be 16 bytes in
 * size and four of them will fit nicely in one 64-byte cacheline. For
 * pvqspinlock, however, we need more space for extra data. To accommodate
 * that, we insert two more long words to pad it up to 32 bytes. IOW, only
 * two of them can fit in a cacheline in this case. That is OK as it is rare
 * to have more than 2 levels of slowpath nesting in actual use. We don't
 * want to penalize pvqspinlocks to optimize for a rare case in native
 * qspinlocks.
 */
struct qnode {
	struct mcs_spinlock mcs;
#ifdef CONFIG_PARAVIRT_SPINLOCKS
	long reserved[2];
#endif
};

/*
 * The pending bit spinning loop count.
 * This heuristic is used to limit the number of lockword accesses
 * made by atomic_cond_read_relaxed when waiting for the lock to
 * transition out of the "== _Q_PENDING_VAL" state. We don't spin
 * indefinitely because there's no guarantee that we'll make forward
 * progress.
 */
#ifndef _Q_PENDING_LOOPS
#define _Q_PENDING_LOOPS	1
#endif

/*
 * Per-CPU queue node structures; we can never have more than 4 nested
 * contexts: task, softirq, hardirq, nmi.
 *
 * Exactly fits one 64-byte cacheline on a 64-bit architecture.
 *
 * PV doubles the storage and uses the second cacheline for PV state.
 */
static DEFINE_PER_CPU_ALIGNED(struct qnode, qnodes[MAX_NODES]);

/*
 * We must be able to distinguish between no-tail and the tail at 0:0,
 * therefore increment the cpu number by one.
 */

static inline __pure u32 encode_tail(int cpu, int idx)
{
	u32 tail;

	tail  = (cpu + 1) << _Q_TAIL_CPU_OFFSET;
	tail |= idx << _Q_TAIL_IDX_OFFSET; /* assume < 4 */

	return tail;
}

static inline __pure struct mcs_spinlock *decode_tail(u32 tail)
{
	int cpu = (tail >> _Q_TAIL_CPU_OFFSET) - 1;
	int idx = (tail &  _Q_TAIL_IDX_MASK) >> _Q_TAIL_IDX_OFFSET;

	return per_cpu_ptr(&qnodes[idx].mcs, cpu);
}

static inline __pure
struct mcs_spinlock *grab_mcs_node(struct mcs_spinlock *base, int idx)
{
	return &((struct qnode *)base + idx)->mcs;
}

#define _Q_LOCKED_PENDING_MASK (_Q_LOCKED_MASK | _Q_PENDING_MASK)

#if _Q_PENDING_BITS == 8
/**
 * clear_pending - clear the pending bit.
 * @lock: Pointer to queued spinlock structure
 *
 * *,1,* -> *,0,*
 */
static __always_inline void clear_pending(struct qspinlock *lock)
{
	WRITE_ONCE(lock->pending, 0);
}

/**
 * clear_pending_set_locked - take ownership and clear the pending bit.
 * @lock: Pointer to queued spinlock structure
 *
 * *,1,0 -> *,0,1
 *
 * Lock stealing is not allowed if this function is used.
 */
static __always_inline void clear_pending_set_locked(struct qspinlock *lock)
{
	WRITE_ONCE(lock->locked_pending, _Q_LOCKED_VAL);
}

/*
 * xchg_tail - Put in the new queue tail code word & retrieve previous one
 * @lock : Pointer to queued spinlock structure
 * @tail : The new queue tail code word
 * Return: The previous queue tail code word
 *
 * xchg(lock, tail), which heads an address dependency
 *
 * p,*,* -> n,*,* ; prev = xchg(lock, node)
 */
static __always_inline u32 xchg_tail(struct qspinlock *lock, u32 tail)
{
	/*
	 * We can use relaxed semantics since the caller ensures that the
	 * MCS node is properly initialized before updating the tail.
	 */
	return (u32)xchg_relaxed(&lock->tail,
				 tail >> _Q_TAIL_OFFSET) << _Q_TAIL_OFFSET;
}

#else /* _Q_PENDING_BITS == 8 */

/**
 * clear_pending - clear the pending bit.
 * @lock: Pointer to queued spinlock structure
 *
 * *,1,* -> *,0,*
 */
static __always_inline void clear_pending(struct qspinlock *lock)
{
	atomic_andnot(_Q_PENDING_VAL, &lock->val);
}

/**
 * clear_pending_set_locked - take ownership and clear the pending bit.
 * @lock: Pointer to queued spinlock structure
 *
 * *,1,0 -> *,0,1
 */
static __always_inline void clear_pending_set_locked(struct qspinlock *lock)
{
	atomic_add(-_Q_PENDING_VAL + _Q_LOCKED_VAL, &lock->val);
}

/**
 * xchg_tail - Put in the new queue tail code word & retrieve previous one
 * @lock : Pointer to queued spinlock structure
 * @tail : The new queue tail code word
 * Return: The previous queue tail code word
 *
 * xchg(lock, tail)
 *
 * p,*,* -> n,*,* ; prev = xchg(lock, node)
 */
static __always_inline u32 xchg_tail(struct qspinlock *lock, u32 tail)
{
	u32 old, new, val = atomic_read(&lock->val);

	for (;;) {
		new = (val & _Q_LOCKED_PENDING_MASK) | tail;
		/*
		 * We can use relaxed semantics since the caller ensures that
		 * the MCS node is properly initialized before updating the
		 * tail.
		 */
		old = atomic_cmpxchg_relaxed(&lock->val, val, new);
		if (old == val)
			break;

		val = old;
	}
	return old;
}
#endif /* _Q_PENDING_BITS == 8 */

/**
 * queued_fetch_set_pending_acquire - fetch the whole lock value and set pending
 * @lock : Pointer to queued spinlock structure
 * Return: The previous lock value
 *
 * *,*,* -> *,1,*
 */
#ifndef queued_fetch_set_pending_acquire
static __always_inline u32 queued_fetch_set_pending_acquire(struct qspinlock *lock)
{
	return atomic_fetch_or_acquire(_Q_PENDING_VAL, &lock->val);
}
#endif

/**
 * set_locked - Set the lock bit and own the lock
 * @lock: Pointer to queued spinlock structure
 *
 * *,*,0 -> *,0,1
 */
static __always_inline void set_locked(struct qspinlock *lock)
{
	WRITE_ONCE(lock->locked, _Q_LOCKED_VAL);
}

static __always_inline void set_pending(struct qspinlock *lock)
{
	WRITE_ONCE(lock->pending, _Q_PENDING_VAL);
}


/**
 * queued_spin_lock_slowpath - acquire the queued spinlock
 * @lock: Pointer to queued spinlock structure
 * @val: Current value of the queued spinlock 32-bit word
 *
 * (queue tail, pending bit, lock value)
 *
 *              fast     :    slow                                  :    unlock
 *                       :                                          :
 * uncontended  (0,0,0) -:--> (0,0,1) ------------------------------:--> (*,*,0)
 *                       :       | ^--------.------.             /  :
 *                       :       v           \      \            |  :
 * pending               :    (0,1,1) +--> (0,1,0)   \           |  :
 *                       :       | ^--'              |           |  :
 *                       :       v                   |           |  :
 * uncontended           :    (n,x,y) +--> (n,0,0) --'           |  :
 *   queue               :       | ^--'                          |  :
 *                       :       v                               |  :
 * contended             :    (*,x,y) +--> (*,0,0) ---> (*,0,1) -'  :
 *   queue               :         ^--'                             :
 */
noinline void __lockfunc my_queued_spin_lock_slowpath(struct qspinlock *lock, u32 val)
{
	struct mcs_spinlock *prev, *next, *node;
	u32 old, tail;
	int idx;

//#if SPINLOCK_BENCH_DEBUG_ON
//    pr_info("spinlock_bench_sysfs: %s\n", __FUNCTION__);
//#endif
/*
	BUILD_BUG_ON(CONFIG_NR_CPUS >= (1U << _Q_TAIL_CPU_BITS));

	if (pv_enabled())
		goto pv_queue;

	if (virt_spin_lock(lock))
		return;
*/

	/*
	 * Wait for in-progress pending->locked hand-overs with a bounded
	 * number of spins so that we guarantee forward progress.
	 *
	 * 0,1,0 -> 0,0,1
	 */
	if (val == _Q_PENDING_VAL) {
		int cnt = _Q_PENDING_LOOPS;
		val = atomic_cond_read_relaxed(&lock->val,
					       (VAL != _Q_PENDING_VAL) || !cnt--);
	}

	/*
	 * If we observe any contention; queue.
	 */
	if (val & ~_Q_LOCKED_MASK)
		goto queue;   // *,*,1

	/*
	 * trylock || pending
	 *
	 * 0,0,* -> 0,1,* -> 0,0,1 pending, trylock
	 */
	val = queued_fetch_set_pending_acquire(lock);

	/*
	 * If we observe contention, there is a concurrent locker.
	 *
	 * Undo and queue; our setting of PENDING might have made the
	 * n,0,0 -> 0,0,0 transition fail and it will now be waiting
	 * on @next to become !NULL.
	 */
	if (unlikely(val & ~_Q_LOCKED_MASK)) {

		/* Undo PENDING if we set it. */
		if (!(val & _Q_PENDING_MASK))
			clear_pending(lock);

		goto queue;
	}

	/*
	 * We're pending, wait for the owner to go away.
	 *
	 * 0,1,1 -> *,1,0
	 *
	 * this wait loop must be a load-acquire such that we match the
	 * store-release that clears the locked bit and create lock
	 * sequentiality; this is because not all
	 * clear_pending_set_locked() implementations imply full
	 * barriers.
	 */
	if (val & _Q_LOCKED_MASK)
		smp_cond_load_acquire(&lock->locked, !VAL);

	/*
	 * take ownership and clear the pending bit.
	 *
	 * 0,1,0 -> 0,0,1
	 */
	clear_pending_set_locked(lock);
//	lockevent_inc(lock_pending);
	return;

	/*
	 * End of pending bit optimistic spinning and beginning of MCS
	 * queuing.
	 */
queue:
//	lockevent_inc(lock_slowpath);
pv_queue:
	node = this_cpu_ptr(&qnodes[0].mcs);
	idx = node->count++;
	tail = encode_tail(smp_processor_id(), idx);

//	trace_contention_begin(lock, LCB_F_SPIN);

	/*
	 * 4 nodes are allocated based on the assumption that there will
	 * not be nested NMIs taking spinlocks. That may not be true in
	 * some architectures even though the chance of needing more than
	 * 4 nodes will still be extremely unlikely. When that happens,
	 * we fall back to spinning on the lock directly without using
	 * any MCS node. This is not the most elegant solution, but is
	 * simple enough.
	 */
	if (unlikely(idx >= MAX_NODES)) {
//		lockevent_inc(lock_no_node);
		while (!queued_spin_trylock(lock))
			cpu_relax();
		goto release;
	}

	node = grab_mcs_node(node, idx);

	/*
	 * Keep counts of non-zero index values:
	 */
//	lockevent_cond_inc(lock_use_node2 + idx - 1, idx);

	/*
	 * Ensure that we increment the head node->count before initialising
	 * the actual node. If the compiler is kind enough to reorder these
	 * stores, then an IRQ could overwrite our assignments.
	 */
	barrier();

	node->locked = 0;
	node->next = NULL;
//	pv_init_node(node);

	/*
	 * We touched a (possibly) cold cacheline in the per-cpu queue node;
	 * attempt the trylock once more in the hope someone let go while we
	 * weren't watching.
	 */
	if (queued_spin_trylock(lock))
		goto release;

	/*
	 * Ensure that the initialisation of @node is complete before we
	 * publish the updated tail via xchg_tail() and potentially link
	 * @node into the waitqueue via WRITE_ONCE(prev->next, node) below.
	 */
	smp_wmb();

	/*
	 * Publish the updated tail.
	 * We have already touched the queueing cacheline; don't bother with
	 * pending stuff.
	 *
	 * p,*,* -> n,*,*
	 */
	old = xchg_tail(lock, tail);
	next = NULL;

	/*
	 * if there was a previous node; link it and wait until reaching the
	 * head of the waitqueue.
	 */
	if (old & _Q_TAIL_MASK) {
		prev = decode_tail(old);

		/* Link @node into the waitqueue. */
		WRITE_ONCE(prev->next, node); 

//		pv_wait_node(node, prev);
		arch_mcs_spin_lock_contended(&node->locked);

		/*
		 * While waiting for the MCS lock, the next pointer may have
		 * been set by another lock waiter. We optimistically load
		 * the next pointer & prefetch the cacheline for writing
		 * to reduce latency in the upcoming MCS unlock operation.
		 */
		next = READ_ONCE(node->next);
		if (next)
			prefetchw(next); //?????
		/* exit the second MCS node, will become to the first node to spin pending_locked bits*/
	}

	/*
	 * we're at the head of the waitqueue, wait for the owner & pending to
	 * go away.
	 *
	 * *,x,y -> *,0,0
	 *
	 * this wait loop must use a load-acquire such that we match the
	 * store-release that clears the locked bit and create lock
	 * sequentiality; this is because the set_locked() function below
	 * does not imply a full barrier.
	 *
	 * The PV pv_wait_head_or_lock function, if active, will acquire
	 * the lock and return a non-zero value. So we have to skip the
	 * atomic_cond_read_acquire() call. As the next PV queue head hasn't
	 * been designated yet, there is no way for the locked value to become
	 * _Q_SLOW_VAL. So both the set_locked() and the
	 * atomic_cmpxchg_relaxed() calls will be safe.
	 *
	 * If PV isn't active, 0 will be returned instead.
	 *
	 */
	// if ((val = pv_wait_head_or_lock(lock, node)))
	// 	goto locked;

	val = atomic_cond_read_acquire(&lock->val, !(VAL & _Q_LOCKED_PENDING_MASK));  //-> *,0,0  --> *,0,1, 
	// val = atomic_cond_read_acquire(&lock->val, !(VAL & _Q_LOCKED_MASK));  //-> *,0,0  --> *,0,1, 

locked:
	/*
	 * claim the lock:
	 *
	 * n,0,0 -> 0,0,1 : lock, uncontended
	 * *,*,0 -> *,*,1 : lock, contended
	 *
	 * If the queue head is the only one in the queue (lock value == tail)
	 * and nobody is pending, clear the tail code and grab the lock.
	 * Otherwise, we only need to grab the lock.
	 */

	/*
	 * In the PV case we might already have _Q_LOCKED_VAL set, because
	 * of lock stealing; therefore we must also allow:
	 *
	 * n,0,1 -> 0,0,1
	 *
	 * Note: at this point: (val & _Q_PENDING_MASK) == 0, because of the
	 *       above wait condition, therefore any concurrent setting of
	 *       PENDING will make the uncontended transition fail.
	 */

/// only one node to acquire the lock, and no pending node there.
	if ((val & _Q_TAIL_MASK) == tail) {
		if (atomic_try_cmpxchg_relaxed(&lock->val, &val, _Q_LOCKED_VAL))
			goto release; /* No contention */
	}

	/*
	 * Either somebody is queued behind us or _Q_PENDING_VAL got set
	 * which will then detect the remaining tail and queue behind us
	 * ensuring we'll see a @next.
	 */
	set_locked(lock);

	/*
	 * contended path; wait for next ,if not observed yet, release.
	 */
	if (!next)
		next = smp_cond_load_relaxed(&node->next, (VAL));

	arch_mcs_spin_unlock_contended(&next->locked);
//	pv_kick_node(lock, next);

release:
//	trace_contention_end(lock, 0);

	/*
	 * release the node
	 */
	__this_cpu_dec(qnodes[0].mcs.count);
}
EXPORT_SYMBOL(my_queued_spin_lock_slowpath);
#endif  //MY_SPINLOCK_SLOWPATH


//define qspinlock
// in asm-generic/qspinlock.h
//
#ifndef my_queued_spin_is_locked
/**
 * my_queued_spin_is_locked - is the spinlock locked?
 * @lock: Pointer to queued spinlock structure
 * Return: 1 if it is locked, 0 otherwise
 */
static __always_inline int my_queued_spin_is_locked(struct qspinlock *lock)
{
	/*
	 * Any !0 state indicates it is locked, even if _Q_LOCKED_VAL
	 * isn't immediately observable.
	 */
	return atomic_read(&lock->val);
}
#endif

/**
 * my_queued_spin_value_unlocked - is the spinlock structure unlocked?
 * @lock: queued spinlock structure
 * Return: 1 if it is unlocked, 0 otherwise
 *
 * N.B. Whenever there are tasks waiting for the lock, it is considered
 *      locked wrt the lockref code to avoid lock stealing by the lockref
 *      code and change things underneath the lock. This also allows some
 *      optimizations to be applied without conflict with lockref.
 */
static __always_inline int my_queued_spin_value_unlocked(struct qspinlock lock)
{
	return !lock.val.counter;
}

/**
 * my_queued_spin_is_contended - check if the lock is contended
 * @lock : Pointer to queued spinlock structure
 * Return: 1 if lock contended, 0 otherwise
 */
static __always_inline int my_queued_spin_is_contended(struct qspinlock *lock)
{
	return atomic_read(&lock->val) & ~_Q_LOCKED_MASK;
}
/**
 * my_queued_spin_trylock - try to acquire the queued spinlock
 * @lock : Pointer to queued spinlock structure
 * Return: 1 if lock acquired, 0 if failed
 */
static __always_inline int my_queued_spin_trylock(struct qspinlock *lock)
{
	int val = atomic_read(&lock->val);

	if (unlikely(val))
		return 0;

	return likely(atomic_try_cmpxchg_acquire(&lock->val, &val, _Q_LOCKED_VAL));
}

extern void queued_spin_lock_slowpath(struct qspinlock *lock, u32 val);
//extern void my_queued_spin_lock_slowpath(struct qspinlock *lock, u32 val);


#ifndef my_queued_spin_lock
/**
 * my_queued_spin_lock - acquire a queued spinlock
 * @lock: Pointer to queued spinlock structure
 */
static __always_inline void my_queued_spin_lock(struct qspinlock *lock)
{
	int val = 0;
#if SPINLOCK_BENCH_DEBUG_ON
    pr_info("spinlock_bench_sysfs: %s\n", __FUNCTION__);
#endif
	if (likely(atomic_try_cmpxchg_acquire(&lock->val, &val, _Q_LOCKED_VAL)))
		return;

#if SPINLOCK_BENCH_DEBUG_ON
    pr_info("Entry to slowpath: %s\n", __FUNCTION__);
#endif

#if MY_SPINLOCK_SLOWPATH
    my_queued_spin_lock_slowpath(lock, val);
#else 
	queued_spin_lock_slowpath(lock, val);
#endif

}
#endif

#ifndef my_queued_spin_unlock

static void cldemote2(volatile void *__p)
{
        asm volatile("cldemote %0" : "+m" (*(volatile char *)__p));
}
/**
 * my_queued_spin_unlock - release a queued spinlock
 * @lock : Pointer to queued spinlock structure
 */
static __always_inline void my_queued_spin_unlock(struct qspinlock *lock)
{
	/*
	 * unlock() needs release semantics:
	 */
	smp_store_release(&lock->locked, 0);
//	cldemote2(&lock->locked);
}
#endif


/*
 * Remapping spinlock architecture specific functions to the corresponding
 * queued spinlock functions.
 */
#define my_arch_spin_is_locked(l)		my_queued_spin_is_locked(l)
#define my_arch_spin_is_contended(l)	my_queued_spin_is_contended(l)
#define my_arch_spin_value_unlocked(l)	my_queued_spin_value_unlocked(l)
#define my_arch_spin_lock(l)		my_queued_spin_lock(l)
#define my_arch_spin_trylock(l)		my_queued_spin_trylock(l)
#define my_arch_spin_unlock(l)		my_queued_spin_unlock(l)


// linux/spinlock.h
static inline void my_do_raw_spin_lock(raw_spinlock_t *lock) __acquires(lock)
{
#if SPINLOCK_BENCH_DEBUG_ON
    pr_info("spinlock_bench_sysfs: %s\n", __FUNCTION__);
#endif
	__acquire(lock);
	my_arch_spin_lock(&lock->raw_lock);
	mmiowb_spin_lock();
}

static inline int my_do_raw_spin_trylock(raw_spinlock_t *lock)
{
	int ret = my_arch_spin_trylock(&(lock)->raw_lock);

	if (ret)
		mmiowb_spin_lock();

	return ret;
}

static inline void my_do_raw_spin_unlock(raw_spinlock_t *lock) __releases(lock)
{
	mmiowb_spin_unlock();
	my_arch_spin_unlock(&lock->raw_lock);
	__release(lock);
}

//linux/spinlock_api_smp.h
/* ------   */

static inline int __my_raw_spin_trylock(raw_spinlock_t *lock)
{
	preempt_disable();
	if (my_do_raw_spin_trylock(lock)) {
		spin_acquire(&lock->dep_map, 0, 1, _RET_IP_);
		return 1;
	}
	preempt_enable();
	return 0;
}

static inline void __my_raw_spin_lock_irq(raw_spinlock_t *lock)
{
#if SPINLOCK_BENCH_DEBUG_ON
    pr_info("spinlock_bench_sysfs: %s\n", __FUNCTION__);
#endif
	local_irq_disable();
	preempt_disable();
	spin_acquire(&lock->dep_map, 0, 0, _RET_IP_);
	LOCK_CONTENDED(lock, my_do_raw_spin_trylock, my_do_raw_spin_lock);
}

static inline void __my_raw_spin_lock(raw_spinlock_t *lock)
{
	preempt_disable();
	spin_acquire(&lock->dep_map, 0, 0, _RET_IP_);
	LOCK_CONTENDED(lock, my_do_raw_spin_trylock, my_do_raw_spin_lock);
}

static inline void __my_raw_spin_unlock(raw_spinlock_t *lock)
{
	spin_release(&lock->dep_map, _RET_IP_);
	my_do_raw_spin_unlock(lock);
	preempt_enable();
}

static inline void __my_raw_spin_unlock_irq(raw_spinlock_t *lock)
{
	spin_release(&lock->dep_map, _RET_IP_);
	my_do_raw_spin_unlock(lock);
	local_irq_enable();
	preempt_enable();
}


// locking/spinlock.c
//#ifndef CONFIG_INLINE_SPIN_TRYLOCK
noinline int __lockfunc _my_raw_spin_trylock(raw_spinlock_t *lock)
{
	return __my_raw_spin_trylock(lock);
}
EXPORT_SYMBOL(_my_raw_spin_trylock);
//#endif


//#ifndef CONFIG_INLINE_SPIN_LOCK
noinline void __lockfunc _my_raw_spin_lock(raw_spinlock_t *lock)
{
	__my_raw_spin_lock(lock);
}
EXPORT_SYMBOL(_my_raw_spin_lock);
//#endif


//#ifndef CONFIG_INLINE_SPIN_LOCK_IRQ
noinline void __lockfunc _my_raw_spin_lock_irq(raw_spinlock_t *lock)
{
	__my_raw_spin_lock_irq(lock);
}
EXPORT_SYMBOL(_my_raw_spin_lock_irq);
//#endif


//#ifdef CONFIG_UNINLINE_SPIN_UNLOCK
noinline void __lockfunc _my_raw_spin_unlock(raw_spinlock_t *lock)
{
	__my_raw_spin_unlock(lock);
}
EXPORT_SYMBOL(_my_raw_spin_unlock);
//#endif

//#ifndef CONFIG_INLINE_SPIN_UNLOCK_IRQ
noinline void __lockfunc _my_raw_spin_unlock_irq(raw_spinlock_t *lock)
{
	__my_raw_spin_unlock_irq(lock);
}
EXPORT_SYMBOL(_my_raw_spin_unlock_irq);
//#endif

#define my_raw_spin_trylock(lock)	__cond_lock(lock, _my_raw_spin_trylock(lock))

#define my_raw_spin_lock(lock)          _my_raw_spin_lock(lock)
#define my_raw_spin_unlock(lock)		_my_raw_spin_unlock(lock)

#define my_raw_spin_lock_irq(lock)		_my_raw_spin_lock_irq(lock)
#define my_raw_spin_unlock_irq(lock)	_my_raw_spin_unlock_irq(lock)

//////////////////////////////////////////////////////////////////////
//  end of spinlock functions
//////////////////////////////////////////////////////////////////////


/*------------------------------------*/

#if ATOMIC_OPS
static inline long long read64_atomic_value(atomic64_t *v)
{
    return atomic64_read(v);
}

static inline void write64_atomic_value(atomic64_t *v, long long new_value)
{
    atomic64_set(v, new_value);
}

static inline void inc64_atomic_value(atomic64_t *v)
{
    atomic64_inc(v);
}

#else //ATOMIC_OPS
// original read write..
static inline long long read64_atomic_value(long long *v)
{
    return *v;
}

static inline void inc64_atomic_value(long long  *v)
{
    (*v)++;
}

static inline void write64_atomic_value(long long  *v, long long new_value)
{
    (*v) = new_value;
}
#endif //ATOMIC_OPS

static inline void my_spin_lock(spinlock_t *lock)
{
#if USE_SPINLOCK_IRQ
    //spinlock irq
    #if USE_RAW_SPINLOCK_IRQ
        #if USE_MY_RAW_SPINLOCK_IRQ
            my_raw_spin_lock_irq(&lock->rlock);
        #else 
            raw_spin_lock_irq(&lock->rlock);
        #endif
    #else 
        spin_lock_irq(lock);
    #endif

#else  
    spin_lock(lock);
#endif

}

static inline void my_spin_unlock(spinlock_t *lock)
{
#if USE_SPINLOCK_IRQ
    //spinlock irq
    #if USE_RAW_SPINLOCK_IRQ

        #if USE_MY_RAW_SPINLOCK_IRQ
            my_raw_spin_unlock_irq(&lock->rlock);
        #else 
            raw_spin_unlock_irq(&lock->rlock);
        #endif

    #else 
        spin_unlock_irq(lock);
    #endif

#else 
    spin_unlock(lock);
#endif

}

// re-try acquire the spinlock til get the onwership of the lock.
static inline int my_retry_spin_lock(spinlock_t *spinlock)
{
    raw_spinlock_t *rlock = &spinlock->rlock;
    arch_spinlock_t *lock = &rlock->raw_lock;

#if USE_SPINLOCK_IRQ
	local_irq_disable();
#endif
	preempt_disable();

    int tries = 0;
    do {
        tries++;
        while (atomic_read(&lock->val) != 0) {
//        while (lock->val->counter != 0) {            
            tries++;
            cpu_relax();
        }
    } while (atomic_cmpxchg(&lock->val, 0, _Q_LOCKED_VAL) != 0);
//	 while ( likely(atomic_try_cmpxchg_acquire(&lock->val, &val, _Q_LOCKED_VAL)) );
    return tries;
}


static inline void my_retry_unlock(spinlock_t *lock)
{
#if USE_SPINLOCK_IRQ

        #if USE_MY_RAW_SPINLOCK_IRQ
            my_raw_spin_unlock_irq(&lock->rlock);
        #else 
            raw_spin_unlock_irq(&lock->rlock);
        #endif

#else 
    spin_unlock(lock);
#endif
}

static void my_pthread_init_lock(my_pthread_spinlock_t *pthread_spinlock)
{
    atomic64_set((atomic64_t *) &(pthread_spinlock->value), 1);
}

/**
 * my_pthread_spin_lock - Spin lock acquisition function implemented with inline assembly
 * @lock: Pointer to the spin lock (0 = locked, 1 = unlocked)
 */
static inline void my_pthread_spin_lock(my_pthread_spinlock_t *pthread_spinlock)
{
    unsigned int eax;
    atomic64_t *plock = &(pthread_spinlock->value);

    asm volatile (
        "1:                         \n"
        "xor    %%eax, %%eax        \n"  /* Clear EAX register to indicate lock acquisition attempt */
        "lock; decl (%0)            \n"  /* Atomically decrement the lock value */
        "jne    2f                  \n"  /* If the result is non-zero, the lock is held by another CPU */
        "jmp    3f                  \n"  /* Successfully acquired the lock, return */

        ".align 16                  \n"  /* Code alignment to improve branch prediction efficiency */
        "2:                         \n"
        "rep; nop                   \n"  /* Equivalent to PAUSE instruction, reduces memory contention */
        "cmpl   %%eax, (%0)         \n"  /* Check if the lock has been released (value is 0) */
        "jle    2b                  \n"  /* If the lock is still held, continue spinning */
        "lock; decl (%0)            \n"  /* Atomically decrement the lock value */
        "jne    2b                  \n"  /* If the result is non-zero, the lock is held by another CPU */
        "3:                         \n"
        :
        : "r" (&plock->counter)      /* Input operand: address of the lock */
        : "memory", "cc", "%eax"    /* Clobber list: resources modified by the assembly code */
    );
}

/**
 * my_pthread_spin_unlock - Spin lock release function implemented with inline assembly
 * @lock: Pointer to the spin lock (0 = locked, 1 = unlocked)
 */
static inline void my_pthread_spin_unlock(my_pthread_spinlock_t *pthread_spinlock)
{
    atomic64_t *plock = &(pthread_spinlock->value);
    asm volatile (
        "movl   $1, (%0)            \n"         /* Set the lock value to 1 (unlocked state) */
        :
        : "r" (&plock->counter)                 /* Input operand: address of the lock */
        : "memory"                              /* Clobbered resources: memory */
    );
}    
// same as atomic64_set(pthread_spinlock, 1);
// use mfence after set lock value if it's non-x86
// "mfence                     \n"  /* Ensure all previous writes are visible to other CPUs */

static inline void my_mutex_lock(struct mutex * mlock)
{
    mutex_lock(mlock);
}

static inline void my_mutex_unlock(struct mutex * mlock)
{
    mutex_unlock(mlock);
}

//////////////////////////////////////////////////////////////////////
//  threads functions
//////////////////////////////////////////////////////////////////////
#define TSCRD1	"lfence; rdtsc;"
#define TSCRD10 TSCRD1 TSCRD1 TSCRD1 TSCRD1 TSCRD1 TSCRD1 TSCRD1 TSCRD1 TSCRD1 TSCRD1 
#define TSCRD100 TSCRD10 TSCRD10 TSCRD10 TSCRD10 TSCRD10 TSCRD10 TSCRD10 TSCRD10 TSCRD10 TSCRD10 

#define THE_TSC rdtsc()

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
    int oh=0xffffff, result=0, i = 0;
    for (i=0; i < 4; i++) {
        result = rdtsc_latency();
        //printk("Overhead%d\t%d\n", i, result);
        if (result < oh) oh = result;
    }
    //printk("overhead = %d\n", oh);
    return oh;
    
}

static inline void busy_loop_delay(int64_t hold_count)
{
    int64_t begin, end;
  
    if (hold_count == 0) 
        return;

    begin = THE_TSC;
 
    while(1) {
        end = THE_TSC;
        asm ("lfence"::);
        barrier();
        if ((end - begin) >= (int64_t) hold_count - 2 * g_rdtsc_overhead)
            break;
    }
 
}
#ifndef CONFIG_X86_TSC
void get_tsc_frequency( uint64_t * tsc_frequency) {

    // Read the TSC frequency
    uint64_t tsc_start = THE_TSC;
    msleep(500); // Wait for 500 msecond
    uint64_t tsc_end = THE_TSC;
    uint64_t tsc = (tsc_end - tsc_start);
    
    *tsc_frequency = tsc/500000;  // per us,
    //printk("TSC duration %llu\n", tsc);

    //printk("TSC Frequency: %llu MHz\n", *tsc_frequency);
}
#endif


static void lock_reinit_with_address(int lock_mode, uint64_t lock_addr)
{
    if (lock_mode == MUTEX_LOCK) {
        bench_mutex_ptr = (struct mutex *)lock_addr;
        mutex_init(bench_mutex_ptr);
    } if (lock_mode == PTHREAD_LOCK) {
        my_plock_ptr = (struct my_pthread_spinlock *)lock_addr;
        my_pthread_init_lock(my_plock_ptr);
    } else {
        bench_spinlock_ptr = (spinlock_t * )lock_addr;
        spin_lock_init(bench_spinlock_ptr);
    }
}

static void lock_init_by_mode(int lock_mode)
{
    if (lock_mode == MUTEX_LOCK) {
        mutex_init(&mutex_bench_lock);
        bench_mutex_ptr = (struct mutex *)&mutex_bench_lock;
        // get the spinlock virtual and physical address.
        g_lock_virt_addr = (uint64_t)&mutex_bench_lock;
    } else if (lock_mode == PTHREAD_LOCK) {
        my_pthread_init_lock( &my_pthread_lock);
        my_plock_ptr = (struct my_pthread_spinlock *) &my_pthread_lock;
        g_lock_virt_addr = (uint64_t) &my_pthread_lock;
    } else {
        // to use the static address for spinlock.
        spin_lock_init(&spinlock_bench_spinlock);
        bench_spinlock_ptr = (spinlock_t *)&spinlock_bench_spinlock;
        // get the spinlock virtual and physical address.
        g_lock_virt_addr = (uint64_t)&spinlock_bench_spinlock;
    }

    g_lock_phys_addr = kvirt_to_phys((void *)g_lock_virt_addr);

}

/*
 * Convert kernel *virtual* addresses to physical addresses.
 * This is used to vmalloc'ed addresses.
 */
static uint64_t kvirt_to_phys(void *virt_addr)
{
    uint64_t pfn, offset = (uint64_t) virt_addr & ((1UL << PAGE_SHIFT) - 1) ;

#if 0
    //TODO: might don't need check vmalloc'ed ? this judgement is wrong?
    if (is_vmalloc_addr((void *)virt_addr)) {
        pr_info("virt_addr 0x%lx is vmalloc address \n", virt_addr);
        pfn = vmalloc_to_pfn((void *)virt_addr); 
    } else {
        pr_info("virt_addr 0x%lx is not vmallc address \n", virt_addr);
        pfn = page_to_pfn(virt_to_page((void *)virt_addr));
    }

    return (pfn << PAGE_SHIFT) + offset;
#else 
	u64 paddr = 0;
	struct page * addr_page = vmalloc_to_page(virt_addr);
	if (addr_page)
		paddr = page_to_pfn(addr_page) << PAGE_SHIFT;

	return paddr + offset;
#endif
}

#if SPINLOCK_NOT_USE_STATIC_MEM
inline unsigned long my_allocate_free_page(unsigned int node_id, unsigned int page_order)
{
    unsigned long virt_addr = 0;
    // virt_addr = __get_free_pages(GFP_KERNEL, page_order);

    struct page *page;
    page = alloc_pages_node(node_id, GFP_KERNEL, page_order);
   	if (!page)
		return 0;
    virt_addr = (unsigned long) page_address(page);

    return virt_addr;
}


static int lock_address_remap(void)
{
    g_lock_phys_addr = lock_base_phys_addr + offset4selected_cha;
    g_lock_virt_addr = (uint64_t)__va(g_lock_phys_addr);

    pr_info("Selected Address: Virt: 0x%llx, Phy: 0x%llx\n", g_lock_virt_addr, g_lock_phys_addr);

    lock_reinit_with_address(g_lock_mode, g_lock_virt_addr);

    return 0;
}

static int lock_address_allocation(void)
{
    int page_order = g_mem_page_order;
    //g_lock_virt_addr = __get_free_pages(GFP_KERNEL, page_order);
    g_lock_virt_addr = my_allocate_free_page(g_numa_node_id, page_order);
    if (! g_lock_virt_addr) {
        pr_warn("SpinLock_bench: Can't allocate %d free pages \n", 1<<page_order);
        return -ENOMEM;
    } else {
        pr_info("SpinLock_bench: Allocate %d free pages, at address: 0x%llx \n", 1<<page_order, g_lock_virt_addr);
    }
    lock_base_virt_addr = g_lock_virt_addr;
    lock_base_phys_addr  = __pa(lock_base_virt_addr);
    g_lock_phys_addr = lock_base_phys_addr + offset4selected_cha;
    g_lock_virt_addr = (uint64_t)__va(g_lock_phys_addr);

    pr_info("SpinLock allocated Base Virtual address: 0x%llx\n", lock_base_virt_addr);
    pr_info("SpinLock allocated Base Physical address: 0x%llx\n", lock_base_phys_addr);

    pr_info("Selected Address: Virt: 0x%llx, Phy: 0x%llx\n", g_lock_virt_addr, g_lock_phys_addr);

    // before start thread, set the real address for spinlock.
    g_lock_phys_addr = lock_base_phys_addr + offset4selected_cha;
    g_lock_virt_addr = (uint64_t)__va(g_lock_phys_addr);

    pr_info("Set SpinLock Physical address: 0x%llx\n", g_lock_phys_addr);
    pr_info("Set SpinLock Virtual address: 0x%llx\n", g_lock_virt_addr);

    lock_reinit_with_address(g_lock_mode, g_lock_virt_addr);

    return 0;
}

#endif

static inline int test_should_stop(void )
{
    return (!(test_on) & 0x01);
}

// hold on duration by nano seconds.
static inline void critical_section_holdon_duration(long long hold_duration)
{
    long long duration = hold_duration;  //ns

    busy_loop_delay(hold_duration);
#if LAZY_LOCK_WORK
            ndelay(1);

#endif

}


#if SIMPLE_THREAD 
// simple thread, just 2 threads for sanity check.

static int threads_on_spinlock(void)
{
    return 0;
}

// Function to start threads
static int start_threads_function(void)
{
    int thread_count = thread_num;
    int num_cpus = num_online_cpus(); // Get the number of online CPUs


    if (thread_count <= 0) {
        pr_err("spinlock_bench_sysfs: thread_count is not set or is invalid\n");
        return -EINVAL;
    }

    stop_threads = false;

    threads_should_stop = false;
    pr_info("Start to run thread...");
    // Start the worker threads
    thread1 = kthread_create(thread_fn1, NULL, "spinlock_bench_thread1");
    if (IS_ERR(thread1)) {
        pr_err("spinlock_bench_sysfs: failed to create thread1\n");
        return PTR_ERR(thread1);
    }

    // Pin the thread to a specific CPU in round-robin fashion
    kthread_bind(thread1, 1 % num_cpus);

    // Start the thread
    wake_up_process(thread1);

    thread2 = kthread_create(thread_fn2, NULL, "spinlock_bench_thread2");
    if (IS_ERR(thread2)) {
        pr_err("spinlock_bench_sysfs: failed to create thread2\n");
        if (thread1)
            kthread_stop(thread1);
        return PTR_ERR(thread2);
    }

    // Pin the thread to a specific CPU in round-robin fashion
    kthread_bind(thread2, 2 % num_cpus);

    // Start the thread
    wake_up_process(thread2);


    pr_info("spinlock_bench_sysfs: threads started (thread_count = %d)\n", thread_count);
    return 0;
}

// Function to stop threads
static void stop_threads_function(void)
{
    threads_should_stop = true;

    // Stop the worker threads
    if (thread1)
        kthread_stop(thread1);
    if (thread2)
        kthread_stop(thread2);

    pr_info("spinlock_bench_sysfs: threads stopped\n");
    stop_threads = false;
}

// Thread function to increment the counter
static int thread_fn1(void *data)
{
    long long current_value = 0;
    while (!kthread_should_stop()) {
        my_spin_lock(&spinlock_bench_spinlock);
        // shared_value++;
        // current_value = shared_value;
        inc64_atomic_value(&(my_shared_data.shared_value));
        current_value = read64_atomic_value(&(my_shared_data.shared_value));
        my_spin_unlock(&spinlock_bench_spinlock);

        pr_info("Thread 1: shared value incremented to %d\n", current_value);
        msleep(1); // Simulate some work
    }

    pr_info("Thread 1 loop exit...");
    return 0;
}

// Thread function to toggle the test_on flag
static int thread_fn2(void *data)
{
    long long current_value = 0;
    while (!kthread_should_stop()) {
        my_spin_lock(&spinlock_bench_spinlock);
        // shared_value++;
        // current_value = shared_value;
        inc64_atomic_value(&(my_shared_data.shared_value));
        current_value = read64_atomic_value(&(my_shared_data.shared_value));

        my_spin_unlock(&spinlock_bench_spinlock);

        pr_info("Thread 2: shared value incremented to %d\n", current_value);
        msleep(1); // Simulate some work
    }

    pr_info("Thread 2 loop exit...");

    return 0;
}

#else 
// Function to start threads
// create the threads, and waitup the threads. 
static int start_threads_function(void)
{
    int i, thread_count = thread_num;
    int num_cpus = num_online_cpus(); // Get the number of online CPUs
    uint16_t cpu_list[MAX_CORES] = {0};

    if (thread_count <= 0) {
        pr_err("spinlock_bench_sysfs: thread_count is not set or is invalid\n");
        return -EINVAL;
    }

    stop_threads = false;
    // Allocate array for thread pointers
    threads = kcalloc(thread_count, sizeof(struct task_struct *), GFP_KERNEL);
    if (!threads)
        return -ENOMEM;

	 // Allocate threads data variables.
	if ( (threads_data = (struct thread_private_data *) kzalloc(thread_count * sizeof (*threads_data), GFP_KERNEL | __GFP_ZERO) ) == NULL ) {
		pr_err("malloc threads_data failed\n");

        if (threads) {
            kfree(threads);
            threads = NULL;
        }
        return -EINVAL;
	}

    threads_should_stop = false;

    //Get the cpulist from cpumask:
    int cpu, cpu_count, idx = 0;
    for_each_cpu(cpu, &cpuaffinity_mask) {
        cpu_list[idx++] = cpu;
    }
    cpu_count = idx;

    for (i = 0; i < thread_count; i++) {
        // Dynamically allocate memory for the thread ID parameter
        // will free this memory in each thread.
        int *thread_id = kmalloc(sizeof(int), GFP_KERNEL);
        if (!thread_id) {
            pr_err("spinlock_bench_sysfs: failed to allocate memory for thread ID\n");
            return -ENOMEM;
        }
        *thread_id = i;
        threads_data[i].thread_id = i;
        threads_data[i].cpu_id = i;  //just initial here, update later for cpu affinity.
        threads_data[i].state = THREAD_STOPPED;
        threads_data[i].thread_private_counter = 0;
        threads_data[i].attempt_count = 0;
        threads_data[i].acquired_count = 0;
        threads_data[i].test_on = false;

        // Create the thread
        threads[i] = kthread_create(thread_fn_common, thread_id, "spinlock_bench_thread_%d", i);
        //threads[i] = kthread_run(thread_fn_common, thread_id, "spinlock_bench_thread_%d", i);
/*  
 *  use the cpu count to sequentially mapping cpu core.
 */
#if 0
        // Pin the thread to a specific CPU in round-robin fashion
        int cpu_id;
        if (nr_cpu <= num_cpus) {
            cpu_id = i % nr_cpu ;
        } else {
            cpu_id = i % num_cpus;
        }
        kthread_bind(threads[i], cpu_id);
        threads_data[i].cpu_id = cpu_id;
#else

        // Bind thread to a CPU based on the CPU affinity mask
        // int cpu_id = cpumask_next(i - 1, &cpuaffinity_mask);
        int cpu_id = cpu_list[i % cpu_count];
        if (cpu_id >= num_cpus || cpu_id < 0) {
            pr_warn("spinlock_bench_sysfs: No available CPU in affinity mask for thread %d\n", i);
            cpu_id = i % num_cpus; // Fallback to round-robin assignment
        }
        kthread_bind(threads[i], cpu_id);
        threads_data[i].cpu_id = cpu_id;
#endif
        pr_info("spinlock_bench_sysfs: Bind thread [%d] on CPU core %d\n", i, cpu_id);

        // Start the thread
        wake_up_process(threads[i]);
        threads_data[i].state = THREAD_STARTED;

        if (IS_ERR(threads[i])) {
            pr_err("spinlock_bench_sysfs: failed to create thread %d\n", i);
            kfree(thread_id); // Free memory if thread creation fails
            threads[i] = NULL;
        }
    }

    pr_info("spinlock_bench_sysfs: threads started (thread_count = %d)\n", thread_count);
    return 0;
}

// Function to stop threads
static void stop_threads_function(void)
{
    int i, thread_count = thread_num;

    threads_should_stop = true;
    if (threads) {
        for (i = 0; i < thread_count; i++) {
            if (threads[i]) {
                kthread_stop(threads[i]);
                threads[i] = NULL;
            }
        }
        kfree(threads);
        threads = NULL;
    }

    if (threads_data) {
        kfree(threads_data);
        threads_data = NULL;
    }

    pr_info("spinlock_bench_sysfs: [%d] threads stopped\n", thread_count);
    stop_threads = false; 

    // if(lock_base_virt_addr) {
    //     free_pages(lock_base_virt_addr, g_mem_page_order);
    //      lock_base_virt_addr = 0;
    //      lock_base_phys_addr = 0;
    //     printk("spinlock_bench: free_pages ok! \n");
    // }

}

#endif // #if SIMPLE_THREAD


// Simulate CPU resource consumption
void computering_work(int thread_id) 
{
    int cpu_work = 0;
    unsigned long i;
    for (i = 0; i < 100000; i++) { // Run a computational loop
        cpu_work += i % 10; // Perform some meaningless calculations
    }
    pr_debug("Thread %d CPU work result: %d\n", thread_id, cpu_work);
}

void  computering_work_2(int counter) 
{
    int cpu_work = 0;
    unsigned long i;
    for (i = 0; i < counter; i++) { // Run a computational loop
        cpu_work += i % 10; // Perform some meaningless calculations
    }
    pr_debug("Thread CPU work result: %d\n",  cpu_work);
}

// other works besides of the critial section.
inline void other_works_duration_us(int t_pause, int t_usleep)
{

    if (t_pause != 0) {
        udelay( t_pause  ); // Simulate work, similar with while loop. not sleep.
    }
    if ( t_usleep != 0) {
        usleep_range(t_usleep, t_usleep );    //sleep at least 5us.
    }
    // if both 0, then return directly.

#if LAZY_LOCK_WORK
    //computering_work(thread_id);
    udelay( SIM_TIME ); // Simulate work
    //msleep( SIM_TIME ); // Simulate work
    fsleep(10);
#endif
}

inline uint64_t current_tsc(void)
{
#if MY_LOCK_LATENCY
    return rdtsc();
#endif
}

#if SIMULATE_XFS_PWQS_FLUSH

inline int sim_flush_work_pwqs(int times)
{
    long long current_value = 0;
    bool do_nothing = 0;
    int cc = 0;  // internal counter

    while (times--) {

        if (!do_nothing) {

            my_spin_lock(bench_spinlock_ptr);

            if (current_value >= MAX_VALUE){
                threads_should_stop = true;
                do_nothing = 1;
            }else {
                // shared_value++;
                // current_value = shared_value;
                inc64_atomic_value(&(my_shared_data.shared_value));
                current_value = read64_atomic_value(&(my_shared_data.shared_value));
                cc++;
            }
            my_spin_unlock(bench_spinlock_ptr);

#if SPINLOCK_BENCH_DEBUG_ON
            udelay( SIM_TIME ); // Simulate work
            computering_work_2(1000);

            pr_info("Thread %d on CPU %d: counter incremented to %d\n",
                    thread_id, smp_processor_id(), current_value);
#endif

        } else {
            msleep(100); // Simulate work
        }
    }

    return 0;

}

EXPORT_SYMBOL(sim_flush_work_pwqs);

inline int sim_flush_work_pwqs(int times);

// Thread function to increment the counter
static int thread_fn_common(void *data)
{
    long long current_value = 0;
    int thread_id = *(int *)data;
    bool do_nothing = 0;
    int cc, work = 0;
    int num_pwq = num_online_cpus() + 1 ; // Get the number of online CPUs + default one.


    kfree(data); // Free the allocated memory for the thread ID

    while (!kthread_should_stop()) {

        if (current_value >= MAX_VALUE){
            threads_should_stop = true;
            pr_debug("Thread %d on CPU %d: counter incremented to %d, exceed the max value [%llu]\n",
                thread_id, smp_processor_id(), current_value, MAX_VALUE);
            msleep(500);
            do_nothing = 1;
        }
//        current_value = shared_value;
        current_value = read64_atomic_value(&(my_shared_data.shared_value));

        if (test_on && !do_nothing) {
            //simulate the xfs workqueue pwqs flush function.
            //actual work with spinlock
            work = sim_flush_work_pwqs(num_pwq);

            if ( !(++cc % 50000)) {
                pr_info("spinlock_bench_sysfs: value is %llu\n", current_value);
                cc = 0;
            }
            //for EMR8952+ 3.9GHz, 
            //  240000 round computing used to simulate the fio xfs work. 15% - native_queued_spin_lock_slowpath
            computering_work_2(240000);// 

            //computering_work(thread_id);
#if LAZY_LOCK_WORK
            computering_work(thread_id);
            udelay( SIM_TIME ); // Simulate work
            //msleep( SIM_TIME ); // Simulate work
            fsleep(10);
#endif

#if SPINLOCK_BENCH_DEBUG_ON
            pr_info("Thread %d on CPU %d: counter incremented to %d\n",
                    thread_id, smp_processor_id(), current_value);
#endif

        } else {
            msleep(100); // Simulate work
        }

    }

    pr_info("Thread %d loop exit...", thread_id);
    return 0;
}

#else //SIMULATE_XFS_PWQS_FLUSH

// Thread function to increment the shared data.
static int thread_fn_common(void *data)
{
    long long current_value = 0;
    uint64_t attempt_count=0, acquired_count=0, retries;  //miss_count=0, miss_tmp_count=0
    uint64_t acq_duration = 0, t0, t1, t2, t3, t4;  //
    uint64_t holdon_time = g_holdon_time_cycles, other_works_wait_cycles = g_other_works_wait_time_cycles;
    int other_works_pause_us = g_other_works_pause_us, other_works_sleep_us = g_other_works_sleep_us;
    int thread_id = *(int *)data;
    bool do_nothing = 0, print_trace = g_trace_print, timer_on = 0;
    int lock_mode = g_lock_mode;
    int wait_counter = 0, batch_counter = 0, online_cpus = num_online_cpus();

    volatile struct thread_private_data *local_thread = (struct thread_private_data *)&threads_data[thread_id];
    local_thread->state = THREAD_RUNNING;

    kfree(data); // Free the allocated memory for the thread ID

#if MY_LOCK_TRACE
  	trace_my_lock_begin(bench_spinlock_ptr, 1);
#endif

    while (!kthread_should_stop()) {


        while (local_thread->test_on && !do_nothing) {
            if (timer_on == 0) {
                timer_on = 1;
                t0 = current_tsc(); // start time.
            }

            if (lock_mode == QUEUE_LOCK) {
                (local_thread->attempt_count)++;
                attempt_count++;

                //t1 = current_tsc();
                my_spin_lock(bench_spinlock_ptr);
                //t2 = current_tsc();
            } else if (lock_mode == RETRY_LOCK) {
                //t1 = current_tsc();
                retries = my_retry_spin_lock(bench_spinlock_ptr);
                //t2 = current_tsc();

                local_thread->attempt_count += retries; 
                attempt_count += retries;
            } else if (lock_mode == MUTEX_LOCK) {
                (local_thread->attempt_count)++;
                attempt_count++;

                //t1 = current_tsc();
                my_mutex_lock(bench_mutex_ptr);
                //t2 = current_tsc();
            } else if (lock_mode == PTHREAD_LOCK) {
                my_pthread_spin_lock( my_plock_ptr);
            }
//---------entry critical section ----------

            // acquired_count++;
            //local_thread->acquired_count++;

            //-- avoid cacheline pingpong. 
            //inc64_atomic_value(&(my_shared_data.shared_value));
            //current_value = read64_atomic_value(&(my_shared_data.shared_value));
            critical_section_holdon_duration(holdon_time);
            current_value++;

//---------exit critical section ----------
            if (lock_mode == QUEUE_LOCK) {
                my_spin_unlock(bench_spinlock_ptr);
            } else if (lock_mode == RETRY_LOCK) {
                my_retry_unlock(bench_spinlock_ptr);
            } else if (lock_mode == MUTEX_LOCK) {
                my_mutex_unlock(bench_mutex_ptr);
            } else if (lock_mode == PTHREAD_LOCK) {
                my_pthread_spin_unlock( my_plock_ptr);
            }
       	    //local_thread->attempt_count += attempt_count;
    		//local_thread->acquired_count == acquired_count;
#if MY_LOCK_LATENCY
    //         t3 = t2 - t1;
    //         acq_duration += t3;
    //         if (print_trace)
    //             trace_printk("thread#: %d ; lat: %llu \n ", thread_id, t3);
    // #if MY_LOCK_TRACE
    //         trace_my_lock_end_3(bench_spinlock_ptr, 0, t1, t2, t3);
    // #endif
#endif

            //If enable batch(align with online cpu core) lock benchmark 
            if (g_batch_lock && (batch_counter++ < online_cpus) ) {
                continue;
            }

            if (g_batch_lock) {
                batch_counter = 0;
                wait_counter++;
            }

            //Other works outside of the critial section.
            other_works_duration_us(other_works_pause_us, other_works_sleep_us);
            // other waiting with while...
            busy_loop_delay(other_works_wait_cycles);

            if (current_value >= MAX_VALUE){
                threads_should_stop = true;
                pr_info("Thread %d on CPU %d: counter incremented to %llu, exceed the max value [%u]\n",
                    thread_id, smp_processor_id(), current_value, MAX_VALUE);
                msleep(5000);
                do_nothing = 1;
            }

#if SPINLOCK_BENCH_DEBUG_ON
            pr_info("Thread %d on CPU %d: counter incremented to %d\n",
                    thread_id, smp_processor_id(), current_value);
#endif

        }

        if (timer_on) {
            t4 = current_tsc(); //end of time.
            local_thread->acquired_count = current_value;
            // update the total acquring latency for each thread.
            //local_thread->acquiring_time = acq_duration;

            if (g_batch_lock)
                local_thread->acquiring_time = t4 - t0 \
                    - g_tsc_freq_mhz_per_us * (other_works_pause_us + other_works_sleep_us) * (wait_counter) \
                    - (other_works_wait_cycles) * wait_counter - (holdon_time) * (local_thread->acquired_count) ;
            else 
                local_thread->acquiring_time = t4 - t0 \
                    - g_tsc_freq_mhz_per_us * (other_works_pause_us + other_works_sleep_us) * (local_thread->acquired_count) \
                    - (other_works_wait_cycles + holdon_time) * (local_thread->acquired_count) ;

            timer_on = 0;
        }

        {
            //udelay( 10000 ); // Simulate work
            //msleep(10); // Simulate work
            //msleep(100); // Simulate work
            // set_current_state(TASK_INTERRUPTIBLE); // 
            // schedule_timeout(msecs_to_jiffies(50)); // 
            usleep_range(50,50);    //sleep at least 50us.

        }

    }

    local_thread->state = THREAD_STOPPED;
    pr_info("Thread %d loop exit...", thread_id);
    return 0;
}

#endif // SIMULATE_XFS_PWQS_FLUSH

//////////////////////////////////////////////////////////////////////
//  end of thread functions
//////////////////////////////////////////////////////////////////////

char * lock_mode_str(int mode)
{
//    int batch = mode >> 7; 

    switch (mode) {
        case QUEUE_LOCK:
            return "Queued_spinlock";
            break;
        case RETRY_LOCK:
            return "Retry_spinlock";
            break;
        case TICKET_LOCK:
            return "Ticket_spinlock";
            break;
        case MUTEX_LOCK:
            return "mutex_lock";
            break;
        case PTHREAD_LOCK:
            return "pthread_spinlock";
            break;
        case LAST_LOCK:
        default:
            return "NONE";
            break;
    }
    return "NONE";

}


//////////////////////////////////////////////////////////////////////
//  sysfs node functions
//////////////////////////////////////////////////////////////////////

#include <linux/sort.h>

// compare values.
static int value_cmp(const void *a, const void *b)
{
    return (*(int *)a - *(int *)b);
}

/**
 * calculate_median - 
 * @array: 
 * @n: counter of the data serial.
 * 
 * return: the median value.
 */
int thread_latency_calculate_median(struct thread_private_data * data_array, size_t n)
{
    int i = 0;
    int *sorted;
    int  median;
    
    if (n == 0)
        return 0;
    
    sorted = kmalloc(n * sizeof(int), GFP_KERNEL);
    if (!sorted)
        return 0;
    
    for (i = 0 ; i < n ; i++) {
        if (data_array[i].acquired_count)
            sorted[i] = data_array[i].acquiring_time/data_array[i].acquired_count;
        else 
            sorted[i] = data_array[i].acquiring_time;
    }
    
    //sort the array.
    sort(sorted, n, sizeof(int), value_cmp, NULL);
    
    // get the median
    if (n % 2 == 0)
        median = (sorted[n/2 - 1] + sorted[n/2]) / 2;
    else
        median = sorted[n/2];
    
    kfree(sorted);
    return median;
}


// Sysfs show and store functions for `spinlock_bench_value`
static ssize_t value_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{

    uint64_t lock_count = read64_atomic_value(&spinlock_bench_value);
    uint64_t total_acquired = 0, bench_duration_ns = g_test_duration_ns, all_bench_duration_ns = 0, all_lantecy_clk = 0;
    uint64_t thread_throughput_per_sec = 0, total_throughput_per_sec = 0;
    int i;
    ssize_t len = 0;
//    return sprintf(buf, "%llu\n", lock_count );

    if (!threads_data) {
        return sprintf(buf, "No thread data available\n");
    }

    // len += scnprintf(buf + len, PAGE_SIZE - len,
    //                 "thread#\t cpu#\t private_counter/sec\t lock-attempts/sec\t lock-acquired/sec\tavg-latency(clk)\n");

    len += scnprintf(buf + len, PAGE_SIZE - len,
                    "thread#\t cpu#\tlock-attempts\tlock-acquired\ttotal-acq-lat(TSC)\tavg-acq-lat(TSC)\tlock-acq/sec\n");
    for (i = 0; i < thread_num; i++) {
        unsigned long avg_lat_per_thread = 0;
        total_acquired += threads_data[i].acquired_count;
        // bench_duration_ns = g_test_duration_ns - threads_data[i].acquired_count * (g_other_works_pause_us + g_other_works_sleep_us) * 1000 \
        //                     - (g_other_works_wait_time_cycles + g_holdon_time_cycles) * threads_data[i].acquired_count * 1000 / g_tsc_freq_mhz_per_us;
        bench_duration_ns = g_test_duration_ns;
        all_bench_duration_ns += bench_duration_ns;
        //all_lantecy_clk += threads_data[i].acquiring_time;
        thread_throughput_per_sec = threads_data[i].acquired_count *1000*1000*1000 / bench_duration_ns;
        total_throughput_per_sec += thread_throughput_per_sec;
        if (threads_data[i].acquired_count)
            avg_lat_per_thread = threads_data[i].acquiring_time/threads_data[i].acquired_count;

        all_lantecy_clk += avg_lat_per_thread;
        len += scnprintf(buf + len, PAGE_SIZE - len,
                         "%d \t%d \t%lu\t%lu\t %lu  \t %lu %8llu\n",
                         threads_data[i].thread_id,
                         threads_data[i].cpu_id,
                         threads_data[i].attempt_count,
                         threads_data[i].acquired_count,
                         threads_data[i].acquiring_time,
                         avg_lat_per_thread,
                         thread_throughput_per_sec);

//                         threads_data[i].thread_private_counter,
//                         "Thread#%d, cpu#%d, private_counter=%lu, attempts=%lu, successes=%lu, state=%s\n",
        if (len >= PAGE_SIZE) {
            break; // Prevent buffer overflow
        }
    }

    unsigned long latency_clk_median = thread_latency_calculate_median(threads_data, thread_num);
    /* For summary */
    //len += scnprintf(buf + len, PAGE_SIZE - len,"Total Acquired: %lu\n", lock_count);
    //total_acquired
    len += scnprintf(buf + len, PAGE_SIZE - len,"Lock_mode: %s%s, other_works_pause: %d us, other_works_sleep: %d us, wait_cycles: %llu, holdon_cycles: %llu thread_count: %d\n", \
        (g_batch_lock) ? "Batch_":"", lock_mode_str(g_lock_mode), \
        g_other_works_pause_us, g_other_works_sleep_us, g_other_works_wait_time_cycles, g_holdon_time_cycles, thread_num);
    len += scnprintf(buf + len, PAGE_SIZE - len, "Lock addr: 0x%llx, Physial Addr: 0x%llx \n", g_lock_virt_addr, g_lock_phys_addr);    
    len += scnprintf(buf + len, PAGE_SIZE - len,"Total Acquired: %llu , Global lock counter: %llu, Shared value: %llu\n", total_acquired, lock_count, read64_atomic_value(&(my_shared_data.shared_value)));
    len += scnprintf(buf + len, PAGE_SIZE - len,"Total Run Time(us): %llu\n", g_test_duration_ns/1000);
    // len += scnprintf(buf + len, PAGE_SIZE - len,"Avg Bench Duration(us): %llu\n", all_bench_duration_ns/thread_num/1000);
    // len += scnprintf(buf + len, PAGE_SIZE - len,"Avg Latency(clk): %llu\n", all_lantecy_clk/thread_num);
    len += scnprintf(buf + len, PAGE_SIZE - len,"Avg Latency(clk): %llu, Median Lat(clk): %lu\n", all_lantecy_clk/thread_num, latency_clk_median);
    len += scnprintf(buf + len, PAGE_SIZE - len,"LockAcquired Throughput(/s): %llu\n", total_throughput_per_sec);

    if (len >= PAGE_SIZE) {
        return PAGE_SIZE; // Prevent buffer overflow
    }

    return len;

}

static ssize_t value_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count)
{
    int ret, new_value;

    ret = kstrtoint(buf, 10, &new_value);
    if (ret < 0)
        return ret;

//    spinlock_bench_value = new_value;
//    shared_value = new_value;
    write64_atomic_value(&(my_shared_data.shared_value), new_value);
    write64_atomic_value(&spinlock_bench_value, new_value);

    pr_info("spinlock_bench_sysfs: value updated to %llu\n", read64_atomic_value(&spinlock_bench_value));
    return count;
}

// Sysfs show and store functions for `test_on`
static ssize_t test_on_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sprintf(buf, "%d\n", test_on);
}

static ssize_t test_on_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count)
{
    int ret, i;
    long long v;
    bool new_value;

    ret = kstrtobool(buf, &new_value);
    if (ret < 0)
        return ret;

    //test_on = new_value;

    // if (test_on) {
    //     threads_on_spinlock();
    // }

    if (test_on != new_value) {
        if (new_value) {
            // re-clean the data is test start .
            if (threads_data) {
                for (i = 0; i < thread_num; i++) {
                            threads_data[i].state = THREAD_STOPPED;
                            threads_data[i].thread_private_counter = 0;
                            threads_data[i].attempt_count = 0;
                            threads_data[i].acquired_count = 0;
                            //threads_data[i].acquiring_time = 0;
                }
            }
            
            write64_atomic_value(&spinlock_bench_value, 0);
            write64_atomic_value(&(my_shared_data.shared_value), 0);
            wmb();  //incase for not atomic write.
        }

        // test on /off for each thread;
        if (threads_data) {
            for (i = 0; i < thread_num; i++) {
                        threads_data[i].test_on = new_value;
            }
        }

        test_on = new_value;

        if (test_on) {
            // Start threads when test_on is set to 1
            test_flag = 1;

            // Record thread start time
            thread_start_time = ktime_get();

            if (threads || thread1 || thread2) {
                // threads have been created. 
                msleep(10);
                pr_info("spinlock_bench_sysfs: Just test on the threads exist...");
            } else {
#ifdef START_THREADS_WITH_TEST_ON
                // first time to creat threads.
                start_threads_function();
                stop_threads = 0;
#else 
                test_flag = 0;
                test_on = 0;
                pr_info("spinlock_bench_sysfs: Please Start the threads before test on");
#endif
            }
        } else {
            v = read64_atomic_value(&(my_shared_data.shared_value));
            // Stop threads when test_on is set to 0
            test_flag = 0;
            // Record thread stop time
            thread_stop_time = ktime_get();
            /* Don't stop thread immediately, since there might be some spinlock in slowpath */
            //stop_threads_function();
            pr_info("spinlock_bench_sysfs: The shared value is : %llu \n", v);

            g_test_duration_ns = ktime_to_ns(ktime_sub(thread_stop_time, thread_start_time));

            pr_info("spinlock_bench_sysfs: Total time duration: %lld nanoseconds\n",g_test_duration_ns);
            msleep(10);
            //spinlock_bench_value = v;
            //(my_shared_data.shared_value) = 0;
            write64_atomic_value(&spinlock_bench_value, v);
            //write64_atomic_value(&(my_shared_data.shared_value), 0);
            wmb();  //In case for not atomic write.
        }

        pr_info("spinlock_bench_sysfs: test_on set to %d\n", new_value);
    } else {
        pr_info("spinlock_bench_sysfs: No change for test_on...");
    }

    return count;
}

// Sysfs show and store functions for `start_threads`
static ssize_t start_threads_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sprintf(buf, "%d\n", start_threads);
}

static ssize_t start_threads_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count)
{
    int ret;
    bool new_value;

    ret = kstrtobool(buf, &new_value);
    if (ret < 0)
        return ret;

#if SPINLOCK_NOT_USE_STATIC_MEM
    if (g_dynamic_lock_addr )
        ret = lock_address_remap();

#endif

    pr_info("spinlock_bench_sysfs: start threads set to %d\n", new_value);


    if (start_threads != new_value) {
        start_threads = new_value;

        //shared_value = 0;
        write64_atomic_value(&(my_shared_data.shared_value), 0);

        if (start_threads) {
            // start threads when start_threads is set to 1
            test_flag = 0;
#ifndef START_THREADS_WITH_TEST_ON
           // first time to creat threads.
            start_threads_function();
            stop_threads = 0;
#endif
        } else {
            //  do nothing  when start_threads is set to 0
            test_flag = 0;
        }
    } else {
        pr_info("spinlock_bench_sysfs: No change for start_threads...");
    }

    msleep(10);

    return count;
}

// Sysfs show and store functions for `stop_threads`
static ssize_t stop_threads_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sprintf(buf, "%d\n", stop_threads);
}

static ssize_t stop_threads_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count)
{
    int ret;
    bool new_value;

    ret = kstrtobool(buf, &new_value);
    if (ret < 0)
        return ret;

    pr_info("spinlock_bench_sysfs: Stop_threads set to %d\n", new_value);


    if (stop_threads != new_value) {
        stop_threads = new_value;

        if (stop_threads) {
            // stop threads when stop_threads is set to 1
            test_flag = 0;
            msleep(10);
            stop_threads_function();
            start_threads = 0;
        } else {
            //  threads when stop_threads is set to 0
            test_flag = 0;
            msleep(10);
        }
        //shared_value = 0;
        write64_atomic_value(&(my_shared_data.shared_value), 0);

    } else {
        pr_info("spinlock_bench_sysfs: No change for stop_threads...");
    }

    return count;
}

// Sysfs show and store functions for `thread_num`
static ssize_t thread_num_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sprintf(buf, "%d\n", thread_num);
}

static ssize_t thread_num_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count)
{
    int ret, new_counter;

    ret = kstrtoint(buf, 10, &new_counter);
    if (ret < 0)
        return ret;

    if (new_counter < 0 || new_counter > 65535)
        return -EINVAL;

    thread_num = new_counter;

    pr_info("spinlock_bench_sysfs: thread_num updated to %d\n", thread_num);
    return count;
}

// Sysfs show and store functions for `nr_cpu`
static ssize_t nr_cpu_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sprintf(buf, "%d\n", nr_cpu);
}

static ssize_t nr_cpu_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count)
{
    int ret, new_counter;

    ret = kstrtoint(buf, 10, &new_counter);
    if (ret < 0)
        return ret;

    if (new_counter > 0) {
        nr_cpu = new_counter;
        pr_info("spinlock_bench_sysfs: nr_cpu updated to %d\n", nr_cpu);
    } else {
        pr_warn("spinlock_bench_sysfs: nr_cpu MUST be > 0, keep it to %d\n", nr_cpu);
    }

    return count;
}

static ssize_t cpumask_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf) {
    int max_cpus = num_online_cpus();

    //return snprintf(buf, PAGE_SIZE, "%*pbl\n", cpumask_pr_args(&cpuaffinity_mask));
    return snprintf(buf, PAGE_SIZE, "%*pbl\n", max_cpus, (&cpuaffinity_mask));

}

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
static int hexstring_to_cpumask(const char *str, struct cpumask * cmask, int max_bits)
{
    const char *p = str;
    int bit_pos = 0;
    int value, str_lengh = strlen(str);
    int i;

    while (isspace(*p))
        p++;

    if (*p == '\0')
        return -EINVAL;    

    if (str_lengh >= 2) {
        if (str[0] == '0' && (str[1] == 'x' || str[1] == 'X') ) {
            str += 2;
            str_lengh -= 2;
        }
    }
    //pr_info("spinlock_bench_sysfs: cpumask string is %s\n", str);
    p = str + str_lengh - 2;
    while (p >= str && !isspace(*p)) {
        value = hex_char_to_value(*p);
        if (value < 0)
            return -EINVAL;

        // hex value has 4 bit.
        for (i = 0; i < 4; i++) {
            //pr_info("spinlock_bench_sysfs: bit_pos to %d\n", bit_pos);
            if (bit_pos >= max_bits)
                break;

            if (value & (1 << i))
               cpumask_set_cpu(bit_pos, cmask);

            bit_pos++;
        }

        p--;
    }

    return 0;
}

static ssize_t cpumask_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count) {
    
    mutex_lock(&control_lock);
#if MAX_CORES > 64
    int ret;
    struct cpumask new_mask;

    cpumask_clear(&new_mask);

    ret = hexstring_to_cpumask(buf, &new_mask, MAX_CORES);
    if (ret) {
        pr_err("Failed to parse CPU mask with input %s,  error code %d\n", buf, ret);
        mutex_unlock(&control_lock);
        return ret;
    }

    cpumask_copy(&cpuaffinity_mask, &new_mask);


    pr_info("spinlock_bench_sysfs: CPU affinity updated: %*pbl\n", cpumask_pr_args(&cpuaffinity_mask));

#else 
    int i, num_cpus = num_online_cpus();
    unsigned long mask;
    if (num_cpus > MAX_CORES) {
        num_cpus = MAX_CORES;
        pr_warn("spinlock_bench_sysfs: set the cpumask max core to %d \n", num_cpus);
    }

    if (sscanf(buf, "%lx", &mask) != 1) {
        mutex_unlock(&control_lock);
        return -EINVAL;
    }

//    pr_info("mask input:%lx\n", mask);
    cpumask_clear(&cpuaffinity_mask);
    //cpumask_setall(&cpuaffinity_mask); // Set all bits to 1
    for ( i = 0; i < num_cpus; i++) {
        if (mask & (1UL << i)) {
            cpumask_set_cpu(i, &cpuaffinity_mask);
        }
    }
    
    int cpu_count = cpumask_weight(&cpuaffinity_mask);
    pr_info("spinlock_bench_sysfs: set the cpumask max core number to %d \n", cpu_count);

#endif

    mutex_unlock(&control_lock);

    return count;
}

// Sysfs show and store functions for `cpuaffinity`
static ssize_t cpuaffinity_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return snprintf(buf, PAGE_SIZE, "%*pbl\n", cpumask_pr_args(&cpuaffinity_mask));
}

static ssize_t cpuaffinity_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count)
{
    cpumask_t new_mask;
    int ret;

    // Parse the CPU affinity mask from the user input
    ret = cpumask_parse(buf, &new_mask);
    if (ret < 0) {
        pr_err("spinlock_bench_sysfs: Invalid cpuaffinity value\n");
        return ret;
    }

    // Update the CPU affinity mask
    cpumask_copy(&cpuaffinity_mask, &new_mask);
    pr_info("spinlock_bench_sysfs: CPU affinity updated: %*pbl\n", cpumask_pr_args(&cpuaffinity_mask));

    return count;
}

// Sysfs show and store functions for `lock_mode`
static ssize_t lock_mode_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sprintf(buf, "0x%x\n", g_batch_lock? 0x80 | g_lock_mode : g_batch_lock);
}

static ssize_t lock_mode_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count)
{
    int ret, new_counter;

    //ret = kstrtoint(buf, 10, &new_counter);
    ret = sscanf(buf, "0x%x", &new_counter);

    if (ret < 0)
        return ret;

    if (new_counter >= 0 && new_counter < LAST_LOCK) {
        g_lock_mode = new_counter & 0x7F;
        g_batch_lock = new_counter >> 7;
        pr_info("spinlock_bench_sysfs: g_lock_mode updated to %d, batch mode: %d\n", g_lock_mode, g_batch_lock);
    } else {
        pr_warn("spinlock_bench_sysfs: g_lock_mode MUST be in range [0 ~ %d], keep it to %d\n", LAST_LOCK, g_lock_mode);
    }

    return count;
}

// Sysfs show and store functions for `trace_print`
static ssize_t trace_print_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sprintf(buf, "%d\n", g_trace_print);
}

static ssize_t trace_print_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count)
{
    int ret;
    bool new_value;

    ret = kstrtobool(buf, &new_value);
    if (ret < 0)
        return ret;

    if (g_trace_print != new_value) {
        g_trace_print = new_value;
        pr_info("spinlock_bench_sysfs: g_trace_print set to %d\n", new_value);
    } else {
        pr_info("spinlock_bench_sysfs: No change for g_trace_print...");
    }

    return count;
}

//for g_other_works_pause_us
// Sysfs show and store functions for `g_other_works_pause_us`
static ssize_t other_works_pause_us_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sprintf(buf, "%d\n", g_other_works_pause_us);
}

static ssize_t other_works_pause_us_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count)
{
    int ret, new_counter;

    ret = kstrtoint(buf, 10, &new_counter);
    if (ret < 0)
        return ret;

    if (new_counter >= 0) {
        g_other_works_pause_us = new_counter;
        pr_info("spinlock_bench_sysfs: g_other_works_pause_us updated to %d\n", g_other_works_pause_us);
    } else {
        pr_warn("spinlock_bench_sysfs: g_other_works_pause_us MUST be >= 0, keep it to %d\n", g_other_works_pause_us);
    }

    return count;
}

//for g_other_works_pause_us
// Sysfs show and store functions for `g_other_works_sleep_us`
static ssize_t other_works_sleep_us_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sprintf(buf, "%d\n", g_other_works_sleep_us);
}

static ssize_t other_works_sleep_us_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count)
{
    int ret, new_counter;

    ret = kstrtoint(buf, 10, &new_counter);
    if (ret < 0)
        return ret;

    if (new_counter >= 0) {
        g_other_works_sleep_us = new_counter;
        pr_info("spinlock_bench_sysfs: g_other_works_sleep_us updated to %d\n", g_other_works_sleep_us);
    } else {
        pr_warn("spinlock_bench_sysfs: g_other_works_sleep_us MUST be >= 0, keep it to %d\n", g_other_works_sleep_us);
    }

    return count;
}

//static uint64_t g_holdon_time_cycles = 0;   // hold on duration in critical section, with cycles.
//static uint64_t g_other_works_wait_time_cycles = 0;
//for g_holdon_time_cycles
// Sysfs show and store functions for `g_holdon_time_cycles`
static ssize_t holdon_cycles_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sprintf(buf, "%llu\n", g_holdon_time_cycles);
}

static ssize_t holdon_cycles_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count)
{
    int ret, new_counter;

    ret = kstrtoint(buf, 10, &new_counter);
    if (ret < 0)
        return ret;

    if (new_counter >= 0) {
        g_holdon_time_cycles = new_counter;
        pr_info("spinlock_bench_sysfs: g_holdon_time_cycles updated to %llu\n", g_holdon_time_cycles);
    } else {
        pr_warn("spinlock_bench_sysfs: g_holdon_time_cycles MUST be >= 0, keep it to %llu\n", g_holdon_time_cycles);
    }

    return count;
}

//for g_other_works_wait_time_cycles
// Sysfs show and store functions for `g_other_works_wait_time_cycles`
static ssize_t other_works_wait_time_cycles_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sprintf(buf, "%llu\n", g_other_works_wait_time_cycles);
}

static ssize_t other_works_wait_time_cycles_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count)
{
    int ret, new_counter;

    ret = kstrtoint(buf, 10, &new_counter);
    if (ret < 0)
        return ret;

    if (new_counter >= 0) {
        g_other_works_wait_time_cycles = new_counter;
        pr_info("spinlock_bench_sysfs: g_other_works_wait_time_cycles updated to %llu\n", g_other_works_wait_time_cycles);
    } else {
        pr_warn("spinlock_bench_sysfs: g_other_works_wait_time_cycles MUST be >= 0, keep it to %llu\n", g_other_works_wait_time_cycles);
    }

    return count;
}

// Sysfs show and store functions for `test_on`
static ssize_t lock_phy_address_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sprintf(buf, "0x%llx\n", g_lock_phys_addr);
}

// Sysfs show and store functions for `test_on`
static ssize_t allocated_base_address_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sprintf(buf, "0x%llx\n", lock_base_phys_addr);
}

// Sysfs show and store functions for `g_cha_id`
static ssize_t cha_id_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sprintf(buf, "%d\n", g_cha_id);
}

static ssize_t cha_id_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count)
{
    int ret, new_counter;

    ret = kstrtoint(buf, 10, &new_counter);
    if (ret < 0)
        return ret;

    if (new_counter >= 0) {
        g_cha_id = new_counter;
        pr_info("spinlock_bench_sysfs: g_cha_id updated to %d\n", g_cha_id);
    } else {
        pr_warn("spinlock_bench_sysfs: g_cha_id MUST be >= 0, keep it to %d\n", g_cha_id);
    }

    return count;
}

// Sysfs show and store functions for `lock_address_offset`
static ssize_t lock_address_offset_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sprintf(buf, "0x%llx\n", offset4selected_cha);
}

static ssize_t lock_address_offset_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count)
{
    int ret;
    uint64_t new_counter;

    // ret = kstrtoint(buf, 16, &new_counter);
    // if (ret < 0)
    //     return ret;

    ret = sscanf(buf, "0x%llx", &new_counter);
    if (ret < 0)
        return ret;

    if (new_counter >= 0) {
        offset4selected_cha = new_counter;
        pr_info("spinlock_bench_sysfs: offset4selected_cha updated to 0x%llx\n", offset4selected_cha);
        g_lock_phys_addr = lock_base_phys_addr + offset4selected_cha;
    } else {
        pr_warn("spinlock_bench_sysfs: offset4selected_cha MUST be >= 0, keep it to 0x%llx\n", offset4selected_cha);
    }

    return count;
}

// Sysfs show and store functions for `g_numa_node_id for spinlock address`
static ssize_t lock_numa_node_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sprintf(buf, "%d\n", g_numa_node_id);
}

static ssize_t lock_numa_node_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count)
{
    int ret, new_counter;

    ret = kstrtoint(buf, 10, &new_counter);
    if (ret < 0)
        return ret;

    if (new_counter >= 0) {
        g_numa_node_id = new_counter;
        pr_info("spinlock_bench_sysfs: g_numa_node_id updated to %d\n", g_numa_node_id);
    } else {
        pr_warn("spinlock_bench_sysfs: g_numa_node_id MUST be >= 0, keep it to %d\n", g_numa_node_id);
    }

    return count;
}


// Sysfs show and store functions for `g_mem_page_order`
static ssize_t mem_page_order_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sprintf(buf, "page order: %d -> Memory page count: %d, Memory size: 0x%lx\n", g_mem_page_order, 1 << g_mem_page_order, 1LU << g_mem_page_order << PAGE_SHIFT);
}

static ssize_t mem_page_order_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count)
{
    int ret, new_counter;

    ret = kstrtoint(buf, 10, &new_counter);
    if (ret < 0)
        return ret;

    if (new_counter >= 0) {
        g_mem_page_order = new_counter;
        pr_info("spinlock_bench_sysfs: g_mem_page_order updated to %d\n", g_mem_page_order);
    } else {
        pr_warn("spinlock_bench_sysfs: g_mem_page_order MUST be >= 0, keep it to %d\n", g_mem_page_order);
    }

    return count;
}


// Sysfs show and store functions for `g_dynamic_lock_addr`
static ssize_t dynamic_lock_addr_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
    return sprintf(buf, "%d\n", g_dynamic_lock_addr);
}

static ssize_t dynamic_lock_addr_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count)
{
    int ret;
    bool new_value;

    ret = kstrtobool(buf, &new_value);
    if (ret < 0)
        return ret;

    if (g_dynamic_lock_addr != new_value) { 
        g_dynamic_lock_addr = new_value;
        pr_info("spinlock_bench_sysfs: g_dynamic_lock_addr updated to %d\n", g_dynamic_lock_addr);

        if (g_dynamic_lock_addr) {
            ret = lock_address_allocation();
            if (ret < 0)
                return ret;
        } else {
            if(lock_base_virt_addr) {
                free_pages(lock_base_virt_addr, g_mem_page_order);
                lock_base_virt_addr = 0;
                lock_base_phys_addr = 0;
                printk("spinlock_bench: free_pages ok! \n");
            }

            offset4selected_cha = 0;

            lock_init_by_mode(g_lock_mode);

            g_lock_phys_addr = kvirt_to_phys((void *)g_lock_virt_addr);

            pr_info("Static SpinLock Virtual address: 0x%llx\n", g_lock_virt_addr);
            pr_info("Static SpinLock Physical address: 0x%llx\n", g_lock_phys_addr);

        }

    } else {
        pr_warn("spinlock_bench_sysfs: no change for g_mem_page_order");
    }

    return count;
}


// Define sysfs attributes for each value
static struct kobj_attribute value_attribute = __ATTR(value, 0664, value_show, value_store);
static struct kobj_attribute test_on_attribute = __ATTR(test_on, 0664, test_on_show, test_on_store);
static struct kobj_attribute thread_num_attribute = __ATTR(thread_num, 0664, thread_num_show, thread_num_store);
static struct kobj_attribute start_threads_attribute = __ATTR(start_threads, 0664, start_threads_show, start_threads_store);
static struct kobj_attribute stop_threads_attribute = __ATTR(stop_threads, 0664, stop_threads_show, stop_threads_store);
static struct kobj_attribute nr_cpu_attribute = __ATTR(nr_cpu, 0664, nr_cpu_show, nr_cpu_store);
static struct kobj_attribute cpuaffinity_attribute = __ATTR(cpuaffinity, 0664, cpuaffinity_show, cpuaffinity_store);
static struct kobj_attribute lock_mode_attribute = __ATTR(lock_mode, 0664, lock_mode_show, lock_mode_store);
static struct kobj_attribute trace_print_attribute = __ATTR(trace_print, 0664, trace_print_show, trace_print_store);
static struct kobj_attribute other_works_sleep_us_attribute = __ATTR(other_works_sleep_us, 0664, other_works_sleep_us_show, other_works_sleep_us_store);
static struct kobj_attribute other_works_pause_us_attribute = __ATTR(other_works_pause_us, 0664, other_works_pause_us_show, other_works_pause_us_store);
static struct kobj_attribute cpumask_attribute = __ATTR(cpumask, 0664, cpumask_show, cpumask_store);
static struct kobj_attribute lock_phy_address_attribute = __ATTR(lock_phy_address, 0444, lock_phy_address_show, NULL);
static struct kobj_attribute allocated_base_address_attribute = __ATTR(allocated_base_address, 0444, allocated_base_address_show, NULL);
static struct kobj_attribute cha_id_attribute = __ATTR(cha_id, 0664, cha_id_show, cha_id_store);
static struct kobj_attribute lock_address_offset_attribute = __ATTR(lock_address_offset, 0664, lock_address_offset_show, lock_address_offset_store);
static struct kobj_attribute lock_numa_node_attribute = __ATTR(lock_numa_node, 0664, lock_numa_node_show, lock_numa_node_store);
static struct kobj_attribute mem_page_order_attribute = __ATTR(mem_page_order, 0664, mem_page_order_show, mem_page_order_store);
static struct kobj_attribute dynamic_lock_addr_attribute = __ATTR(dynamic_lock_addr, 0664, dynamic_lock_addr_show, dynamic_lock_addr_store);
static struct kobj_attribute other_works_wait_time_attribute = __ATTR(other_work_wait_cycles, 0664, other_works_wait_time_cycles_show, other_works_wait_time_cycles_store);
static struct kobj_attribute holdon_time_attribute = __ATTR(holdon_cycles, 0664, holdon_cycles_show, holdon_cycles_store);
// Array of attributes for cleanup
static struct attribute *spinlock_bench_attrs[] = {
    &value_attribute.attr,
    &test_on_attribute.attr,
    &start_threads_attribute.attr,
    &stop_threads_attribute.attr,
    &thread_num_attribute.attr,
    &nr_cpu_attribute.attr,
//    &cpuaffinity_attribute.attr,
    &lock_mode_attribute.attr,
    &trace_print_attribute.attr,
    &other_works_sleep_us_attribute.attr,
    &other_works_pause_us_attribute.attr,
    &cpumask_attribute.attr,
    &lock_phy_address_attribute.attr,
    &allocated_base_address_attribute.attr,
    &cha_id_attribute.attr,
    &lock_address_offset_attribute.attr,
    &lock_numa_node_attribute.attr,
    &mem_page_order_attribute.attr,
    &dynamic_lock_addr_attribute.attr,
    &other_works_wait_time_attribute.attr,
    &holdon_time_attribute.attr,
    NULL, // Terminator
};

// Attribute group
static struct attribute_group spinlock_bench_attr_group = {
    .attrs = spinlock_bench_attrs,
};

//////////////////////////////////////////////////////////////////////
// end of sysfs functions
//////////////////////////////////////////////////////////////////////

// Module initialization
static int __init spinlock_bench_sysfs_init(void)
{
    int ret;

    pr_info("Load spinlock kernel benchmark module, version is %s \n", VERSION);

#ifdef CONFIG_X86_TSC
    g_tsc_freq_mhz_per_us = tsc_khz / 1000;
    pr_info("TSC frequency: %u kHz (%u MHz)\n", tsc_khz, g_tsc_freq_mhz_per_us);
#else
    get_tsc_frequency(&g_tsc_freq_mhz_per_us);
    pr_info("TSC not available on this architecture, calculate tsc frequcny is : %u mhz.\n", g_tsc_freq_mhz_per_us);
#endif

    g_rdtsc_overhead = compute_rdtsc_latency();
    pr_info("RDTSC overhead is %d cycles.\n", g_rdtsc_overhead);

    pr_info("Size of spinlock_t: %zu bytes\n", sizeof(spinlock_t));

#if SPINLOCK_NOT_USE_STATIC_MEM
  #if 0 // move this pieces of code to start_thread function.
    int page_order = g_mem_page_order;
    //g_lock_virt_addr = __get_free_pages(GFP_KERNEL, page_order);
    g_lock_virt_addr = my_allocate_free_page(g_numa_node_id, page_order);
    if (! g_lock_virt_addr) {
        pr_warn("SpinLock_bench: Can't allocate %d free pages \n", 1<<page_order);
        return -ENOMEM;
    } else {
        pr_info("SpinLock_bench: Allocate %d free pages, at address: 0x%lx \n", 1<<page_order, g_lock_virt_addr);
    }
    lock_base_virt_addr = g_lock_virt_addr;
    lock_base_phys_addr  = __pa(lock_base_virt_addr);
    g_lock_phys_addr = lock_base_phys_addr + offset4selected_cha;
    g_lock_virt_addr = __va(g_lock_phys_addr);

    pr_info("SpinLock allocated Base Virtual address: 0x%llx\n", lock_base_virt_addr);
    pr_info("SpinLock allocated Base Physical address: 0x%lx\n", lock_base_phys_addr);

    pr_info("Selected Address: Virt: 0x%llx, Phy: 0x%llx\n", g_lock_virt_addr, g_lock_phys_addr);

    bench_spinlock_ptr = (spinlock_t * )g_lock_virt_addr;
    //spin_lock_init(bench_spinlock_ptr);
  #endif
  if (g_dynamic_lock_addr) {
    pr_info("SpinLock bench: use the dynamic allocated spinlock address\n");
    lock_address_allocation();
    if (ret < 0)
        return ret;
  } else {

    lock_init_by_mode(g_lock_mode);

    // // get the spinlock physical address.
    // g_lock_virt_addr = (uint64_t)&spinlock_bench_spinlock;
    // g_lock_phys_addr = virt_to_phys((void *)g_lock_virt_addr);
    // lock_page = virt_to_page(g_lock_virt_addr);
    // lock_page_phys_addr = page_to_phys(lock_page);

    g_lock_phys_addr = kvirt_to_phys((void *)g_lock_virt_addr);

    pr_info("SpinLock Virtual address: 0x%llx\n", g_lock_virt_addr);
    pr_info("SpinLock Physical address: 0x%llx\n", g_lock_phys_addr);
  }
#else 

    lock_init_by_mode(g_lock_mode);

    // g_lock_phys_addr = virt_to_phys((void *)g_lock_virt_addr);
    // lock_page = virt_to_page(g_lock_virt_addr);
    // lock_page_phys_addr = page_to_phys(lock_page);

    g_lock_phys_addr = kvirt_to_phys((void *)g_lock_virt_addr);

    pr_info("SpinLock Virtual address: 0x%llx\n", g_lock_virt_addr);
    pr_info("SpinLock Physical address: 0x%llx\n", g_lock_phys_addr);
    //pr_info("SpinLock Page Physical address: 0x%lx\n", lock_page_phys_addr);
#endif

    // Create a directory under /sys/kernel/
    spinlock_bench_kobj = kobject_create_and_add(SYSFS_DIR_NAME, kernel_kobj);
    if (!spinlock_bench_kobj)
        return -ENOMEM;

    // Create the sysfs files in the directory
    ret = sysfs_create_group(spinlock_bench_kobj, &spinlock_bench_attr_group);
    if (ret) {
        pr_err("spinlock_bench_sysfs: failed to create sysfs group\n");
        kobject_put(spinlock_bench_kobj);
        return ret;
    }

    pr_info("spinlock_bench_sysfs: module loaded\n");
    return 0;
}

// Module cleanup
static void __exit spinlock_bench_sysfs_exit(void)
{
    // // Stop the worker threads
    // if (thread1)
    //     kthread_stop(thread1);
    // if (thread2)
    //     kthread_stop(thread2);

    test_on = false;
    stop_threads_function();

    // Remove the sysfs group and directory
    sysfs_remove_group(spinlock_bench_kobj, &spinlock_bench_attr_group);
    kobject_put(spinlock_bench_kobj);

    if(lock_base_virt_addr) {
        free_pages(lock_base_virt_addr, g_mem_page_order);
        lock_base_virt_addr = 0;
        lock_base_phys_addr = 0;
        printk("spinlock_bench: free_pages ok! \n");
    }

    pr_info("spinlock_bench: module removed\n");
}

module_init(spinlock_bench_sysfs_init);
module_exit(spinlock_bench_sysfs_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Michael.Zhang");
MODULE_DESCRIPTION("Kernel Module with Multi-Threading spinlock ");
MODULE_VERSION(VERSION);
