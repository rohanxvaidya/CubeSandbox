#!/bin/bash

#$1 = test on
#$2 = thread count
#$3 = nr cpu
#$4 = test duration

test_duration=${4:-"10"}
test_start=0
MOD_NAME="spinlock_bench"
result=10
throughput=0
spinlock_sysfs_path="/sys/kernel/spinlock_bench"
module_load_tool="module_load.sh"

echo 40 > /proc/sys/kernel/watchdog_thresh
#echo "performance" |tee //sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

if [ "$1" == "1" ] ;then
  insmod "$MOD_NAME".ko
  sleep 2s
 echo "test on"
 test_start=1
  bash -x ${module_load_tool}
  echo $2 > ${spinlock_sysfs_path}/thread_num
  sleep 1
  echo $3 > ${spinlock_sysfs_path}/nr_cpu
  sleep 1
  echo 1 > ${spinlock_sysfs_path}/start_threads
  sleep 5s
else
   echo "test off"
fi

if [ "$test_start" == "1" ];then
#   echo $1 > /sys/kernel/spinlock_bench/test_on
   echo "Start test with $test_duration seconds..."
   echo 1 > ${spinlock_sysfs_path}/test_on
   sleep $test_duration
   echo 0 > ${spinlock_sysfs_path}/test_on

   sleep 2s
   result=`(cat ${spinlock_sysfs_path}/value)`
   echo "Benchmark result is ${result} with $test_duration seconds"
   throughput=$((result/test_duration))
   echo "Throughput is ${throughput} ops/s"

  echo "Stop the threads..."
  sleep 30s
  echo 1 > ${spinlock_sysfs_path}/stop_threads
  sleep 2s

  echo "remove the module..."
  rmmod "$MOD_NAME".ko

fi
