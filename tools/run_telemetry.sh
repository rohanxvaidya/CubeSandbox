#!/bin/bash -e
set -x

#CONFIGURATION_OPTIONS="-DNODE_SELECT=;-DDEVICE_SELECT=;-DDELAY_RUN=2s;-DDURATION=200s;-DLOG_PATH=logs"
export $(echo ${CONFIGURATION_OPTIONS//"-D"/""} | tr -t ';' '\n')

BASE_PATH=/opt/telemetry
WORK_PATH=${BASE_PATH}/tools
LOG_PATH=${BASE_PATH}/logs
DURATION=${DURATION:-"180"}
DELAY_RUN=${DELAY_RUN:-"2"}
top_seconds_per_monitor=5
seconds_per_monitor=5
COUNT=$(($DURATION/$seconds_per_monitor))
TOP_GREP=${TOP_GREP:-'ceph|fio|kubelet|reactor|qemu|vhost|build|softir'}

sleep ${DELAY_RUN}

cat << EOF > ${WORK_PATH}/telemetry.conf
#!/usr/bin/env bash
force_end=0
EOF
source ${WORK_PATH}/telemetry.conf

# dump hostname
touch ${LOG_PATH}/"${MY_NODE_NAME}.log"

echo "Start to capture the system info..."

task_list=()
echo "---start---" > ${LOG_PATH}/top_sar_end_time.log
date >> ${LOG_PATH}/top_sar_end_time.log
# system top
# top_seconds_per_monitor=5
# (timeout $DURATION top -b -d ${top_seconds_per_monitor} |grep -iE 'ceph|fio|kubelet|reactor|qemu|vhost|build|softir|kworker' > ${LOG_PATH}/node-top.log) &
# task_1=`ps aux|grep -v grep |grep 'top -b'|awk '{print $2}'`
#top_frame=40
#(timeout $DURATION top -b -n ${top_frame} -d ${top_seconds_per_monitor} |grep -iE 'ceph|fio|kubelet|reactor|qemu|vhost|build|softir|kworker' > ${LOG_PATH}/node-top.log) &

#task_list[${#task_list[*]}]=$task_1  # TODO: get the process ID.
    
# IO monitor
    sar -d -p $seconds_per_monitor $COUNT > ${LOG_PATH}/sar-io.log &
    task_2=`ps aux|grep -v grep |grep 'sar -d'|awk '{print $2}'`
    task_list[${#task_list[*]}]=$task_2
# Network monitor
    sar -n DEV $seconds_per_monitor $COUNT > ${LOG_PATH}/sar-net.log &
    task_3=`ps aux|grep -v grep |grep 'sar -n'|awk '{print $2}'`
    task_list[${#task_list[*]}]=$task_3
# cpu state
    sar -m CPU -P ALL $seconds_per_monitor $COUNT > ${LOG_PATH}/sar-cpu-monitor.log &
    task_4=`ps aux|grep -v grep |grep 'sar -m'|awk '{print $2}'`
    task_list[${#task_list[*]}]=$task_4
    sar -P ALL $seconds_per_monitor $COUNT > ${LOG_PATH}/sar-cpu-all.log &
    task_5=`ps aux|grep -v grep |grep 'sar -P'|awk '{print $2}'`
    task_list[${#task_list[*]}]=$task_5
    sar -u $seconds_per_monitor $COUNT > ${LOG_PATH}/sar-cpu-uniq.log &
    task_6=`ps aux|grep -v grep |grep 'sar -u'|awk '{print $2}'`
    task_list[${#task_list[*]}]=$task_6
# mem state
    sar -r $seconds_per_monitor $COUNT > ${LOG_PATH}/sar-mem.log &
    task_7=`ps aux|grep -v grep |grep 'sar -r'|awk '{print $2}'`
    task_list[${#task_list[*]}]=$task_7
# 
kill_process() {
    set +e 
    for i in ${task_list[*]}
    do
        para=$(ps aux|grep -v grep|grep ${i}|grep -iE 'top|sar'|awk '{print $2}')
        para=${para:-"null"}

        if [ "$para" == "null" ]; then
            echo "process IS NULL"
        else
            ##
            ## issue here, cannot kill process in docker...
            echo " *** Force to kill process[${i}]... ***"
            kill ${i}   
            task_list=( "${task_list[*]/${i}}" )       
        fi  
    done
}

# sleep $(($seconds_per_monitor*$COUNT))
while [ $SECONDS -le $(($DURATION+${DELAY_RUN})) ]
do
    # top batch output.
    top -b -n 1 | head -100 >> ${LOG_PATH}/node-top.log 
    
    source ${WORK_PATH}/telemetry.conf
    if [ "$force_end" == "1" ]; then
        kill_process
        break
    fi
    sleep $seconds_per_monitor
done

echo "---end---" >> ${LOG_PATH}/top_sar_end_time.log
date >> ${LOG_PATH}/top_sar_end_time.log

force_end=1
# force kill all task
if [ "$force_end" == "1" ]; then
kill_process
fi

echo "End of telemetry ..."