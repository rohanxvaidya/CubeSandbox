#!/bin/bash
#numactl -m 2 -C 64,65 ib_write_bw --report_gbits -D 10 -s 4096 -l 16 -t 1024 --recv_post_list 64 -q 1 -F --tclass 236 --wait_destroy 1 --ib-port 1 --bind_source_ip 192.168.0.2 -d rocep184s0 192.168.0.3  -p 18515 -R --run_infinitely --use_hugepages | while IFS= read -r line; do     echo [2026-03-06 12:48:23] 192.168.0.2/24; done 
#set -x
# test:
#IB_POST_LIST=16 IB_IO_SIZE=$((4*1024)) bash rdma_client.sh


post_list_size=${IB_POST_LIST:-16}
#io_size=4096
#io_size=$((4*1024))
io_size=${IB_IO_SIZE:-$((4*1024))}
tx_depth=${IB_W_TX_DEPTH:-1024}

server_mgmt_ip="10.239.12.232"
remote_ip="192.168.0.3"
cur_source_ip="192.168.0.2"
mkdir -p ./logs
log_file="./logs/rdma_ib_write_bw_output_$(date '+%Y-%m-%d-%H-%M-%S').log"
output_file=$(realpath $log_file)
#test_opts="-D ${duration_report} --use_hugepages --disable_pcie_relaxed"


#ib_write_bw_tool="ib_write_bw"
ib_write_bw_tool="/home/mz/tools/perftest_Core_no_ops/ib_write_bw"
server_tool="/home/mz/tools/perftest/ib_write_bw"
ib_dev=rocep184s0
duration_report=${R_TIME-:10}
core_bind=${IB_CORE:-"67,68"}
numa_bind="-m 2 -C ${core_bind}"

test_opts="-l ${post_list_size} -s ${io_size} -t ${tx_depth} -D ${duration_report} --use_hugepages --disable_pcie_relaxed"
echo "logging to file $output_file"


function start_server() {

echo -n "Start server, server version is:"
ssh root@${server_mgmt_ip} ${server_tool} --version
#ssh root@${server_ip} numactl -m 0 -C 0,1 /home/mz/tools/perftest/ib_write_bw --report_gbits -D 10 -s ${io_size} -l 16 -t 1024 --recv_post_list 64 -q 1 -F --tclass 236 --wait_destroy 1 --ib-port 1 --bind_source_ip 192.168.0.3 -d mlx5_0 --run_infinitely -p 18515 -R  --disable_pcie_relaxed

ssh root@${server_mgmt_ip} numactl -m 0 -C 0,1 /home/mz/tools/perftest/ib_write_bw --report_gbits ${test_opts} --recv_post_list 64 -q 1 -F --tclass 236 --wait_destroy 1 --ib-port 1 --bind_source_ip 192.168.0.3 -d mlx5_0 --run_infinitely -p 18515 -R  &
}

function start_client() {
echo "Start the test with tool: $ib_write_bw_tool ..."
echo "test parameters -- numa_cmd: [${numa_bind}],ib_write: [${test_opts}] "
#numactl -m 2 -C 64,65 ib_write_bw --report_gbits -D 10 -s 4096 -l 16 -t 1024 --recv_post_list 64 -q 1 -F --tclass 236 --wait_destroy 1 --ib-port 1 --bind_source_ip 192.168.0.2 -d rocep184s0 192.168.0.3  -p 18515 -R --run_infinitely ${test_opts} --disable_pcie_relaxed | while IFS= read -r line; do     echo "[$(date '+%Y-%m-%d %H:%M:%S')] $line"; done | tee ./logs/${output_file}
#numactl -m 2 -C 64,65 ib_write_bw --report_gbits -D 10 -s 4096 -l 16 -t 1024 --recv_post_list 64 -q 1 -F --tclass 236 --wait_destroy 1 --ib-port 1 --bind_source_ip 192.168.0.2 -d rocep184s0 192.168.0.3  -p 18515 -R --run_infinitely ${test_opts}  | while IFS= read -r line; do     echo "[$(date '+%Y-%m-%d %H:%M:%S')] $line"; done

#numactl ${numa_bind} ib_write_bw --report_gbits -s 4096 -l 16 -t 1024 --recv_post_list 64 -q 1 -F --tclass 236 --wait_destroy 1 --ib-port 1 --bind_source_ip 192.168.0.2 -d rocep184s0 192.168.0.3  -p 18515 -R --run_infinitely ${test_opts}  | while IFS= read -r line; do     echo "[$(date '+%Y-%m-%d %H:%M:%S')] $line"; done

#numactl ${numa_bind} ib_write_bw --report_gbits ${test_opts} --recv_post_list 64 -q 1 -F --tclass 236 --wait_destroy 1 --ib-port 1 --bind_source_ip 192.168.0.2 -d rocep184s0 192.168.0.3  -p 18515 -R --run_infinitely ${test_opts}  | while IFS= read -r line; do     echo "[$(date '+%Y-%m-%d %H:%M:%S')] $line"; done

echo "current IP : $cur_source_ip | Remote IP: $remote_ip"
$ib_write_bw_tool --version

taskset -c ${core_bind} $ib_write_bw_tool --report_gbits ${test_opts} --recv_post_list 64 -q 1 -F --tclass 236 --wait_destroy 1 --ib-port 1 --bind_source_ip 192.168.0.2 -d rocep184s0 192.168.0.3  -p 18515 -R --run_infinitely   | while IFS= read -r line; do     echo "[$(date '+%Y-%m-%d %H:%M:%S')] $line"; done

}

start_server;

sleep 1s

start_client | tee ${output_file}


