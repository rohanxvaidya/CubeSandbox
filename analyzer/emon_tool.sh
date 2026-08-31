#!/bin/bash

# This script is used to capture and process emon data. It will capture emon data for a specified duration and then process the data using the mpp.py script. The processed data will be saved in an xlsx file. The script also supports specifying a custom emon config file.
# param1: function, "cap" for capture, "proc" for process data, "all" for both capture and process. default is "cap".
# param2: file name for emon capture and the folder containing the file. e.g. "test1/test1" for test1/test1.dat.
# param3: emon config file. if not specified, the default edp config will be used. e.g. "config/edp/pyedp_config.txt"

function=${1:-"cap"}  # capture and process and both. "cap"/"pro"/"install"/"all"
file=$2
time=${EMON_TIME:-60}
details_view=${EMON_FULL:-0}
CONFIG=$3
source /opt/intel/sep/sep_vars.sh
CONFIG=$(realpath $CONFIG)

# check the emon driver is loaded or not. if not, load the driver by insmod with the .ko file in /opt/intel/sep/sepdk/src/pax/. if the driver is already loaded, skip the loading step.
# check if the emon driver is loaded

/opt/intel/sep/sepdk/src/insmod-sep

if ! lsmod | grep -q "pax"; then
    echo "emon driver is not loaded. Loading the driver..."
    # Before loading the driver, check if the .ko file exists. if exist, then loaded driver with insmod, if not, print an error message and exit. 
    # load the driver by insmod with the .ko file in /opt/intel/sep/sepdk/src/pax/ if the .ko file exists. if not, print an error message and exit.
    if [ -f /opt/intel/sep/sepdk/src/pax/pax-x32_64-$(uname -r)smp.ko ] ;then
        insmod /opt/intel/sep/sepdk/src/pax/pax-x32_64-$(uname -r)smp.ko
    else
        echo "Error: /opt/intel/sep/sepdk/src/pax/pax-x32_64-$(uname -r)smp.ko not found. Please check the path and try again."
        exit 1
    fi  

    if [ -f /opt/intel/sep/sepdk/src/sepint5-x32_64-$(uname -r)smp.ko ] ;then
        insmod /opt/intel/sep/sepdk/src/sepint5-x32_64-$(uname -r)smp.ko
    elif [ -f /opt/intel/sep/sepdk/src/sep5-x32_64-$(uname -r)smp.ko ] ;then
        insmod /opt/intel/sep/sepdk/src/sep5-x32_64-$(uname -r)smp.ko
    else    
        echo "Error: no sepint5-x32_64-$(uname -r)smp.ko or sep5-x32_64-$(uname -r)smp.ko found in /opt/intel/sep/sepdk/src/. "
        echo "Please check the path and try again."
        exit 1
    fi  

else
    echo "emon driver is already loaded. Skipping the loading step."
fi  

ls -lash /opt/intel/sep/sepdk/src/pax/pax-x32_64-$(uname -r)smp.ko
ls -lash /opt/intel/sep/sepdk/src/sepint5-x32_64-$(uname -r)smp.ko
ls -lash /opt/intel/sep/sepdk/src/sep5-x32_64-$(uname -r)smp.ko

function process_data() {
    mpp=/opt/intel/sep/config/edp/pyedp/mpp.py
    xml=/opt/intel/sep/config/edp/graniterapids_server_private.xml

    # process data using mpp.py
    if [ "$details_view" == "1" ]; then
        echo "Process the emon data with details view"
        python3 $mpp -m $xml -i ${file}.dat -o ${file}.xlsx --socket-view --core-view --thread-view --uncore-view -p 32
    else

        python3 $mpp -m $xml -i ${file}.dat -o ${file}.xlsx --socket-view --core-view --thread-view --uncore-view --no-detail-views -p 32
    fi

}


function capture_data() {
    if [ "${CONFIG}" != "" ]; then
        #CONFIG=$(realpath $CONFIG)
        emon -i ${CONFIG} -f ${file}.dat &  sleep $time; emon -stop
    else
        emon -collect-edp -f ${file}.dat &  sleep $time; emon -stop
    fi
}

if [ "$function" == "cap" ]; then
    mkdir -p ./emon_$file && cd ./emon_$file
    capture_data
    chmod -R 777 ../emon_$file

elif [ "$function" == "pro" ]; then
    process_data
    chmod -R 777 ./${file}*
elif [ "$function" == "all" ]; then
    mkdir -p ./emon_$file && cd ./emon_$file

    capture_data
    sleep 2s
    process_data
    chmod -R 777 ../emon_$file

else
    echo "Invalid function. Use 'cap' for capture, 'pro' for process, or 'all' for both."
    exit;
fi



