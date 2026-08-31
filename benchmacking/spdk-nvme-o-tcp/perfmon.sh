#!/bin/bash
set -x

EMON_SCRIPT_PATH="/root/mz/tools/emon.sh"
PERF_SCRIPT_PATH="/root/mz/tools/perf.sh"
FREQ=${FREQ:-"999"}

FG_PATH="/root/mz/tools/FlameGraph"
RECORD_TIME=${RECORD_TIME:-"100"}  # 100s by default

test_case=${1:-"randread_4k"}
case_type=${2:-"noDSA"}
perf_type=${3:-"perf"}  #perf/emon

node_num=1
core_num=1

emon_path="/root/mz/perf_analysis/emon_data"
perf_path="/root/mz/perf_analysis/perf_data"

# case_folder="${test_case}-$(date +"%m-%d-%y-%H-%M-%S")"
case_folder=${test_case}

sleep 160  #??????

if [ ${perf_type} == "perf" ]; then
    cd $perf_path && mkdir -p ${case_folder} && cd $case_folder
    #/root/mz/tools/perf.sh nvmf_tgt randread_16k_withDSA_1node_1core perf
    ${PERF_SCRIPT_PATH} nvmf_tgt ${test_case}_${case_type}_${node_num}node_${core_num}core perf
elif [ ${perf_type} == "emon" ]; then
    cd $emon_path && mkdir -p $case_folder && cd $case_folder
    #/root/mz/tools/perf.sh nvmf_tgt randread_16k_withDSA_1node_1core perf
    ${PERF_SCRIPT_PATH} nvmf_tgt ${test_case}_${case_type}_${node_num}node_${core_num}core emon
fi
