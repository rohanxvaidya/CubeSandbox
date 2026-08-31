#!/bin/bash

#arg1:
PID_NAME=$1  # PID or process/thread name, for spdk nvme fabric, it's nvmf_tgt
#PID=$1
# output name
NAME=${2:-${PID_NAME}}

FUNCTION=${3:-"0"}  # collect emon or not, or offcpu

EMON_SCRIPT_PATH="/home/raspadmin/mz/emon.sh"
FREQ=${FREQ:-"999"}
# https://github.com/brendangregg/FlameGraph.git
FG_PATH="/home/raspadmin/mz/FlameGraph"
RECORD_TIME=${RECORD_TIME:-"100"}  # 100s by default

#TPID=$(ps -ef | grep ${PID_NAME} | grep -v grep | awk '{print $2}')
# SPID=$(top -n 1 | grep ${PID_NAME} | grep -v grep | awk '{s}END{print $1}')     #awk '{print $1}')
#SPID=`top -n 1 | grep reactor | cut -d ' ' -f 1`

#SPID=$(ps -eLf | grep ${PID_NAME} | grep -v grep | grep -v perf | head -1 | awk '{print $2}')
SPID=$(ps -eLf | grep ${PID_NAME} | grep -v grep | head -1 | awk '{print $2}')

#PID=$(expr $SPID + 0) # change to digital number.
PID=$(($SPID + 0)) # change to digital number.
SPID="$(echo $SPID)"


if [ "$FUNCTION" == "emon" ]; then
    echo "Collect the emon data..."
    if [ -e "$EMON_SCRIPT_PATH" ]; then
        $EMON_SCRIPT_PATH cap $NAME 60
        sleep 2s
        $EMON_SCRIPT_PATH pro $NAME 60
    fi
    exit 0
fi

# install Framegraph tools
function install_framegraph() {
  git clone https://github.com/brendangregg/FlameGraph.git
}


## capture offcpu
# 
function offcpu() {

#capture the offcpu data

echo "Start to capture the offcpu data..."
# please ensure the bcc tool chain have been installed.
offcputime -df ${RECORD_TIME} -p ${PID} > ${NAME}_offcpu.out

sleep 3s
# /home/raspadmin/mz/FlameGraph/flamegraph.pl --color=io --title="1core_noDSA_seqread_1024 Off-CPU Time Flame Graph" \ 
# --countname=us < 1core_noDSA_seqread_1024_offcpu.out > 1core_noDSA_seqread_1024_offcpu.svg

echo "Tranform the offtime data to FlameGraph"
${FG_PATH}/flamegraph.pl --color=io \ 
--title="${NAME} Off-CPU Time FlameGraph" \ 
--countname=us < ${NAME}_offcpu.out > ${NAME}_offcpu.svg
echo "Done!"
}


echo "The select Process ${PID_NAME}'s PID is : $SPID"

if [ "$FUNCTION" == "offcpu" ]; then
    offcpu
    exit 0
fi


if [ "$ipt" == "u" ]; then
        OPT="-e intel_pt/cyc=1/u"
else if [ "$ipt" == "k" ]; then
        OPT="-e intel_pt/cyc=1/k"
else if [ "$ipt" == "a" ]; then
        OPT="-e intel_pt/cyc=1/"
else
        OPT=""
fi

fi
fi



##### for report #####
echo "Start to record perf on PID $PID for Flamegraphic..."
# very interesting issue, here the perf command is [perf recore -p '123456' ...] the process number is a string.
#ARG="-p `echo ${PID}` -F ${FREQ}"  #

ARG="-p `echo ${PID}` -F ${FREQ}"
# PERF_CMD="perf record -p ${PID} -F ${FREQ} --call-graph dwarf -o ${NAME}_perf.data -- sleep $RECORD_TIME"
# CMD="perf record -p `top -n 1 | grep reactor | cut -d ' ' -f 1` -F ${FREQ} --call-graph dwarf -o ${NAME}_perf.data -- sleep $RECORD_TIME"
# echo $CMD

# recore for flamegraphic
perf record -p ${PID} ${OPT} -F ${FREQ} --call-graph dwarf -o ${NAME}_perf1.data -- sleep $RECORD_TIME
# #perf record ${ARG} --call-graph dwarf -o ${NAME}_perf.data -- sleep $RECORD_TIME
# perf script -i ${NAME}_perf1.data > ${NAME}_perf.unfold

# # fold the perf data
# ${FG_PATH}/stackcollapse-perf.pl ${NAME}_perf.unfold >${NAME}_perf.folded

# # transfer to svg
# ${FG_PATH}/flamegraph.pl ${NAME}_perf.folded > ${NAME}_flamegraph.svg


sleep 5
##### for report #####
echo "Start to record again for report and hotsport..."

# recore for flamegraphic
perf record -p ${PID} ${OPT} -F ${FREQ} -g -o ${NAME}_perf.data -- sleep $RECORD_TIME

perf report -f -n --sort=dso --max-stack=0 --stdio -i ${NAME}_perf.data > ${NAME}_report.txt
perf report -f -n --no-children --max-stack=0 --stdio -i ${NAME}_perf.data > ${NAME}_hotspots.txt


sleep 2s
echo "Handle the flamegraph..."

#perf record ${ARG} --call-graph dwarf -o ${NAME}_perf.data -- sleep $RECORD_TIME
perf script -i ${NAME}_perf1.data > ${NAME}_perf.unfold

# fold the perf data
${FG_PATH}/stackcollapse-perf.pl ${NAME}_perf.unfold >${NAME}_perf.folded

# transfer to svg
${FG_PATH}/flamegraph.pl ${NAME}_perf.folded > ${NAME}_flamegraph.svg
