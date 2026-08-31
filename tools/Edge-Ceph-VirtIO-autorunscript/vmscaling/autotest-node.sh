#!/bin/bash -e
set -x
# $1: test_operation
# $2: test_time
TEST_REPO=/home/vmscaling
RES_REPO=$TEST_REPO/$3
prefix=$3
NODE1="192.168.88.157"
NODE2="192.168.88.71"
start_collect() {
    # seconds for each static
    #prefix="RBD_IO_LOG"
    #timestamp=$(date +'%m%d%H%M')
    sleep 300
    seconds_per_monitor=5
    #time=12
    count=180
    (timeout 1200s top -b -d5 | grep -iE 'ceph|fio|kubelet|reactor|qemu|vhost' >$RES_REPO/$1/$2/node-top.log) &
    TOP_PID=`ps -ef |grep "top -b -d5" |grep -v grep |awk '{print$2}'`
    (sar -P ALL $seconds_per_monitor $count >${RES_REPO}/$1/$2/${prefix}_sar-cpu-all.log) &
    (sar -u $seconds_per_monitor $count >${RES_REPO}/$1/$2/${prefix}_sar-cpu-uniq.log) &
    (sar -n DEV $seconds_per_monitor $count >${RES_REPO}/$1/$2/${prefix}_sar-net.log) &
    (sar -r $seconds_per_monitor $count >${RES_REPO}/$1/$2/${prefix}_sar-mem.log) &
    (sar -m CPU -P ALL $seconds_per_monitor $count >${RES_REPO}/$1/$2/${prefix}_sar-cpu-frequency.log) &
    (sar -d -p $seconds_per_monitor $count >${RES_REPO}/$1/$2/${prefix}_sar-io.log) &
    sleep 1200
    kill -9 $TOP_PID
}

mkdir -p $RES_REPO/$1/$2

(start_collect $1 $2)
#echo 32768 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
exit 0
echo "++++++++++++++++++All Complete!+++++++++++++++++++"
