#!/bin/bash

#### below is the control node in sysfs path for spinlock_bench kernel module:
# allocated_base_address
# cha_id
# cpumask
# dynamic_lock_addr
# lock_address_offset
# lock_mode -- 0 - queuespinlock , 1-retry-spinlock, 2-pthread-spinlock,.... 80-Batch_qspinlock, 81-Batch retry-spinlock
# lock_numa_node
# lock_phy_address
# mem_page_order
# nr_cpu
# other_works_pause_us
# other_works_sleep_us
# start_threads
# stop_threads
# test_on
# thread_num
# trace_print
# value  -- ouput the result. 
# other_work_wait_cycles --- wait cycles(TSC) after unlock
# holdon_cycles -- hold on cycles (TSC) in critical section.

# Default values
threads=0
core_number=0
test_duration=0
reset_type=0
KERNEL_MODULE="spinlock_bench"
SYSFS_PATH="/sys/kernel/spinlock_bench"
core_mask=1
lock_mode=0x0
other_works_pause_us=""
other_works_sleep_us=""
addr_offset=""
numa_id=""
order_size=""
holdon_cycles=""
wait_cycles=""

# Function to display usage
usage() {
    echo "Usage: $0 -t <threads> -c <core_mask> -d <test_duration> -r <reset_type> -l <lock_mode> [-o <addr_offset>] [-p <other_works_pause_us>] [-s <other_works_sleep_us>]"
    echo "-t <threads>,         threads will be created"
    echo "-d <test_duration>,   Test time, duration secondss"
    echo "-c <core_mask>,       core_mask options:"
    echo "      FF00 - core 8-15"
    echo "-r <reset_type>       reset_type options:"
    echo "      0 - Reload kernel module ${KERNEL_MODULE} for each test"
    echo "      1 - Reset threads and test"
    echo "      2 - Restart test "
    echo "-l <lock_mode>        lock_mode options, hex value, 0x80/0x81/0x82/0x83 is for batch lock test"
    echo "      0x0 - queued spinlock, with slowpath, kernel default mode"
    echo "      0x1 - retry spinlock"
    echo "      0x2 - pthread spinlock"
    echo "      0x3 - mutex lock"
    echo "-o <addr_offset>      addr_offset:"
    echo "      0x00 -- by default"
    echo "-H <holdon_cycles>,   How many cpu cycles hold on in critical section. refer to TSC frequency"
    echo "-W <wait_cycles>,     How many cpu cycles spend after unlock, wait time before next acquring lock. refer to TSC frequency"
    echo "-n <numa_id>          numa node id"
    echo "-g <page_order_size>  allocated memory size for spinlock test, it's the page order of 2,  i.e. page conter = 1 << order_size"

    exit 1
}

# Parse command line arguments
while getopts "t:c:d:r:l:p:s:o:n:g:H:W:" opt; do
    case ${opt} in
        t) threads=${OPTARG} ;;
        c) core_mask=${OPTARG} ;;
        d) test_duration=${OPTARG} ;;
        r) reset_type=${OPTARG} ;;
        l) lock_mode=${OPTARG} ;;
        p) other_works_pause_us=${OPTARG} ;;
        s) other_works_sleep_us=${OPTARG} ;;
        o) addr_offset=${OPTARG} ;;
        n) numa_id=${OPTARG} ;;
        g) order_size=${OPTARG} ;;
        H) holdon_cycles=${OPTARG} ;;
        W) wait_cycles=${OPTARG} ;;

        *) usage ;;
    esac
done

# Check required parameters
if [ "$threads" -le 0 ] || [ "$test_duration" -le 0 ]; then
    usage
fi

# Check if the kernel module is loaded
if ! lsmod | grep -q "$KERNEL_MODULE"; then
    echo "Loading kernel module ${KERNEL_MODULE}.ko..."
    sudo insmod ${KERNEL_MODULE}.ko
else
    echo "Kernel module ${KERNEL_MODULE}.ko is already loaded."
fi

function setup_bench()
{
    # Set number of threads and core number
    echo $threads > ${SYSFS_PATH}/thread_num

    echo "Cpu mask is set to 0x${core_mask}"
    echo $core_mask > ${SYSFS_PATH}/cpumask

    if [[ ! "$lock_mode" =~ ^0x[0-9a-fA-F]+$ ]]; then
        lock_mode="0x${lock_mode}"
    fi

    echo ${lock_mode} > ${SYSFS_PATH}/lock_mode

    if [ -n "$other_works_pause_us" ]; then
        echo $other_works_pause_us > ${SYSFS_PATH}/other_works_pause_us
    fi

    if [ -n "$other_works_sleep_us" ]; then
        echo $other_works_sleep_us > ${SYSFS_PATH}/other_works_sleep_us
    fi

    if [ -n "$addr_offset" ]; then
        echo $addr_offset > ${SYSFS_PATH}/lock_address_offset
    fi

    if [ -n "$numa_id" ]; then
        echo $numa_id > ${SYSFS_PATH}/lock_numa_node
    fi

    if [ -n "$order_size" ]; then
        echo $order_size > ${SYSFS_PATH}/mem_page_order
    fi

    if [ -n "$holdon_cycles" ]; then 
        echo $holdon_cycles > ${SYSFS_PATH}/holdon_cycles
    fi

    if [ -n "$wait_cycles" ]; then 
        echo $wait_cycles > ${SYSFS_PATH}/other_work_wait_cycles
    fi

}


sw_lockup_thresh=$((test_duration + 2))
echo ${sw_lockup_thresh} > /proc/sys/kernel/watchdog_thresh

# Perform actions based on reset_type
case $reset_type in
    0)
        setup_bench    
        sleep 1
        echo 1 > ${SYSFS_PATH}/start_threads
        sleep 3
        echo "Starting test for ${test_duration} seconds..."
        # Run the test
        echo 1 > ${SYSFS_PATH}/test_on
        sleep ${test_duration}
        echo 0 > ${SYSFS_PATH}/test_on
 
         ;;
    1)
        echo "Resetting threads..."
        echo 0 > ${SYSFS_PATH}/test_on
        sleep 5
        echo 1 > ${SYSFS_PATH}/stop_threads
        sleep 2
        setup_bench
        sleep 5
        echo 1 > ${SYSFS_PATH}/start_threads
        sleep 3
        # Run the test
        echo "Starting test for ${test_duration} seconds..."
        echo 1 > ${SYSFS_PATH}/test_on
        sleep ${test_duration}
        echo 0 > ${SYSFS_PATH}/test_on

        ;;
    2)
        setup_bench
        echo 1 > ${SYSFS_PATH}/start_threads
        sleep 5
        echo "Restarting test..."
        # Run the test
        echo "Starting test for ${test_duration} seconds..."
        echo 1 > ${SYSFS_PATH}/test_on
        sleep ${test_duration}
        echo 0 > ${SYSFS_PATH}/test_on
        ;;
    *)
        echo "Invalid reset_type. Use 0, 1, or 2."
        exit 1
        ;;
esac

# Print the result after the test
sleep 5
echo "Test results:"
echo "-------------------------------------------------------------------------------------------------------------"
cat ${SYSFS_PATH}/value
echo "-------------------------------------------------------------------------------------------------------------"
# Unload the module if reset_type is 0
if [ "$reset_type" -eq 0 ]; then
    sleep 5
    echo 1 > ${SYSFS_PATH}/stop_threads
    sleep 5
    echo "Unloading kernel module ${KERNEL_MODULE}.ko..."
    sudo rmmod $KERNEL_MODULE
fi
# for reset type 1, leave the threads on.

echo "Benchmark completed."