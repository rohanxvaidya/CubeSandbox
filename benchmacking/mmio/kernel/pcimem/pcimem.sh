#!/bin/bash

# #1 = start or not, 1/0
# $2 = offset value , e.g. 0x8000
# $3 = loop count, used to loop operation
# $4 = operaton , read or write
# $5 = value if it's write.

SYSFS_PATH="/sys/kernel/pcimem/"

start=$1
offset=$2
loop=${3:-"1"}
operation=${4:-"read"}
value=$5

echo $loop > ${SYSFS_PATH}/loop_count
sleep 0.2s
echo $operation > ${SYSFS_PATH}/ops
sleep 0.2s
echo $offset > ${SYSFS_PATH}/offset

sleep 0.2s
if [ "${operation}" == "write" ]; then
    echo $value > ${SYSFS_PATH}/value
fi

sleep 0.5s

echo $start > ${SYSFS_PATH}/start

# maybe should sleep more time..
sleep 5s ## 
echo "output logs:"
dmesg | grep "TSC duration" | tail -${loop}