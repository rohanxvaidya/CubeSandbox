#!/bin/bash -e
set -x
# $1: test_operation
# $2: test_time
TEST_REPO=/home/vmscaling
RES_REPO=$TEST_REPO/$3
WORK_DIR=/home/vmscaling
prefix=$3
NODE1="192.168.88.56"
NODE2="192.168.88.157"
NODE3="192.168.88.71"
start_collect() {
    # seconds for each static
    #prefix="RBD_IO_LOG"
    #timestamp=$(date +'%m%d%H%M')
    sleep 300
    seconds_per_monitor=5
    #time=12
    count=180
    (top -c -b -d5 | grep -iE 'ceph|fio|kubelet|reactor|qemu|vhost' >$RES_REPO/$1/$2/node-top.log) &
    TOP_PID=`ps -ef |grep "top -c -b -d5" |grep -v grep |awk '{print$2}'`
    (sar -P ALL $seconds_per_monitor $count >${RES_REPO}/$1/$2/${prefix}_sar-cpu-all.log) &
    (sar -u $seconds_per_monitor $count >${RES_REPO}/$1/$2/${prefix}_sar-cpu-uniq.log) &
    (sar -n DEV $seconds_per_monitor $count >${RES_REPO}/$1/$2/${prefix}_sar-net.log) &
    (sar -r $seconds_per_monitor $count >${RES_REPO}/$1/$2/${prefix}_sar-mem.log) &
    (sar -m CPU -P ALL $seconds_per_monitor $count >${RES_REPO}/$1/$2/${prefix}_sar-cpu-frequency.log) &
    (sar -d -p $seconds_per_monitor $count >${RES_REPO}/$1/$2/${prefix}_sar-io.log) &
    sleep 1200
    kill -9 $TOP_PID
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
for num_line in $(seq 1 $2)
do
        num=$(($num_line + 1))
        VM_IP_ADDR=$(kubectl get vmi -A | awk 'NR=="'"$num"'"{print $5}')
        while [ -z "`kubectl -n $NAMESPACE exec -it $OPERATOR -- ssh -o StrictHostKeyChecking=no -l root $VM_IP_ADDR "ps -ef |grep "$1" |grep -v grep"`" ]; do
                sleep 2
        done
done
mkdir -p $RES_REPO/$1/$2

(start_collect $1 $2) &
(ssh root@$NODE2 "bash $WORK_DIR/autotest-node.sh $1 $2 $3") &
(ssh root@$NODE3 "bash $WORK_DIR/autotest-node.sh $1 $2 $3") &
sleep 250s
for duration in {1..40..1}
do
 for num_line in $(seq 1 $2)
 do
                num=$(($num_line + 1))
                VM_IP_ADDR=$(kubectl get vmi -A | awk 'NR=="'"$num"'"{print $5}')
                kubectl -n $NAMESPACE exec -it $OPERATOR -- ssh -t -o StrictHostKeyChecking=no -l root $VM_IP_ADDR "top -n 1" >>${RES_REPO}/$1/$2/${prefix}_${num_line}_vm_top.log
 done
 sleep 20s
done
# (start_collect $1 $2) &
exit 0
echo "++++++++++++++++++All Complete!+++++++++++++++++++"

