#!/bin/bash
#--------------------------------------------------------------------------------
#   Test project /home/raspadmin/mz/sf_storage/build/workload/SPDK-NVMe-o-TCP
#   Test  #1: test_spdk_nvme_o_tcp_gated
#   Test  #2: test_spdk_nvme_o_tcp_withDSA_sequential_read
#   Test  #3: test_spdk_nvme_o_tcp_withDSA_sequential_write
#   Test  #4: test_spdk_nvme_o_tcp_withDSA_sequential_mixedrw
#   Test  #5: test_spdk_nvme_o_tcp_withDSA_random_read
#   Test  #6: test_spdk_nvme_o_tcp_withDSA_random_write
#   Test  #7: test_spdk_nvme_o_tcp_withDSA_random_mixedrw
#   Test  #8: test_spdk_nvme_o_tcp_noDSA_sequential_read
#   Test  #9: test_spdk_nvme_o_tcp_noDSA_sequential_write
#   Test #10: test_spdk_nvme_o_tcp_noDSA_sequential_mixedrw
#   Test #11: test_spdk_nvme_o_tcp_noDSA_random_read
#   Test #12: test_spdk_nvme_o_tcp_noDSA_random_write
#   Test #13: test_spdk_nvme_o_tcp_noDSA_random_mixedrw
#   Test #14: test_spdk_nvme_o_tcp_withDSA_sequential_read_pkm
#--------------------------------------------------------------------------------
# IO block size scaling 
#test_io_size_list=( 4 16 32 64 128)
#test_io_size_list=(512 1024)
#test_io_size_list=(16 32 64 128 512 1024)
#test_io_size_list=(4 16 32)  #128 /1024 
test_io_size_list=(128 1024)

# test_random_io_size_list=(4 16 32 64 128 512 1024 )
# test_seq_io_size_list=(4 16 32 64 128 512 1024)
test_random_io_size_list=(4 16 32 64 )
test_seq_io_size_list=(128 1024)
# test_random_io_size_list=(128 1024 )
# test_seq_io_size_list=(4 16)


# IO depth scaling
test_io_depth_list=(64 128 256 512 1024)
#test_io_depth_list=(1024)
#test_io_depth_list=(256 512 1024)

test_drive_connection_count_list=(2 4 6 8)

test_all_cases=(random_read random_write sequential_read sequential_write)

test_fio_job_num_list=(1 2 3 4)

#test_target_core_list=(1 2 3 4 5)  # storage target cpu core
test_target_core_list=(1 2 3 4 5 6)

#WSF ctest options:
WSF_ARGS="--options=--sut_reboot=false "

# test policy 
LOOP_COUNT=1
TEST_CASE="ALL"
#io_test_case="random_read" #[random_read, random_write, sequential_read, sequential_write]
#io_test_case="sequential_read"
io_test_case="random_read"
#CASE_SCALING="iosize" #iosize, iodepth, connection, fiojob, iosize_core,
#CASE_SCALING="iodepth"
#CASE_SCALING="fiojob"
#CASE_SCALING="iosize_fiojob"
CASE_SCALING="iosize_mixed"
#CASE_SCALING="iosize_core"
#CASE_SCALING="iosize_mixed_core"

io_size=1024  #128 # default block size.
drvie_connection_count=8  #8
#export TEST_BLOCK_SIZE=16  # default is 4k
export TEST_IO_DEPTH=128  #1024
export SPDK_PRO_CPUCORE=${SPDK_PRO_CPUCORE:-1}
export BENCHMARK_CLIENT_NODES=${BENCHMARK_CLIENT_NODES:-2}

#export TGT_ADDR="192.168.130.32"
#export TGT_ADDR="192.168.122.6,192.168.123.6"
export TGT_ADDR="192.168.126.2,192.168.127.2,192.168.128.2,192.168.129.2"
if [ "$BENCHMARK_CLIENT_NODES" == "1" ]; then
    export TGT_ADDR="192.168.128.2,192.168.129.2"
    #export SPDK_HUGEMEM=${SPDK_HUGEMEM:-"8192"}
    drvie_connection_count=8
fi
export SPDK_HUGEMEM=${SPDK_HUGEMEM:-"16384"}
#export TGT_ADDR="192.168.130.32"
export BDEV_TYPE=${BDEV_TYPE:-"drive"}
export DRIVE_NUM=${drvie_connection_count}
export ENABLE_DIGEST=1

export CPUS_ALLOWED="0-31"

export NR_IO_QUEUE=${NR_IO_QUEUE:-32}
export TEST_JOBS_NUM=${TEST_JOBS_NUM:-4}
export TEST_DURATION=${TEST_DURATION:-"300"}
export TEST_RAMP_TIME=${TEST_RAMP_TIME:-"100"}

export ALL_ARGS="TEST_BLOCK_SIZE=$io_size DRIVE_NUM=${drvie_connection_count} ENABLE_DIGEST=1"
HOOK1=${HOOK1:-"hook1.sh"}

perf_collection_type="emon"   # perf/emon

function hook1() {
    if [ -f "$HOOK1" ]; then
        echo "$HOOK1 exist"
        bash -x ./$HOOK1
    else 
        echo "no hook1"
    fi
}

function help_usage() {
  echo "usage: $0 [test case] [block size]"
  echo ""
  echo "[test case]     input testcase [random_read, random_write, sequential_read, sequential_write, all]"
  echo "[block size]    input block io size for fio test, unit: k, eg. 4/16/64/128/1024"
  echo "--help          Show help tips"
}

IP="10.67.127.17"
user="root"
perfmon_path="/root/mz/perf_analysis/perfmon.sh"

function perf_data() {
    perf_test_case=${1:-"randread_4k"}
    perf_case_type=${2:-"noDSA"}
    perf_type=${3:-"perf"}  #perf/emon
    # sleep ${TEST_RAMP_TIME}
    # sleep 60
    ssh -l ${user} ${IP} ${perfmon_path} $1 $2 $3 &
}

function check_args() {
    # Parse the parameter for the main entrypoint.
    echo $*
    if [[ $# == 0 || $* =~ ^"--help"$ ]]; then
      help_usage;
      exit 0;
    fi 

    io_test_case="$1"  # arg 1
    io_size=${2:-"128"} # arg 2.
}

# Do IO_SIZE scaling
function io_size_scaling() {
    echo "=== Start to run io size scaling for testcase [${io_test_case}] ==="
    files_boundary="$(date +%m%d-%H%M%S)-boundary-${io_test_case}"
    touch $files_boundary
    for io_size in ${test_io_size_list[@]}; do 
        files_boundary="$(date +%m%d-%H%M%S)-boundary-${io_test_case}"
        touch $files_boundary$io_size"k"
        echo "=== Benchamrk for IO_SIZE[${io_size}k] without DSA ==="; 
        hook1 & 
        #DRIVE_NUM=6 ENABLE_DIGEST=1 ./ctest.sh --loop ${LOOP_COUNT} -R test_spdk_nvme_o_tcp_noDSA_random_read; 
        TEST_BLOCK_SIZE=$io_size DRIVE_NUM=${drvie_connection_count} ENABLE_DIGEST=1 ./ctest.sh ${WSF_ARGS} --loop ${LOOP_COUNT} -R spdk_nvme_o_tcp_noDSA_${io_test_case} -E pkm; 
        sleep 5s
        echo "=== Benchamrk for IO_SIZE[${io_size}k] with DSA ==="; 
        hook1 & 
        TEST_BLOCK_SIZE=$io_size DRIVE_NUM=${drvie_connection_count} ENABLE_DIGEST=1 ./ctest.sh ${WSF_ARGS} --loop ${LOOP_COUNT} -R spdk_nvme_o_tcp_withDSA_${io_test_case} -E pkm; 

    done
}

function io_depth_scaling() {
    echo "=== Start to run io depth scaling for testcase [${io_test_case}] ==="
    files_boundary="$(date +%m%d-%H%M%S)-boundary-${io_test_case}"
    touch $files_boundary
    for io_depth in ${test_io_depth_list[@]}; do 
        files_boundary="$(date +%m%d-%H%M%S)-boundary-${io_test_case}"
        touch $files_boundary$io_size"k"
        echo "=== Benchamrk for IO_DEPTH[${io_depth}] without DSA ==="; 
        hook1 & 
        #DRIVE_NUM=6 ENABLE_DIGEST=1 ./ctest.sh --loop ${LOOP_COUNT} -R test_spdk_nvme_o_tcp_noDSA_random_read; 
        TEST_IO_DEPTH=$io_depth DRIVE_NUM=${drvie_connection_count} ENABLE_DIGEST=1 ./ctest.sh ${WSF_ARGS} --loop ${LOOP_COUNT} -R spdk_nvme_o_tcp_noDSA_${io_test_case} -E pkm; 
        sleep 5s
        echo "=== Benchamrk for IO_DEPTH[${io_depth}] with DSA ==="; 
        hook1 & 
        TEST_IO_DEPTH=$io_depth DRIVE_NUM=${drvie_connection_count} ENABLE_DIGEST=1 ./ctest.sh ${WSF_ARGS} --loop ${LOOP_COUNT} -R spdk_nvme_o_tcp_withDSA_${io_test_case} -E pkm; 

    done
}

function drive_connection_scaling() {
    echo "=== Start to run drive connection scaling for testcase [${io_test_case}] ==="
    files_boundary="$(date +%m%d-%H%M%S)-boundary-${io_test_case}"
    touch $files_boundary
    for drive_cnnt in ${test_drive_connection_count_list[@]}; do 
        files_boundary="$(date +%m%d-%H%M%S)-boundary-${io_test_case}"
        touch $files_boundary$io_size"k"
        echo "=== Benchmark for drive connection [${drive_cnnt}] without DSA ==="; 
        hook1 & 
        #DRIVE_NUM=6 ENABLE_DIGEST=1 ./ctest.sh --loop ${LOOP_COUNT} -R test_spdk_nvme_o_tcp_noDSA_random_read; 
        DRIVE_NUM=${drive_cnnt} ENABLE_DIGEST=1 ./ctest.sh ${WSF_ARGS} --loop ${LOOP_COUNT} -R spdk_nvme_o_tcp_noDSA_${io_test_case} -E pkm; 
        sleep 5s
        echo "=== Benchmark for drive connection [${drive_cnnt}]  with DSA ==="; 
        hook1 & 
        DRIVE_NUM=${drive_cnnt} ENABLE_DIGEST=1 ./ctest.sh ${WSF_ARGS} --loop ${LOOP_COUNT} -R spdk_nvme_o_tcp_withDSA_${io_test_case} -E pkm; 

    done
}

# for IO  size scaling case
function benchmark_io_size_scaling_case() {

    echo "=== Benchmakr BLOCK IO SIZE scaling cases ==="

    if [ "${io_test_case}" == "all" ]; then 

        #### ======= Random read case =======
        io_test_case="random_read"
        io_size_scaling #

        export BDEV_TYPE="drive"
        #### ======= Random Write case =======
        io_test_case="random_write"
        io_size_scaling #
        # echo "64k noDSA write test"
        # TEST_BLOCK_SIZE=64 ./ctest.sh --loop 5 -R test_spdk_nvme_o_tcp_noDSA_random_write
        # echo "64k with DSA write test"
        # TEST_BLOCK_SIZE=64 ./ctest.sh --loop 5 -R test_spdk_nvme_o_tcp_withDSA_random_write

        #### ======= Sequential read case =======
        io_test_case="sequential_read"
        io_size_scaling #

        #### ======= Sequential write case =======
        io_test_case="sequential_write"
        io_size_scaling #

    else
        io_size_scaling #
    fi 
}

function benchmark_io_depth_scaling_case() {

    echo "=== Benchmark FIO IO depth scaling for cases ==="

    if [ "${io_test_case}" == "all" ]; then 

        #### ======= Random read case =======
        io_test_case="random_read"
        io_depth_scaling #

        export BDEV_TYPE="drive"
        #### ======= Random Write case =======
        io_test_case="random_write"
        io_depth_scaling #
        # echo "64k noDSA write test"
        # TEST_BLOCK_SIZE=64 ./ctest.sh --loop 5 -R test_spdk_nvme_o_tcp_noDSA_random_write
        # echo "64k with DSA write test"
        # TEST_BLOCK_SIZE=64 ./ctest.sh --loop 5 -R test_spdk_nvme_o_tcp_withDSA_random_write

        #### ======= Sequential read case =======
        io_test_case="sequential_read"
        io_depth_scaling #

        #### ======= Sequential write case =======
        io_test_case="sequential_write"
        io_depth_scaling #

    else
        io_depth_scaling #
    fi 
}


function benchmark_drive_connection_scaling_case() {

    echo "=== Benchmark drvie connection scaling cases ==="

    if [ "${io_test_case}" == "all" ]; then 

        for testcase in ${test_all_cases[@]}; do 
            io_test_case=$testcase
            drive_connection_scaling 
        done

    else
        drive_connection_scaling #
    fi 
}

function fio_job_scaling() {
    echo "=== Start to run FIO job scaling for testcase [${io_test_case}] ==="
    files_boundary="$(date +%m%d-%H%M%S)-boundary-${io_test_case}"
    touch $files_boundary
    for num_job in ${test_fio_job_num_list[@]}; do 
        files_boundary="$(date +%m%d-%H%M%S)-boundary-${io_test_case}"
        touch $files_boundary$io_size"k"
        echo "=== Benchmark for num_job [${num_job}] without DSA ==="; 
        hook1 & 
        #DRIVE_NUM=6 ENABLE_DIGEST=1 ./ctest.sh --loop ${LOOP_COUNT} -R test_spdk_nvme_o_tcp_noDSA_random_read; 
        TEST_JOBS_NUM=${num_job} ENABLE_DIGEST=1 ./ctest.sh ${WSF_ARGS} --loop ${LOOP_COUNT} -R spdk_nvme_o_tcp_noDSA_${io_test_case} -E pkm; 
        sleep 5s
        echo "=== Benchmark for num_job [${num_job}] with DSA ==="; 
        hook1 & 
        TEST_JOBS_NUM=${num_job} ENABLE_DIGEST=1 ./ctest.sh ${WSF_ARGS} --loop ${LOOP_COUNT} -R spdk_nvme_o_tcp_withDSA_${io_test_case} -E pkm; 

    done
}

function benchmark_fio_job_scaling_case () {

    echo "=== Benchmark FIO Job scaling cases ==="

    if [ "${io_test_case}" == "all" ]; then 

        for testcase in ${test_all_cases[@]}; do 
            io_test_case=$testcase
            fio_job_scaling 
        done

    else
        fio_job_scaling #
    fi 
}

function benchmark_all_iosize_fio_job_scaling_case () {

    echo "=== Benchmark FIO Job scaling cases for All IO size ==="

    for io_size in ${test_io_size_list[@]}; do 
        files_boundary="$(date +%m%d-%H%M%S)-boundary-${io_test_case}"
        touch $files_boundary$io_size"k"

        TEST_BLOCK_SIZE=$io_size 
        benchmark_fio_job_scaling_case

    done

}

function benchmark_iosize_scaling_case_with_core () {
    echo "=== Benchmark target cpu core scaling cases for All IO size ==="

    for core in ${test_target_core_list[@]}; do 
        files_boundary="$(date +%m%d-%H%M%S)-boundary-${io_test_case}-"
        touch $files_boundary$core"core"

        SPDK_PRO_CPUCORE=$core 
        benchmark_io_size_scaling_case

    done
}

# random + sequential
function benchmark_io_size_scaling_case_mixed () {

    echo "=== Benchmark FIO Job scaling cases for mixed IO size ==="

    io_test_case="random_read"
    for io_size in ${test_random_io_size_list[@]}; do 
        files_boundary="$(date +%m%d-%H%M%S)-boundary-${io_test_case}"
        touch $files_boundary$io_size"k"

        # TEST_BLOCK_SIZE=$io_size 
        # benchmark_io_size_scaling_case

        echo "=== Benchamrk for IO_SIZE[${io_size}k] without DSA ==="; 
        hook1 & 
        #DRIVE_NUM=6 ENABLE_DIGEST=1 ./ctest.sh --loop ${LOOP_COUNT} -R test_spdk_nvme_o_tcp_noDSA_random_read; 
        perf_data ${io_test_case}_${io_size}k noDSA ${perf_collection_type} &
        TEST_BLOCK_SIZE=$io_size DRIVE_NUM=${drvie_connection_count} ENABLE_DIGEST=1 ./ctest.sh ${WSF_ARGS} --loop ${LOOP_COUNT} -R spdk_nvme_o_tcp_noDSA_${io_test_case} -E pkm; 
        sleep 5s
        echo "=== Benchamrk for IO_SIZE[${io_size}k] with DSA ==="; 
        hook1 & 
        perf_data ${io_test_case}_${io_size}k withDSA ${perf_collection_type} &
        TEST_BLOCK_SIZE=$io_size DRIVE_NUM=${drvie_connection_count} ENABLE_DIGEST=1 ./ctest.sh ${WSF_ARGS} --loop ${LOOP_COUNT} -R spdk_nvme_o_tcp_withDSA_${io_test_case} -E pkm; 


    done

    io_test_case="sequential_read"
    for io_size in ${test_seq_io_size_list[@]}; do 
        files_boundary="$(date +%m%d-%H%M%S)-boundary-${io_test_case}"
        touch $files_boundary$io_size"k"

        # TEST_BLOCK_SIZE=$io_size 
        # benchmark_io_size_scaling_case

        echo "=== Benchamrk for IO_SIZE[${io_size}k] without DSA ==="; 
        hook1 & 
        #DRIVE_NUM=6 ENABLE_DIGEST=1 ./ctest.sh --loop ${LOOP_COUNT} -R test_spdk_nvme_o_tcp_noDSA_random_read; 
        perf_data ${io_test_case}_${io_size}k noDSA ${perf_collection_type} &
        TEST_BLOCK_SIZE=$io_size DRIVE_NUM=${drvie_connection_count} ENABLE_DIGEST=1 ./ctest.sh ${WSF_ARGS} --loop ${LOOP_COUNT} -R spdk_nvme_o_tcp_noDSA_${io_test_case} -E pkm; 
        sleep 5s
        echo "=== Benchamrk for IO_SIZE[${io_size}k] with DSA ==="; 
        hook1 & 
        perf_data ${io_test_case}_${io_size}k withDSA ${perf_collection_type} &
        TEST_BLOCK_SIZE=$io_size DRIVE_NUM=${drvie_connection_count} ENABLE_DIGEST=1 ./ctest.sh ${WSF_ARGS} --loop ${LOOP_COUNT} -R spdk_nvme_o_tcp_withDSA_${io_test_case} -E pkm; 

    done


}

# random + sequential
function benchmark_io_size_scaling_case_mixed_op () {

    echo "=== Benchmark FIO Job scaling cases for mixed IO size ==="

    io_test_case="random_read"
    test_io_size_list=(${test_random_io_size_list[@]})
    benchmark_io_size_scaling_case

    io_test_case="sequential_read"
    test_io_size_list=(${test_seq_io_size_list[@]})
    benchmark_io_size_scaling_case

}

function benchmark_io_size_scaling_case_mixed_core() {
    echo "=== Benchmark target cpu core scaling cases for mixed IO size ==="

    for core in ${test_target_core_list[@]}; do 
        files_boundary="$(date +%m%d-%H%M%S)-boundary-${io_test_case}-"
        touch $files_boundary$core"core"

        SPDK_PRO_CPUCORE=$core 
        benchmark_io_size_scaling_case_mixed

    done
}


# Parse the arguments for bench.
check_args $*

export TEST_BLOCK_SIZE=${io_size}

if [ "$CASE_SCALING" == "iosize" ]; then
    benchmark_io_size_scaling_case
elif [ "$CASE_SCALING" == "iodepth" ]; then
    benchmark_io_depth_scaling_case
elif [ "$CASE_SCALING" == "fiojob" ]; then
    benchmark_fio_job_scaling_case
elif [ "$CASE_SCALING" == "connection" ]; then
    # $CASE_SCALING == connection
    benchmark_drive_connection_scaling_case
elif [ "$CASE_SCALING" == "iosize_fiojob" ]; then
    # $CASE_SCALING == iosize_fiojob
    benchmark_all_iosize_fio_job_scaling_case
elif [ "$CASE_SCALING" == "iosize_core" ]; then
    benchmark_iosize_scaling_case_with_core
elif [ "$CASE_SCALING" == "iosize_mixed" ]; then
    benchmark_io_size_scaling_case_mixed
elif [ "$CASE_SCALING" == "iosize_mixed_core" ]; then
    benchmark_io_size_scaling_case_mixed_core

else 
    echo "No scenaris spcified, default is io size scaling."
    benchmark_io_size_scaling_case
fi
