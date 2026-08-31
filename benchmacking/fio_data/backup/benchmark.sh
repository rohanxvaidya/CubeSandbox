#! /bin/bash -e
set -x
NODE1="192.168.88.56"
NODE2="192.168.88.157"
NODE3="192.168.88.71"
# TIME_H=8   #UTC 8点
# TIME_d=26  #UTC 26号
WORK_DIR=/home/fio_data
#CTEST_PATH=$WORK_DIR/WSF_VHOST_IOPERF/build/workload/Edge-Ceph-VirtIO
#CTEST_PATH=/home/sfdev/sf/pr_addmessage/applications.benchmarking.benchmark.platform-hero-features/build/workload/Edge-Ceph-VirtIO
# CTEST_PATH=/home/fio_data/wsf_perf_test/build/workload/Edge-Ceph-VirtIO
CTEST_PATH=/home/wsf_test_1207/build/workload/Edge-Ceph-VirtIO
ssh root@$NODE1 mkdir -p $WORK_DIR
ssh root@$NODE2 mkdir -p $WORK_DIR
ssh root@$NODE3 mkdir -p $WORK_DIR
scp -r *.sh root@$NODE1:$WORK_DIR
scp -r *.sh root@$NODE2:$WORK_DIR
scp -r *.sh root@$NODE3:$WORK_DIR

TEST_OPERATION_list=(
vm_random_read
vm_sequential_read
vm_random_write
vm_sequential_write

vhost_random_read
vhost_sequential_read
vhost_random_write
vhost_sequential_write
)
case_name=(
  99
  # 1
  # 2
  # 3
  # 4
  # 5
)
# virtIO_test=1
# vhost_test=1
VM_catch_top=0

#   start  code   #############
if [ $VM_catch_top == 1 ];then
tmux new -d -s catch_top
tmux send-keys -t catch_top.0 "bash $WORK_DIR/VM_catch_top.sh" ENTER
fi

for TEST_OPERATION in ${TEST_OPERATION_list[@]};do
echo $TEST_OPERATION
#TEST_OPERATION=sequential_read    # Must keep the same as the workload test case name
# TEST_OPERATION=random_read 

  for i in ${case_name[@]}
  do
  mkdir -p $WORK_DIR/${TEST_OPERATION}/$i/node1log
  mkdir -p $WORK_DIR/${TEST_OPERATION}/$i/node2log
  mkdir -p $WORK_DIR/${TEST_OPERATION}/$i/node3log
  ssh root@$NODE1 'sync; echo 3 > /proc/sys/vm/drop_caches ' && ssh root@$NODE2 'sync; echo 3 > /proc/sys/vm/drop_caches ' && ssh root@$NODE3 'sync; echo 3 > /proc/sys/vm/drop_caches '
  if [ $(cat $WORK_DIR/continue.txt) == 0 ];then
    exit 1
  fi
  ceph -s>> $WORK_DIR/${TEST_OPERATION}/$i/time_bk
  ceph osd df >> $WORK_DIR/${TEST_OPERATION}/$i/time_bk
  echo "-----------">> $WORK_DIR/${TEST_OPERATION}/$i/time_bk
  echo "start">> $WORK_DIR/${TEST_OPERATION}/$i/time_bk
  date >> $WORK_DIR/${TEST_OPERATION}/$i/time_bk
  cd $CTEST_PATH
  (bash $WORK_DIR/autotest.sh ${TEST_OPERATION} $i ) &
  #  (ssh root@$NODE2 "bash $WORK_DIR/autotest.sh ${TEST_OPERATION} $i kubevirt_virtio") & 
  #  (ssh root@$NODE3 "bash $WORK_DIR/autotest.sh ${TEST_OPERATION} $i kubevirt_virtio") &
  ctest -R test_edge_ceph_virtio_block_${TEST_OPERATION} -V -E pkm
  for logs in `find $CTEST_PATH/ -name "ubuntu*"`
  do
    cp -r $logs $WORK_DIR/${TEST_OPERATION}/$i/
  done
  rm -rf logs-*


  scp -r root@$NODE1:$WORK_DIR/${TEST_OPERATION}/$i/*.log   $WORK_DIR/${TEST_OPERATION}/$i/node1log
  scp -r root@$NODE2:$WORK_DIR/${TEST_OPERATION}/$i/*.log   $WORK_DIR/${TEST_OPERATION}/$i/node2log
  scp -r root@$NODE3:$WORK_DIR/${TEST_OPERATION}/$i/*.log   $WORK_DIR/${TEST_OPERATION}/$i/node3log
  rm -rf $WORK_DIR/${TEST_OPERATION}/$i/*.log
  echo "end">> $WORK_DIR/${TEST_OPERATION}/$i/time_bk
  date >> $WORK_DIR/${TEST_OPERATION}/$i/time_bk
  echo "-----------">> $WORK_DIR/${TEST_OPERATION}/$i/time_bk
  ceph -s>> $WORK_DIR/${TEST_OPERATION}/$i/time_bk
  ceph osd df >> $WORK_DIR/${TEST_OPERATION}/$i/time_bk
  done
done
