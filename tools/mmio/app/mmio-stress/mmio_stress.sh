#!/bin/bash

thread_count=${1:-"1"} # by default use 1 thread
loop_count=${2:-"1"}  # by default loop 1 time for each thread
scaling=${3:-"0"}	# max thread scaling or not as well as the cpu core scaling..
# if the scaling is enabled, the $thread_count should be the max_thread_count.
scaling_enabled=$scaling

LOG_PATH=./log
# environment vairable for base_addr, e.g. base_addr=0x1e5ffa080000
base_addr=${base_addr:-"0x1e5ffa080000"}
base_core=${base_core:-0} #// base cpu core, default is 0

mkdir -p $LOG_PATH

echo "Check the memory address attribute:"
echo "------------------------"
cat /proc/mtrr
echo "------------------------"
echo "Please check the MTRR attribute for this address range [${base_addr}]"
echo "You can manually set the address to uncachable with mtrr in system, or suppose it is aready uncachable with the device driver map, you can ignore this step if it's remapped in kernel driver"
echo " "

if [ $scaling_enabled == 0 ];then

	for i in $(seq 1 $thread_count); 
	do 
		#echo $i; ./pcimem -m memio -b 0x1e5ffa080000 -s 0x1000 -o w -r 0x20 -v 0x55AA -l $loop_count 
		core=$((base_core + i - 1))
		echo "Start thread $i on Core $core..."; 
		taskset -c $core ./pcimem -m memio -b $base_addr -s 0x1000 -o w -r 0x20 -v 0x55AA -l $loop_count > ${LOG_PATH}/pcimem-test-$(date +"%y%m%d-%H-%M-%S")-$i.log &
	done

	echo "Testing with $thread_count threads..., and check the log in $LOG_PATH "
else 
	# request scaling the threads.
	max_thread_count=$thread_count
	#LOG_PATH="${LOG_PATH}/scaling-$(date +"%y%m%d-%H%M%S")"
	LOG_PATH="${LOG_PATH}/scaling-$base_addr-$(date +"%y%m%d-%H%M%S")"

	mkdir -p ${LOG_PATH}/
	touch ${LOG_PATH}/address-$base_addr

	for t_count in $(seq 1 $max_thread_count); 
	do 
		T_LOG_PATH="${LOG_PATH}/${t_count}-thread"
		mkdir -p ${T_LOG_PATH}
		for i in $(seq 1 $t_count); 
		do 
			#echo $i; ./pcimem -m memio -b 0x1e5ffa080000 -s 0x1000 -o w -r 0x20 -v 0x55AA -l $loop_count 
			core=$((base_core + i - 1))
			echo "Start thread $i on Core $core..."; 

			if [ $i == $t_count ]; then
				## keep the LAST thread in current context to hold the time, not let it in background. 
				taskset -c $core ./pcimem -m memio -b $base_addr -s 0x1000 -o w -r 0x20 -v 0x55AA -l $loop_count > ${T_LOG_PATH}/pcimem-test-$(date +"%y%m%d-%H-%M-%S")-$i.log
			else 
				taskset -c $core ./pcimem -m memio -b $base_addr -s 0x1000 -o w -r 0x20 -v 0x55AA -l $loop_count > ${T_LOG_PATH}/pcimem-test-$(date +"%y%m%d-%H-%M-%S")-$i.log &
			fi 
		done

		echo "Testing with $t_count threads..., and check the log in $T_LOG_PATH "
		sleep 20
	done

fi