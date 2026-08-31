#! /bin/bash -e
set -x
TEST_REPO=/home/fio_data
while true;do

  if [ ! -f "$TEST_REPO/vm1.info" ];then
  echo "vm1.info文件不存在"
  else
  NAMESPACE=`cat $TEST_REPO/vm1.info|grep NAMESPACE=|awk -F= {'print$2'}`
  OPERATOR=`cat $TEST_REPO/vm1.info|grep OPERATOR=|awk -F= {'print$2'}`
  VM_IP_1=`cat $TEST_REPO/vm1.info|grep VM_IP=|awk -F= {'print$2'}`
  sleep 1s
  kubectl -n $NAMESPACE exec -it $OPERATOR -- ssh -t -o StrictHostKeyChecking=no -l root $VM_IP_1 "top -n 1 | grep -iE fio >>/logs/node2_vm_top.log"
  fi
  if [ ! -f "$TEST_REPO/vm2.info" ];then
  echo "vm2.info文件不存在"
  else
  NAMESPACE=`cat $TEST_REPO/vm2.info|grep NAMESPACE=|awk -F= {'print$2'}`
  OPERATOR=`cat $TEST_REPO/vm2.info|grep OPERATOR=|awk -F= {'print$2'}`
  VM_IP_2=`cat $TEST_REPO/vm2.info|grep VM_IP=|awk -F= {'print$2'}`
  sleep 1s
  kubectl -n $NAMESPACE exec -it $OPERATOR -- ssh -t -o StrictHostKeyChecking=no -l root $VM_IP_2 "top -n 1 | grep -iE fio >>/logs/node1_vm_top.log"
  fi
  if [ ! -f "$TEST_REPO/vm3.info" ];then
  echo "vm3.info文件不存在"
  else
  NAMESPACE=`cat $TEST_REPO/vm3.info|grep NAMESPACE=|awk -F= {'print$2'}`
  OPERATOR=`cat $TEST_REPO/vm3.info|grep OPERATOR=|awk -F= {'print$2'}`
  VM_IP_3=`cat $TEST_REPO/vm3.info|grep VM_IP=|awk -F= {'print$2'}`
  sleep 1s
  kubectl -n $NAMESPACE exec -it $OPERATOR -- ssh -t -o StrictHostKeyChecking=no -l root $VM_IP_3 "top -n 1 | grep -iE fio >>/logs/node3_vm_top.log"
  fi
sleep 20s

done

###############

# while [ -z "$(kubectl -n kubevirt get kubevirt.kubevirt.io/kubevirt -o=jsonpath="{.status.phase}" | grep -i Deployed)" ]; do
#    sleep 10s
# done
# for i in {1..5..1}
# do
