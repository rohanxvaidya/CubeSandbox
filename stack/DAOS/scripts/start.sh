#!/bin/bash

WORK_PATH=/home/daos/
CODE_PATH=${WORK_PATH}/daos/
BUILD_PRE=${WORK_PATH}/pre

DAOS_DEPS_BUILD=yes
DAOS_KEEP_BUILD=yes # keep the build folder and result?
DAOS_TARGET_TYPE=debug  # release/debug
DEPS_JOBS=1

## for socket setting.
# in daos server
mkdir -p /var/run/daos_server
mkdir -p /var/daos/config

mkdir -p /mnt/daos && mount -t tmpfs -o size=32G tmpfs  /mnt/daos

# in daos-client docker, 
mkdir -p /var/run/daos_agent

mkdir -p /etc/daos && cp -r ${WORK_PATH}/config/* /etc/daos/
cd ${WORK_PATH}

## config the server , agent and client config 

# for debug
# export FI_LOG_LEVEL=debug
# export FI_LOG_LEVEL=warn

# export HG_LOG_LEVEL=debug
# export HG_LOG_LEVEL=warn
	

source /root/.bashrc
pkill daos_agent 
pkill daos_server
rm -f /tmp/daos*.log
rm -f /tmp/.daos_engine.0.log.swp
rm -f /tmp/daos_engine*
# umount /mnt/daos
# remove database related.
rm -rf /var/db/daos_server/*

## start the server
#daos_server start &
daos_server start -o /etc/daos/daos_server.yml &

# count=0
# while true;do
#     joined_num=`dmg sys query -v|grep Joined|wc -l`
#     if [[ $joined_num -eq 3 ]];then
#         break
#     fi
#     echo -e "wait all rank join, $count times"
#     count=$((count+1))
#     sleep 1
# done

sleep 5
echo -e "dmg storage format"
dmg storage format

## start the client
echo -e "start client..."
#daos_agent &
daos_agent start -o /etc/daos/daos_agent.yml &


