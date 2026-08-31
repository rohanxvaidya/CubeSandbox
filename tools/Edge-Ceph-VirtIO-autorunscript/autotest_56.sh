#!/bin/bash -e
set -x
# $1: test_operation
# $2: test_time
# $3: test case
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
    TOP_PID=`ps -ef |grep "top -c -b -d5" |grep -v grep |awk '{print$2}'`
    (sar -P ALL $seconds_per_monitor $count >${RES_REPO}/$1/$2/${prefix}_sar-cpu-all.log) &
    (sar -u $seconds_per_monitor $count >${RES_REPO}/$1/$2/${prefix}_sar-cpu-uniq.log) &
    (sar -n DEV $seconds_per_monitor $count >${RES_REPO}/$1/$2/${prefix}_sar-net.log) &
    (sar -r $seconds_per_monitor $count >${RES_REPO}/$1/$2/${prefix}_sar-mem.log) &
    (sar -m CPU -P ALL $seconds_per_monitor $count >${RES_REPO}/$1/$2/${prefix}_sar-cpu-frequency.log) &
    (sar -d -p $seconds_per_monitor $count >${RES_REPO}/$1/$2/${prefix}_sar-io.log) &
    sleep 1800
    kill -9 $TOP_PID
}


trigger_1() {
        while [ -z "`kubectl -n $NAMESPACE exec -it $OPERATOR -- ssh -o StrictHostKeyChecking=no -l root $VM_IP_ADDR_56 "ps -ef |grep "$1" |grep -v grep"`" ]; do
                sleep 2
        done

        start_collect $1 $2
}

trigger_2() {
        while [ -z "`kubectl -n $NAMESPACE exec -it $OPERATOR -- ssh -o StrictHostKeyChecking=no -l root $VM_IP_ADDR_157 "ps -ef |grep "$1" |grep -v grep"`" ]; do
                sleep 2
        done
        (ssh root@192.168.88.157 "bash /home/fio_data/autotest.sh $1 $2 $3") &
}


while [ -z "$(kubectl -n kubevirt get kubevirt.kubevirt.io/kubevirt -o=jsonpath="{.status.phase}" | grep -i Deployed)" ]; do
   sleep 1s
done
sleep 10s
while (! kubectl wait --for=condition=ready vmi -A --all --timeout=2000s); do
        sleep 3s
done


sleep 10s
NAMESPACE=$(kubectl get po -A -o wide |grep ceph-benchmark |awk '{print $1}')
OPERATOR=$(kubectl get po -n $NAMESPACE |grep edge-ceph-benchmark |awk '{print$1}')

VM_IP_ADDR_56=$(kubectl get vmi -n $NAMESPACE |grep ceph56 |awk '{print$4}')
VM_IP_ADDR_157=$(kubectl get vmi -n $NAMESPACE |grep ceph157 |awk '{print$4}')


mkdir -p $RES_REPO/$1/$2


(trigger_1 $1 $2) &
(trigger_2 $1 $2 $3) &
exit 0
echo "++++++++++++++++++All Complete!+++++++++++++++++++"

