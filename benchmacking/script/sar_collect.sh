#!/bin/bash -e
rm -rf /tmp/sar_log
RES_REPO=/tmp/sar_log
# RES_REPO=$1+"/sar_log"
prefix="KUBEVIRT_SPDK"
mkdir -p $RES_REPO
start_collect() {
    # seconds for each static
    #prefix="RBD_IO_LOG"
    #timestamp=$(date +'%m%d%H%M')
    sleep 30
    seconds_per_monitor=5
    #time=12
    count=360
    (sar -P ALL $seconds_per_monitor $count >${RES_REPO}/${prefix}_sar-cpu-all.log) &
    (sar -u $seconds_per_monitor $count >${RES_REPO}/${prefix}_sar-cpu-uniq.log) &
    (sar -n DEV $seconds_per_monitor $count >${RES_REPO}/${prefix}_sar-net.log) &
    (sar -r $seconds_per_monitor $count >${RES_REPO}/${prefix}_sar-mem.log) &
    (sar -m CPU -P ALL $seconds_per_monitor $count >${RES_REPO}/${prefix}_sar-cpu-frequency.log) &
    (sar -d -p $seconds_per_monitor $count >${RES_REPO}/${prefix}_sar-io.log) &
    sleep $1
}
start_collect $1