#!/bin/bash

Telemdir="/home/raspadmin/mz/Storage-performance-analysis-master"

TEST_DURATION=${TEST_DURATION:-"120"}
TEST_RAMP_TIME=${TEST_RAMP_TIME:-"120"}

delay_time=$(( ${TEST_RAMP_TIME} + 30 ))
duration=100

full_time=$((${delay_time} + ${duration} + 10))

bash -x ${Telemdir}/run.sh --telem --delay_run=${delay_time}s --duration=${duration}s --logpath=logs > /tmp/telem.log &

sleep ${full_time}

bash -x ${Telemdir}/run.sh --telem --stop

sed -i '/force_end=1/d' ${Telemdir}/config/config.conf
