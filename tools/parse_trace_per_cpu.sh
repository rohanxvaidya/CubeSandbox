#!/bin/bash
set -x 
# parse the spinlock slowpath duration time and "flush_workqueue_prep_pwqs" duration time. 

# parameters:
# $1 percpu trace file. 
#  - this file is captured with command: trace-cmd record -p function_graph -g flush_workqueue_prep_pwqs -m 131072 fio 6_fsync_ramdisk.fio
#  - and parse out the percpu trace file:  trace-cmd report -I trace.dat  --cpu 0 > cpu.0.log
# 
# $2: the new name for the parse out data.
#
#
DIR="$( cd "$( dirname "$0" )" &> /dev/null && pwd )"
WORK_PATH="$DIR"

ORIG_FILE=$1
FILE_NAME=${2:-${ORIG_FILE}}
ALL_FUNCTION_FILE="${FILE_NAME}_all_function.log"
ALL_FUNCTION_KV_FILE="${FILE_NAME}_all_function-kv.log"

PATTERN1="queued_spin_lock_slowpath"
PATTERN2="flush_workqueue_prep_pwqs"
slowpath_duration_file="${FILE_NAME}_slowpath_durations.log"
flush_wq_pwqs_duration_file="${FILE_NAME}_flush_wq_pwqs_durations.log"
slowpath_duration_kv_file="${FILE_NAME}_slowpath_durations-kv.log"
flush_wq_pwqs_duration_kv_file="${FILE_NAME}_flush_wq_pwqs_durations-kv.log"

PATTERN="queued_spin_lock_slowpath|flush_workqueue_prep_pwqs"



# filter out the pattern related functions and duration. entry and exit.
grep -E "${PATTERN}" -A3 -B3 ${ORIG_FILE} |sed 's/:/ /g' |sed 's/+/ /g' > ${ALL_FUNCTION_FILE}

# filter only for pattern 1 - slowpath function
grep "${PATTERN1}" ${ALL_FUNCTION_FILE} -A1 > ${slowpath_duration_file}
# for timing and duration value for slowpath function.
grep " us" ${slowpath_duration_file} | awk '{print $3 ",   "  $5}' > ${slowpath_duration_kv_file}
# for csv
cp ${slowpath_duration_kv_file} "${slowpath_duration_kv_file}.csv"

## fileter for pattern2- pwqs
grep "${PATTERN2}" ${ALL_FUNCTION_FILE} -B1 > ${flush_wq_pwqs_duration_file}
# for timing and duration value for slowpath function.
grep " us" ${flush_wq_pwqs_duration_file} | awk '{print $3 ",   "  $6}' > ${flush_wq_pwqs_duration_kv_file}
# for csv
cp ${flush_wq_pwqs_duration_kv_file} "${flush_wq_pwqs_duration_kv_file}.csv"


## for interaged pattern
cp ${slowpath_duration_kv_file} "${ALL_FUNCTION_KV_FILE}"
cat ${flush_wq_pwqs_duration_kv_file} >> "${ALL_FUNCTION_KV_FILE}"

# sort with timestamp for integrated durations
sort "${ALL_FUNCTION_KV_FILE}" > "${ALL_FUNCTION_KV_FILE}.sorted"

cp "${ALL_FUNCTION_KV_FILE}.sorted" "${ALL_FUNCTION_KV_FILE}.sorted.csv"



# sed 's/:/ /g' bgm-cpu3-slowpath-all.log  > bgm-cpu3-slowpath-all-new.log

# grep "queued_spin_lock_slowpath" bgm-cpu3-slowpath-all-new.log -A1 > bgm-cpu3-slowpath_time-value.log
# grep " us" bgm-cpu3-slowpath_time-value.log | awk '{print $3 ",   "  $5}' > bgm-cpu3-slowpath_time-value-kv.log
# #grep "#" srf-cpu3-slowpath-all.log -A1 > srf-cpu3-pwqs_all.log
# grep "flush_workqueue_prep_pwqs" bgm-cpu3-slowpath-all-new.log -B1 > bgm-cpu3-pwqs_all_time-value.log
# grep " us" bgm-cpu3-pwqs_all_time-value.log | awk '{print $3 ",   "  $6}' > bgm-cpu3-pwqs_all_time-value-kv.log
# cp bgm-cpu3-slowpath_time-value-kv.log bgm-cpu3-all-kv.log
# cat bgm-cpu3-pwqs_all_time-value-kv.log >> bgm-cpu3-all-kv.log
# vim bgm-cpu3-all-kv.log
# sort bgm-cpu3-all-kv.log > bgm-cpu3-all-kv.log.sorted
# cp bgm-cpu3-all-kv.log.sorted bgm-cpu3-all-kv.log.sorted.csv
# cp srf-cpu3-slowpath_time-value-new-kv.log srf-cpu3-slowpath_time-value-new-kv.log.csv
# cp bgm-cpu3-slowpath_time-value-kv.log bgm-cpu3-slowpath_time-value-kv.log.csv