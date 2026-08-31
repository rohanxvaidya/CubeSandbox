#!/bin/bash

#parameters:
# $1 service type, e.g. meta, storage, admin.
# $2 IP address,  specify the meta node IP, bydefault, use 1 meta node.
# $3 Disk counter,  
# $4 storage_node_ID,  only for storage node. 
IP_SEG="192.168.200"
META_IP="192.168.200.1"
NUM_STORAGE_NODES=${NUM_STORAGE_NODES:-"2"}
replicas=${replicas:-"2"}
min_targets_per_disk=


CLUSTER_ID="stage" 

echo "${META_IP} meta" >> /etc/hosts 

cd /home/3fs/configs
sed -i 's/max_sge = 16/max_sge = 1/g' `grep -rl max_sge`

# for storage ndoe:
echo "fs.aio-max-nr=67108864" >> /etc/sysctl.conf
sysctl -p

#functions to setup meta service.
function setup_fuse() {

}

#functions to test io with fio.
function test_io() {



}
