#!/bin/bash

Telemdir="/root/mz/Storage-performance-analysis"

#TELEM_ENABLE=1
TELEM_ENABLE=${TELEM_ENABLE:-"0"}
if [ "$TELEM_ENABLE" == "0" ]; then  
   echo "Telemtry is disabled.."
   exit 0
fi

NODE_AFFINITY=1
filename_suffix="${TEST_BLOCK_SIZE}k"

#TEST_RAMP_TIME=300
#TEST_DURATION=600
TEST_DURATION=${TEST_DURATION:-"600"}
TEST_RAMP_TIME=${TEST_RAMP_TIME:-"300"}

#TEST_RAMP_TIME=300
#TEST_DURATION=600

delay_time=$(($TEST_RAMP_TIME + 30))

duration=200

full_time=$((${delay_time} + ${duration} + 10))

NODE_AFFINITY=${NODE_AFFINITY} CASENAME="$filename_suffix" bash -x ${Telemdir}/run.sh --telem --delay_run=${delay_time}s --duration=${duration}s --logpath=logs > /tmp/telem.log &

sleep ${full_time}

bash -x ${Telemdir}/run.sh --telem --stop

sed -i '/force_end=1/d' ${Telemdir}/config/config.conf


