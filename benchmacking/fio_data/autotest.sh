#!/bin/bash -e
set -x
# $1: test_operation
# $2: test_time
TEST_REPO=/home/fio_data
RES_REPO=$TEST_REPO
prefix=""
NODE1="192.168.88.56"
NODE2="192.168.88.157"
NODE3="192.168.88.71"
prefill=1
node1_hostname=`ssh root@$NODE1 hostname`
node2_hostname=`ssh root@$NODE2 hostname`
node3_hostname=`ssh root@$NODE3 hostname`
duration="1900s"
rm -rf $TEST_REPO/vm*.info
# 难点是fio不是同时启动，prefill结束时间点不一致

trigger_1() {
        a1=`echo $1| awk -F "_" '{print $2}'`
        a2=`echo $1| awk -F "_" '{print $3}'`
        fio_name=$a1\_$a2
        echo $fio_name
        while [ -z "`kubectl -n $NAMESPACE exec -it $OPERATOR -- ssh -o StrictHostKeyChecking=no -l root $VM_IP_ADDR_node1 "ps -ef |grep "$fio_name" |grep -v grep"`" ]; do
                sleep 2
        done
        # (ssh root@$NODE1 "bash /home/fio_data/autotest.sh $1 $2 $3") &
        echo "start trigger_1"
        echo "NAMESPACE="$NAMESPACE > $TEST_REPO/vm1.info
        echo "OPERATOR="$OPERATOR >> $TEST_REPO/vm1.info
        echo "VM_IP="$VM_IP_ADDR_node1 >> $TEST_REPO/vm1.info

        while [ -z "`kubectl -n $NAMESPACE exec -it $OPERATOR -- ssh -o StrictHostKeyChecking=no -l root $VM_IP_ADDR_node2 "ps -ef |grep "$fio_name" |grep -v grep"`" ]; do
                sleep 2
        done
        echo "start trigger_2"
        echo "NAMESPACE="$NAMESPACE > $TEST_REPO/vm2.info
        echo "OPERATOR="$OPERATOR >> $TEST_REPO/vm2.info
        echo "VM_IP="$VM_IP_ADDR_node2 >> $TEST_REPO/vm2.info

        while [ -z "`kubectl -n $NAMESPACE exec -it $OPERATOR -- ssh -o StrictHostKeyChecking=no -l root $VM_IP_ADDR_node3 "ps -ef |grep "$fio_name" |grep -v grep"`" ]; do
                sleep 2
        done
        echo "start trigger_3"
        echo "NAMESPACE="$NAMESPACE > $TEST_REPO/vm3.info
        echo "OPERATOR="$OPERATOR >> $TEST_REPO/vm3.info
        echo "VM_IP="$VM_IP_ADDR_node3 >> $TEST_REPO/vm3.info

        ( cd $TEST_REPO/Storage-performance-analysis && ./run.sh --telem  --delay_run=5s --duration=$duration --logpath=$TEST_REPO/$1/$2/ ) &
        # start_collect $1 $2 &
        # for i in {1..90..1}
        # do
        # kubectl -n $NAMESPACE exec -it $OPERATOR -- ssh -t -o StrictHostKeyChecking=no -l root $VM_IP_ADDR_56 "top -n 1 | grep -iE fio >>/logs/node1_vm_top.log"

        # sleep 20s
        # done
        # kubectl -n $NAMESPACE exec -it $OPERATOR -- ssh -t -o StrictHostKeyChecking=no -l root $VM_IP_ADDR_56 "timeout 1800s top -b -d20 | grep -iE 'ceph|fio|kubelet|reactor|qemu|vhost|build'" >$RES_REPO/$1/$2/$VM_IP_ADDR_56_vm_top.log &
        
}


while [ -z "$(kubectl -n kubevirt get kubevirt.kubevirt.io/kubevirt -o=jsonpath="{.status.phase}" | grep -i Deployed)" ]; do
   sleep 1s
done
sleep 10s

while (! kubectl wait --for=condition=ready vmi -A --all --timeout=2000s); do
        sleep 3s
done

if [ $prefill == 1 ];then
echo "Wait prefill,sleeping..."
for ss in {1..15..1};do
sleep 60s
echo "$ss..."
done
fi


NAMESPACE=$(kubectl get po -A -o wide |grep ceph-benchmark |awk '{print $1}')
OPERATOR=$(kubectl get po -n $NAMESPACE |grep edge-ceph-benchmark |awk '{print$1}')

VM_IP_ADDR_node1=$(kubectl get vmi -n $NAMESPACE |grep $node1_hostname |awk '{print$4}')
VM_IP_ADDR_node2=$(kubectl get vmi -n $NAMESPACE |grep $node2_hostname |awk '{print$4}')
VM_IP_ADDR_node3=$(kubectl get vmi -n $NAMESPACE |grep $node3_hostname |awk '{print$4}')


mkdir -p $RES_REPO/$1/$2

(trigger_1 $1 $2 ) 

# (start_collect $1 $2) &
# for i in {1..90..1}
# do
# kubectl -n $NAMESPACE exec -it $OPERATOR -- ssh -t -o StrictHostKeyChecking=no -l root $VM_IP_ADDR_56 "top -n 1 | grep -iE fio >>/logs/node1_vm_top.log"
# kubectl -n $NAMESPACE exec -it $OPERATOR -- ssh -t -o StrictHostKeyChecking=no -l root $VM_IP_ADDR_157 "top -n 1 | grep -iE fio >>/logs/node2_vm_top.log"
# kubectl -n $NAMESPACE exec -it $OPERATOR -- ssh -t -o StrictHostKeyChecking=no -l root $VM_IP_ADDR_71 "top -n 1 | grep -iE fio >>/logs/node3_vm_top.log"
# sleep 20s
# done
exit 0
echo "++++++++++++++++++All Complete!+++++++++++++++++++"

