spinlock benchmark, it's a kernel module to bench the spinlock perforamnce in kernel space, e.g. queued spinlock with slowpath. 
run 'make' to build the kernel module, and insmod spinlock_bench.ko to insert the kernel module, 
You will see below control node in /sys/kernel/spinlock_bench/: 

allocated_base_address: check this node to find out the allocated based address for spinlock.
cha_id
cpumask
dynamic_lock_addr:  on/off, use dynamic memory space (use get_free_page to allocate physical memory ) or static memory space for spinlock.
lock_address_offset:    The actuall memory address offset based on the `allocated_base_address` for lock. 
lock_mode:          support 0/1,  0: queued spinlock with slowpath , default in kernel;  1: retry spinlock. 
lock_numa_node:     used 
lock_phy_address:   The actuall memory address for lock
mem_page_order:     used to specify the memory pages want to allocate, to swap the memory address for spinlock benchmark. 
nr_cpu
other_works_pause_us:   default is 8,  pause work out of the lock critial section.
other_works_sleep_us:   default is 0, ilde work out of the lock critial section.
start_threads
stop_threads
test_on
thread_num
trace_print
value  -- ouput the result. 

# in script foler, there are script tools to run the benchmark. 
e.g.  bash -x ./bench_spinlock.sh -t 32 -c FFFFFFFF -d 16 -r 1   # run 32 threads with 16 seconds, the threads are affinity to 0xFFFFFFFF

## The application 
cha2mem. used to map the memory address with specified CHA_ID. with this tool, user can map the spinlock address to specified CHA, to benchmark the spinlock performance.
Usage: cha2mem -b <base_address> -s <size> -i <cha_id>
  -b <base_address> : Base physical address (hex format)
  -s <memory size>  : Memory range size (hex format)
  -i <cha_id>       : CHA ID to calculate the corresponding address
  -m <num_cha>      : Number of CHA slices in one NUMA node on a socket
  -c <num_cluaer>   : Number of clusters in one NUMA node on a socket