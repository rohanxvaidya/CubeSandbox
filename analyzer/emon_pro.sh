#!/bin/bash

file=$1
time=${EMON_TIME:-60}
details_view=${EMON_FULL:-0}
CONFIG=$2
source /opt/intel/sep/sep_vars.sh
CONFIG=$(realpath $CONFIG)
ls -lash /opt/intel/sep/sepdk/src/pax/pax-x32_64-$(uname -r)smp.ko
ls -lash /opt/intel/sep/sepdk/src/sepint5-x32_64-$(uname -r)smp.ko
ls -lash /opt/intel/sep/sepdk/src/sep5-x32_64-$(uname -r)smp.ko

mpp=/opt/intel/sep/config/edp/pyedp/mpp.py
xml=/opt/intel/sep/config/edp/graniterapids_server_private.xml

mkdir -p ./emon_$file && cp $file.dat ./emon_$file/ && cd ./emon_$file

#if [ "${CONFIG}" != "" ]; then
#                #CONFIG=$(realpath $CONFIG)
#        emon -i ${CONFIG} -f ${file}.dat &  sleep $time; emon -stop
#else
#        emon -collect-edp -f ${file}.dat &  sleep $time; emon -stop
#fi

#sleep 2s

if [ "$details_view" == "1" ]; then
	echo "Process the emon data with details view"
	python3 $mpp -m $xml -i ${file}.dat -o ${file}.xlsx --socket-view --core-view --thread-view --uncore-view -p 32
else 

	python3 $mpp -m $xml -i ${file}.dat -o ${file}.xlsx --socket-view --core-view --thread-view --uncore-view --no-detail-views -p 32
fi

chmod -R 777 ../emon_$file


