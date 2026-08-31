#!/bin/bash -e
set -x
TEST_REPO=/home/fio_data
RES_REPO=$TEST_REPO/$3
prefix=$3


start_collect() {
    # seconds for each static
    #prefix="RBD_IO_LOG"
    #timestamp=$(date +'%m%d%H%M')
    sleep 300
    seconds_per_monitor=5
    #time=12
    count=360
    (top -c -b -d5 | grep -iE 'ceph|fio|kubelet|reactor' >$RES_REPO/$1/$2/node-top.log) &
    (sar -P ALL $seconds_per_monitor $count >${RES_REPO}/$1/$2/${prefix}_sar-cpu-all.log) &
    (sar -u $seconds_per_monitor $count >${RES_REPO}/$1/$2/${prefix}_sar-cpu-uniq.log) &
    (sar -n DEV $seconds_per_monitor $count >${RES_REPO}/$1/$2/${prefix}_sar-net.log) &
    (sar -r $seconds_per_monitor $count >${RES_REPO}/$1/$2/${prefix}_sar-mem.log) &
    (sar -m CPU -P ALL $seconds_per_monitor $count >${RES_REPO}/$1/$2/${prefix}_sar-cpu-frequency.log) &
    (sar -d -p $seconds_per_monitor $count >${RES_REPO}/$1/$2/${prefix}_sar-io.log) &
    sleep 1800
}

mkdir -p $RES_REPO/$1/$2
(start_collect $1 $2)
exit 0
echo "++++++++++++++++++All Complete!+++++++++++++++++++"

