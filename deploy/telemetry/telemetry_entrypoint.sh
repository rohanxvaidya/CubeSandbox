#!/bin/bash -e
set -x

BASE_PATH=/opt/telemetry
WORK_PATH=${BASE_PATH}/tools
LOG_PATH=${BASE_PATH}/logs


echo "*** Start to telemetry daemon ***"
mkdir -p ${LOG_PATH}
(./run_telemetry.sh; echo $? > ${LOG_PATH}/status ) 2>&1 | tee ${LOG_PATH}/telemetry_$(date +"%m-%d-%y-%H-%M-%S").log && \
sync && cd ${LOG_PATH}; tar cf /export-logs status $(find . -name "*.log")

echo "*** End of the telemetry process***"

sleep infinity