#! /bin/bash -e
set -x

WORK_DIR=/home/fio_data
CTEST_PATH=/home/fio_data/wsf_perf_test/build/workload/Edge-Ceph-VirtIO
TEST_OPERATION=sequential_write    # Must keep the same as the workload test case name

for i in {1..10..1}
do
  cd $CTEST_PATH
  (bash $WORK_DIR/autotest.sh ${TEST_OPERATION} $i kubevirt_vhost) &
  ctest -R test_edge_ceph_virtio_block_vhost_${TEST_OPERATION} -V
  for logs in `find $CTEST_PATH/ -name "ubuntu*"`
  do
    cp -r $logs $WORK_DIR/kubevirt_vhost/${TEST_OPERATION}/$i/
  done
  rm -rf logs-edge_ceph_vhost_block*
  ssh root@192.168.88.56 'sync; echo 3 > /proc/sys/vm/drop_caches ' && ssh root@192.168.88.157 'sync; echo 3 > /proc/sys/vm/drop_caches '
done


for i in {1..10..1}
do
  cd $CTEST_PATH
  (bash $WORK_DIR/autotest.sh ${TEST_OPERATION} $i kubevirt_virtio) &
  ctest -R test_edge_ceph_virtio_block_vm_${TEST_OPERATION} -V
  for logs in `find $CTEST_PATH/ -name "ubuntu*"`
  do
    cp -r $logs $WORK_DIR/kubevirt_virtio/${TEST_OPERATION}/$i/
  done
  rm -rf logs-edge_ceph_virtio_block*
  ssh root@192.168.88.56 'sync; echo 3 > /proc/sys/vm/drop_caches ' && ssh root@192.168.88.157 'sync; echo 3 > /proc/sys/vm/drop_caches '
done

