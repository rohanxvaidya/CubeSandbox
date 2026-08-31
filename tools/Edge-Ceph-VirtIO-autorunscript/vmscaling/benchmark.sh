#! /bin/bash -e
set -x
NODE1="192.168.88.56"
NODE2="192.168.88.157"
NODE3="192.168.88.71"
TIME_H=8   #UTC 8点
TIME_d=0  #UTC 26号
WORK_DIR=/home/vmscaling
#CTEST_PATH=$WORK_DIR/WSF_VHOST_IOPERF/build/workload/Edge-Ceph-VirtIO
#CTEST_PATH=/home/sfdev/sf/pr_addmessage/applications.benchmarking.benchmark.platform-hero-features/build/workload/Edge-Ceph-VirtIO
CTEST_PATH=/home/vmscaling/wsf_yd/build/workload/Edge-Ceph-VirtIO
# TEST_CASE: kubevirt_virtio/kubevirt_vhost
TEST_CASE=kubevirt_virtio
# CTEST_CASE: vm/vhost
CTEST_CASE=vm
if [ $TEST_CASE == "kubevirt_virtio" ];then
  CTEST_CASE=vm
else 
  CTEST_CASE=vhost
fi
LOG_DIR=virtio_vmscaling_logs_12_14_2022
ssh root@$NODE1 mkdir -p $WORK_DIR
ssh root@$NODE2 mkdir -p $WORK_DIR
ssh root@$NODE3 mkdir -p $WORK_DIR

scp -r *.sh root@$NODE1:$WORK_DIR
scp -r *.sh root@$NODE2:$WORK_DIR
scp -r *.sh root@$NODE3:$WORK_DIR



########
#virtio case

TEST_OPERATION=random_read
# i : vm nums
# run_time : test round of each vm scaling case
for i in {1..8..1}
do
 for run_time in {1..3..1}
 do
  mkdir -p /home/vmscaling_log/$LOG_DIR/$i/$run_time

  mkdir -p $WORK_DIR/$TEST_CASE/${TEST_OPERATION}/$i/node1log
  mkdir -p $WORK_DIR/$TEST_CASE/${TEST_OPERATION}/$i/node2log
  mkdir -p $WORK_DIR/$TEST_CASE/${TEST_OPERATION}/$i/node3log
  if [ `date +%H` -gt $TIME_H ] && [ `date +%d` -eq $TIME_d ];then
     echo "time is up">>$WORK_DIR/$TEST_CASE/${TEST_OPERATION}/$i/time_bk
  fi
  echo "start">> $WORK_DIR/$TEST_CASE/${TEST_OPERATION}/$i/time_bk
  date >> $WORK_DIR/$TEST_CASE/${TEST_OPERATION}/$i/time_bk
  cd $CTEST_PATH
  (BENCHMARK_CLIENT_NODES=$i RBD_IMAGE_NUM=1 VHOST_CPU_NUM=1 TEST_DURATION=900 VM_CPU_NUM=2 VM_HUGEMEM="4Gi" ctest -R test_edge_ceph_virtio_block_${CTEST_CASE}_${TEST_OPERATION} -V) &
  bash $WORK_DIR/autotest.sh ${TEST_OPERATION} $i $TEST_CASE
while [ -n "$(ps -ef | grep ctest | grep -v grep)" ]; do
        echo ctesting...
        sleep 10s
done
  echo stop_ctest...
  for logs in `find $CTEST_PATH/ -name "ubuntu*"`
  do
        cp -r $logs $WORK_DIR/$TEST_CASE/${TEST_OPERATION}/$i/
  done
  rm -rf logs-edge*;
  ssh root@$NODE1 'sync; echo 3 > /proc/sys/vm/drop_caches ' && ssh root@$NODE2 'sync; echo 3 > /proc/sys/vm/drop_caches ' && ssh root@$NODE3 'sync; echo 3 > /proc/sys/vm/drop_caches ';
  scp -r root@$NODE1:$WORK_DIR/$TEST_CASE/${TEST_OPERATION}/$i/*.log   $WORK_DIR/$TEST_CASE/${TEST_OPERATION}/$i/node1log;
  scp -r root@$NODE2:$WORK_DIR/$TEST_CASE/${TEST_OPERATION}/$i/*.log   $WORK_DIR/$TEST_CASE/${TEST_OPERATION}/$i/node2log;
  scp -r root@$NODE3:$WORK_DIR/$TEST_CASE/${TEST_OPERATION}/$i/*.log   $WORK_DIR/$TEST_CASE/${TEST_OPERATION}/$i/node3log;
  rm -rf $WORK_DIR/$TEST_CASE/${TEST_OPERATION}/$i/*.log;
  echo "end">> $WORK_DIR/$TEST_CASE/${TEST_OPERATION}/$i/time_bk;
  date >> $WORK_DIR/$TEST_CASE/${TEST_OPERATION}/$i/time_bk;
  echo "-----------">> $WORK_DIR/$TEST_CASE/${TEST_OPERATION}/$i/time_bk;
  cp -r $WORK_DIR/$TEST_CASE/${TEST_OPERATION}/$i /home/vmscaling_log/$LOG_DIR/$i/$run_time;

 done
done





