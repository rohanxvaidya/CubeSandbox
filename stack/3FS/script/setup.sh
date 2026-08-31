#!/bin/bash
# $1 service type, e.g. meta, storage, admin.
# $2 Disk
# $3:
#   - storage_node_ID, only for storage node.
#   - Node_counter, for admin.

## e.g. 
## ./setup.sh meta ---> for start meta service.
## ./setup.sh storage 8 10001 ---> for start storage service, 8 disks, storage node_id=10001
## ./setup.sh admin 8 3 ---> for start admin service, 3 nodes, 8 disk per node.

RELICASREL=${RELICASREL:-"2"}
MIN_TARGETS_DISK=${MIN_TARGETS_DISK:-"4"}
META_IP=${META_IP:-"192.168.200.1"}
SRV_TYPE=${1:-"meta"}
DISK_COUNTER=${2:-"4"}
NODE_COUNTER=${3:-"4"}
STORAGE_NODE_ID=${3:-"10001"}
CLUSTER_ID="stage"
IP_SEG="192.168.200"
EXE_PATH="/opt/3fs/etc"
mkdir -p /opt/3fs/log
LOG="/opt/3fs/log"
echo "${META_IP} meta" >> /etc/hosts 
#cd /home/3fs/configs
#sed -i 's/max_sge = 16/max_sge = 1/g' `grep -rl max_sge`

function setup_admin_all_nodes() {

   # Update admin_cli.toml to set cluster_id and clusterFile
   sed -i "s|cluster_id =.*|cluster_id = 'stage'|" $EXE_PATH/admin_cli.toml
   sed -i "s|clusterFile =.*|clusterFile = '$EXE_PATH/fdb.cluster'|" $EXE_PATH/admin_cli.toml
   
   # The full help documentation for admin_cli can be displayed by running the following command
   /opt/3fs/bin/admin_cli -cfg /opt/3fs/etc/admin_cli.toml help | tee $LOG/help.log &
   sleep 5
}

#functions to setup meta service.
function setup_meta() {

   echo "start the clickhouse server..."
   clickhouse-server start &
   sleep 5s
   # Step 1: Create ClickHouse tables for metrics
   # Import the SQL file into ClickHouse:
   #clickhouse-client -n < /home/3fs/deploy/sql/3fs-monitor.sql
   echo "start the clickhouse client and import the SQL config..."
   clickhouse-client -n -u default  < /home/3fs/deploy/sql/3fs-monitor.sql
   sleep 4s 
   # Step 2: Monitor service
   # Update monitor_collector_main.toml to add a ClickHouse connection
   sed -i "s|^db =.*|db = '3fs'|" $EXE_PATH/monitor_collector_main.toml
   sed -i "s|^host =.*|host = '127.0.0.1'|" $EXE_PATH/monitor_collector_main.toml
   sed -i "s|^passwd =.*|passwd = ''|" $EXE_PATH/monitor_collector_main.toml
   sed -i "s|^port =.*|port = '9000'|" $EXE_PATH/monitor_collector_main.toml
   sed -i "s|^user =.*|user = 'default'|" $EXE_PATH/monitor_collector_main.toml
   sed -i "s|\$HOME|\/root|" /root/.profile
   # Start monitor service
   /opt/3fs/bin/monitor_collector_main --cfg /opt/3fs/etc/monitor_collector_main.toml &
   sleep 5
   # Step 3: Admin client
   # Install admin_cli
   setup_admin_all_nodes
   sleep 5
   # Step 4: Mgmtd service
   #Install mgmtd service on meta node
   # Set mgmtd node_id = 1 in mgmtd_main_app.toml
   sed -i "s|\<node_id\> =.*|node_id = 1|" $EXE_PATH/mgmtd_main_app.toml

   # Edit mgmtd_main_launcher.toml to set the cluster_id and clusterFile
   sed -i "s|\<cluster_id\> =.*|cluster_id = 'stage'|" $EXE_PATH/mgmtd_main_launcher.toml
   sed -i "0,/\<clusterFile\>/{s|\<clusterFile\> =.*|clusterFile = '$EXE_PATH/fdb.cluster'|}" $EXE_PATH/mgmtd_main_launcher.toml

   # Set monitor address in mgmtd_main.toml
   sed -i "s|\<remote_ip\> =.*|remote_ip = \"$META_IP:10000\"|" $EXE_PATH/mgmtd_main.toml

   # Initialize the cluster
   service foundationdb start
   /opt/3fs/bin/admin_cli -cfg /opt/3fs/etc/admin_cli.toml \
   "init-cluster --mgmtd /opt/3fs/etc/mgmtd_main.toml 1 1048576 16" &
   sleep 5
   # Start mgmtd service
   /opt/3fs/bin/mgmtd_main \
   --launcher_cfg /opt/3fs/etc/mgmtd_main_launcher.toml --app-cfg /opt/3fs/etc/mgmtd_main_app.toml &
   sleep 5
   # Run list-nodes command to check if the cluster has been successfully initialized:
   /opt/3fs/bin/admin_cli -cfg /opt/3fs/etc/admin_cli.toml \
   --config.mgmtd_client.mgmtd_server_addresses \
   '["RDMA://'$META_IP':8000"]' "list-nodes" | tee $LOG/list-nodes-.log &
   sleep 5
   #Step 5: Meta service
   # Install meta service on meta node. 
   # Set meta node_id = 100 in meta_main_app.toml
   # Set cluster_id, clusterFile and mgmtd address in meta_main_launcher.toml
   sed -i "s|\<node_id\> =.*|node_id = 100|" $EXE_PATH/meta_main_app.toml
   sed -i "s|\<cluster_id\> =.*|cluster_id = 'stage'|" $EXE_PATH/meta_main_launcher.toml
   sed -i "s|\<mgmtd_server_addresses\> =.*|mgmtd_server_addresses = \[\"RDMA://$META_IP:8000\"\]|" $EXE_PATH/meta_main_launcher.toml

   # Set mgmtd and monitor addresses in meta_main.toml
   sed -i "s|\<mgmtd_server_addresses\> =.*|mgmtd_server_addresses = \[\"RDMA://$META_IP:8000\"\]|" $EXE_PATH/meta_main.toml
   sed -i "s|\<remote_ip\> =.*|remote_ip = \"$META_IP:10000\"|" $EXE_PATH/meta_main.toml
   sed -i "0,/\<clusterFile\>/{s|\<clusterFile\> =.*|clusterFile = '$EXE_PATH/fdb.cluster'|}" $EXE_PATH/meta_main.toml

   # Config file of meta service is managed by mgmtd service. Use admin_cli to upload the config file to mgmtd
   /opt/3fs/bin/admin_cli -cfg /opt/3fs/etc/admin_cli.toml \
   --config.mgmtd_client.mgmtd_server_addresses \
   '["RDMA://'$META_IP':8000"]' "set-config --type META --file /opt/3fs/etc/meta_main.toml" &
   sleep 5
   # Start meta service
   #systemctl start meta_main
   /opt/3fs/bin/meta_main --launcher_cfg /opt/3fs/etc/meta_main_launcher.toml \
   --app-cfg /opt/3fs/etc/meta_main_app.toml &
   sleep 5
   # Run list-nodes command to check if meta service has joined the cluster
   /opt/3fs/bin/admin_cli -cfg /opt/3fs/etc/admin_cli.toml \
   --config.mgmtd_client.mgmtd_server_addresses '["RDMA://'$META_IP':8000"]' "list-nodes" | tee $LOG/list-nodes.log &


}


#functions to setup storage service on storage node.
function setup_storage_service() {
 
   # Step 6: Storage service
   # Install storage service on storage node.
   # 1.Format the attached 16 SSDs as XFS and mount at /storage/data{1..16}, then create data directories /storage/data{1..16}/3fs and log directory /var/log/3fs.
   mkdir -p /var/log/3fs
   # for i in {1..8};do umount /storage/data${i}; mkfs.xfs -f -L data${i} /dev/nvme${i}n1;mount -o noatime,nodiratime -L data${i} /storage/data${i};done 
   for i in `seq 1 $DISK_COUNTER`;
   do 
      mkdir -p /storage/data${i}
      umount /storage/data${i}
   done

   for i in `seq 1 $DISK_COUNTER`;
   do 
      mkfs.xfs -L data${i} -s size=4096 /dev/nvme${i}n1;

   done

   for i in `seq 1 $DISK_COUNTER`;
   do 
      mount -o noatime,nodiratime -L data${i} /storage/data${i};
      mkdir -p /storage/data${i}/3fs
   done

# remove this code, do it step by step, 
   # for i in `seq 1 $DISK_COUNTER`;
   # do 
   #    mkdir -p /storage/data${i}
   #    umount /storage/data${i}
   #    mkfs.xfs -L data${i} -s size=4096 /dev/nvme${i}n1;
   #    mount -o noatime,nodiratime -L data${i} /storage/data${i};
   #    mkdir -p /storage/data${i}/3fs
   # done

   sed -i "s|\$HOME|\/root|" /root/.profile
   # 2.Increase the max number of asynchronous aio requests
   echo "fs.aio-max-nr=67108864" >> /etc/sysctl.conf
   sysctl -p
   # Install admin_cli on all nodes
   setup_admin_all_nodes
   sleep 5
   # 4.Update config files
   # Set node_id in storage_main_app.toml. Each storage service is assigned a unique id between 10001 and 10005.
   # Set cluster_id and mgmtd address in storage_main_launcher.toml
   sed -i "s|\<node_id\> =.*|node_id = $STORAGE_NODE_ID|" $EXE_PATH/storage_main_app.toml
   sed -i "s|\<cluster_id\> =.*|cluster_id = 'stage'|" $EXE_PATH/storage_main_launcher.toml
   sed -i "s|\<mgmtd_server_addresses\> =.*|mgmtd_server_addresses = \[\"RDMA://$META_IP:8000\"\]|" $EXE_PATH/storage_main_launcher.toml

   # Add target paths in storage_main.toml
   sed -i "s|\<mgmtd_server_addresses\> =.*|mgmtd_server_addresses = \[\"RDMA://$META_IP:8000\"\]|" $EXE_PATH/storage_main.toml
   sed -i "s|\<remote_ip\> =.*|remote_ip = \"$META_IP:10000\"|" $EXE_PATH/storage_main.toml
   sed -i "s|target_paths =.*|target_paths = \[\]|" $EXE_PATH/storage_main.toml
   for i in `seq $DISK_COUNTER -1 1`;
   do
   sed -i "s|target_paths = \[|&\"/storage/data${i}/3fs\",|" $EXE_PATH/storage_main.toml
   done

   # Config file of storage service is managed by mgmtd service. Use admin_cli to upload the config file to mgmtd
   /opt/3fs/bin/admin_cli -cfg /opt/3fs/etc/admin_cli.toml --config.mgmtd_client.mgmtd_server_addresses \
   '["RDMA://'$META_IP':8000"]' "set-config --type STORAGE --file /opt/3fs/etc/storage_main.toml" &
   sleep 2
   # start storage service
   echo " To start storage main service..."
   /opt/3fs/bin/storage_main --launcher_cfg /opt/3fs/etc/storage_main_launcher.toml \
   --app-cfg /opt/3fs/etc/storage_main_app.toml &
   echo "starting storage main service..."
   sleep 10s
   # Run list-nodes command to check if storage service has joined the cluster
   /opt/3fs/bin/admin_cli -cfg /opt/3fs/etc/admin_cli.toml \
   --config.mgmtd_client.mgmtd_server_addresses '["RDMA://'$META_IP':8000"]' "list-nodes" | tee $LOG/list-nodes.log &
}

#functions to setup admin service.
function setup_admin() {
   i=`expr $NODE_COUNTER + 10001`
   node_id_end=`expr $i - 1`
   sed -i "s|\$HOME|\/root|" /root/.profile
   # Install admin_cli on all nodes
   setup_admin_all_nodes
   # if admin, --num_nodes 2 --replication_factor 2 --min_targets_per_disk 4
   # Step 7: Create admin user, storage targets and chain table
   # Create an admin user
   # The admin token is printed to the console, save it to /opt/3fs/etc/token.txt
   /opt/3fs/bin/admin_cli -cfg /opt/3fs/etc/admin_cli.toml \
   --config.mgmtd_client.mgmtd_server_addresses '["RDMA://'$META_IP':8000"]' "user-add --root --admin 0 root" > /opt/3fs/etc/user.txt
   sleep 2s
   ## TODO: generate token file: /opt/3fs/etc/token.txt
   token=$(grep -ri Token  /opt/3fs/etc/user.txt | sed 's/.*  //; s/(.*//')
   echo $token | tee /opt/3fs/etc/token.txt

   # Generate admin_cli commands to create storage targets on 5 storage nodes (16 SSD per node, 6 targets per SSD).
   # Follow instructions at here to install Python packages.
   python3 /home/3fs/deploy/data_placement/src/model/data_placement.py -ql -relax -type CR --num_nodes $NODE_COUNTER \
   --replication_factor $RELICASREL --min_targets_per_disk $MIN_TARGETS_DISK 2> $LOG/data_placement.log
   DPM_PATH=$(grep "saved solution to"  $LOG/data_placement.log | sed "s/.*to: //g")
   sleep 2
   python3 /home/3fs/deploy/data_placement/src/setup/gen_chain_table.py \
   --chain_table_type CR --node_id_begin 10001 --node_id_end $node_id_end \
   --num_disks_per_node ${DISK_COUNTER} --num_targets_per_disk 4 \
   --target_id_prefix 1 --chain_id_prefix 9 \
   --incidence_matrix_path ${DPM_PATH}/incidence_matrix.pickle
   sleep 3
   # Create storage targets
   /opt/3fs/bin/admin_cli --cfg /opt/3fs/etc/admin_cli.toml --config.mgmtd_client.mgmtd_server_addresses '["RDMA:/'$META_IP':8000"]' \
    --config.user_info.token $(<"/opt/3fs/etc/token.txt") < output/create_target_cmd.txt &
   sleep 5
   # Upload chains to mgmtd service
   /opt/3fs/bin/admin_cli --cfg /opt/3fs/etc/admin_cli.toml --config.mgmtd_client.mgmtd_server_addresses '["RDMA://'$META_IP':8000"]' \
   --config.user_info.token $(<"/opt/3fs/etc/token.txt") "upload-chains output/generated_chains.csv" &
   sleep 2
   # Upload chain table to mgmtd service
   /opt/3fs/bin/admin_cli --cfg /opt/3fs/etc/admin_cli.toml --config.mgmtd_client.mgmtd_server_addresses '["RDMA://'$META_IP':8000"]' \
   --config.user_info.token $(<"/opt/3fs/etc/token.txt") "upload-chain-table --desc stage 1 output/generated_chain_table.csv" &
   sleep 2
   # List chains and chain tables to check if they have been correctly uploaded
   /opt/3fs/bin/admin_cli -cfg /opt/3fs/etc/admin_cli.toml \
   --config.mgmtd_client.mgmtd_server_addresses '["RDMA://'$META_IP':8000"]' "list-chains" | tee $LOG/list-chains.log &
   sleep 1
   /opt/3fs/bin/admin_cli -cfg /opt/3fs/etc/admin_cli.toml \
   --config.mgmtd_client.mgmtd_server_addresses '["RDMA://'$META_IP':8000"]' "list-chain-tables"| tee $LOG/list-chain-tables.log &
   
}

#functions to setup fuse service.
function setup_fuse() {
   sed -i "s|\$HOME|\/root|" /root/.profile
   # Install admin_cli on all nodes
   setup_admin_all_nodes
   # Create the mount point
   mkdir -p /3fs/stage

   # Set cluster ID, mountpoint, token file and mgmtd address in hf3fs_fuse_main_launcher.toml
   sed -i "s|\<cluster_id\> =.*|cluster_id = 'stage'|" $EXE_PATH/hf3fs_fuse_main_launcher.toml
   sed -i "s|\<mountpoint\> =.*|mountpoint = '/3fs/stage'|" $EXE_PATH/hf3fs_fuse_main_launcher.toml
   sed -i "s|\<token_file\> =.*|token_file = '/opt/3fs/etc/token.txt'|" $EXE_PATH/hf3fs_fuse_main_launcher.toml
   sed -i "s|\<mgmtd_server_addresses\> =.*|mgmtd_server_addresses = \[\"RDMA://$META_IP:8000\"\]|" $EXE_PATH/hf3fs_fuse_main_launcher.toml

   # Set mgmtd and monitor address in hf3fs_fuse_main.toml
   sed -i "s|\<mgmtd_server_addresses\> =.*|mgmtd_server_addresses = \[\"RDMA://$META_IP:8000\"\]|" $EXE_PATH/hf3fs_fuse_main.toml
   sed -i "s|\<remote_ip\> =.*|remote_ip = \"$META_IP:10000\"|" $EXE_PATH/hf3fs_fuse_main.toml

   # Config file of FUSE client is also managed by mgmtd service. Use admin_cli to upload the config file to mgmtd
   /opt/3fs/bin/admin_cli -cfg /opt/3fs/etc/admin_cli.toml \
   --config.mgmtd_client.mgmtd_server_addresses '["RDMA://'$META_IP':8000"]' "set-config --type FUSE --file /opt/3fs/etc/hf3fs_fuse_main.toml" &
   sleep 5

   # Start FUSE client
   /opt/3fs/bin/hf3fs_fuse_main --launcher_cfg /opt/3fs/etc/hf3fs_fuse_main_launcher.toml &

}

if [ $SRV_TYPE == "meta" ]; then
   echo "setup meta"
   setup_meta

elif [ $SRV_TYPE == "storage" ]; then
   if [[ ! $2 || ! $3 ]]; then
      echo "Enter Disk Counter, Storage_Node_Id."
   else
      echo "setup storage service"
      setup_storage_service
   fi
elif [ $SRV_TYPE == "admin" ]; then 
   if [ ! $2 ]; then
      echo "Enter Node Counter."
   else
      echo "setup admin"
      setup_admin
   fi
elif [ $SRV_TYPE == "fuse" ]; then
   echo "setup fuse"
   setup_fuse
else
   echo "Invalid option."
   echo "Enter server type as meta, storage, admin."
fi

