#!/bin/bash

#arg1
# $1 function: 
FUNCTION=${1:-"cap"}  # capture and process and both. "cap"/"pro"/"install"/"all"

# output name
NAME=${2:-${PID_NAME}}

#arg3: capture emon data duration. seconds
TIME=${3:-"100"} 

CONFIG=${4} # specify emon config file is needed. 
if [ "$CONFIG" != "" ]; then
    CONFIG=$(realpath $CONFIG)
fi
FREQ=${FREQ:-"999"}

FG_PATH="/home/raspadmin/mz/FlameGraph"

RECORD_TIME=${RECORD_TIME:-"100"}  # 100s by default

PROCESS_ALL=1 # if process all, use the "VIEW=--socket-view --core-view --thread-view --uncore-view" in config file. 

#SEP_VERSION="sep_5_43"
SEP_VERSION="sep_5_50"
# set the path to the default directory:  e.g. to /opt/intel/sep
SEP_VERSION=""

emon_bin_path="/opt/intel/${SEP_VERSION}/"
emon_config_path=${emon_bin_path}/sep/config/edp/
# for GNR
emon_metrics="graniterapids_server_private.xml"
#/opt/intel/sep_private_5.50_linux_11150548f64824e36/config/edp/graniterapids_server_private.xml
emon_metrics_file=${emon_config_path}/${emon_metrics}

#emon_bin_path="/opt/intel/${SEP_VERSION}"
#emon_bin_path="/opt/intel/"
#emon_edp_config="config/edp/pyedp_config.txt"
emon_edp_config="pyedp_config.txt"

emon_sep_vars="$emon_bin_path/sep/sep_vars.sh"
#emon_sep_vars="$emon_bin_path/sep_vars.sh"

#/opt/intel/${SEP_VERSION}/emon/sep/sep_vars.sh
emon_edp_config_file="$emon_config_path/$emon_edp_config"
#emon_edp_config_file="$emon_bin_path/$emon_edp_config"

if [ "${SEP_VERSION}" == "sep_5_42" ]; then
    emon_src_path="/opt/intel/${SEP_VERSION}/sep_private_5_42_linux_08221738bd46ff4"
fi
if [ "${SEP_VERSION}" == "sep_5_43" ]; then
    emon_src_path="/opt/intel/${SEP_VERSION}/sep_private_5_43_linux_10162201a08094e"
fi
if [ "${SEP_VERSION}" == "sep_5_49" ]; then
    #sep_private_5_49_linux_09260550f46847635.tar
    emon_src_path="/opt/intel/${SEP_VERSION}/sep_private_5_49_linux_09260550f46847635"
fi
if [ "${SEP_VERSION}" == "sep_5_48" ]; then
    #sep_private_5_49_linux_09260550f46847635.tar
    #sep_private_5.48_linux_07291753bd42ce2bc
    emon_src_path="/opt/intel/${SEP_VERSION}/sep_private_5_48_linux_07291753bd42ce2bc"
fi
if [ "${SEP_VERSION}" == "sep_5_50" ]; then
    #sep_private_5_49_linux_09260550f46847635.tar
    #sep_private_5.48_linux_07291753bd42ce2bc
    emon_src_path="/opt/intel/${SEP_VERSION}/sep_private_5_50_linux_11150548f64824e36"
fi


emon_options=""


LOCAL_DIR=`pwd`
emon_path="$LOCAL_DIR/emon_$NAME"
new_emon_edp_conf_file="$emon_path/new_pyedp.conf"

## install dependences for edp process function.
# they may not be needed for edp collect function.
function emon_edp_process_deps () {
    # for Unbuntu
    python3 -m pip install --no-cache-dir pandas numpy defusedxml pytz tdigest xlsxwriter
    pip install natsort multiprocess tqdm tables
}

function emon_install () {
    echo "Install sep package."
    mkdir -p $emon_bin_path 
    
    cd $emon_src_path
    grep -E '^vtune:' /etc/group || groupadd vtune
    #./sep-installer.sh -u -C $emon_bin_path --accept-license -ni -i -g vtune --c-compiler $(which gcc)
    ./sep-installer.sh -u -C $emon_bin_path --accept-license -ni -i -g vtune 
#    ./sep-installer.sh -u -C $emon_bin_path --accept-license -ni -i -g vtune --c-compiler $(which gcc)-12

}


function emon_start () {
    if [ -e "$emon_sep_vars" ]; then
        (
            . "$emon_sep_vars" > /dev/null
            mkdir -p "$emon_path"
            emon $emon_options -collect-edp > "$emon_path/emon.dat" 2>&1 &
            echo $! > "$emon_path/emon.pid"
        )
        echo "emon started"
    fi
}

function emon_stop () {
    if [ -e "$emon_sep_vars" ] && [ -e "$emon_path/emon.pid" ]; then
        (
            . "$emon_sep_vars" > /dev/null
            emon -stop
            sleep 5s
            sudo kill -9 $(cat "$emon_path/emon.pid" 2> /dev/null) > /dev/null 2>&1 || true
            rm -f "$emon_path/emon.pid"
        )
        echo "emon stopped"
    fi
}

function emon_collect () {
    if [ -e "$emon_sep_vars" ]; then
        (
            . "$emon_sep_vars" > /dev/null
            cd "$emon_path"
#            emon -process-pyedp  "$emon_edp_config_file"
            emon -process-pyedp -i "$emon_path/emon.dat" "$emon_edp_config_file"
        )
    fi
}

# #source the vars.
# . $oneapi_path/setvars.sh
. "$emon_sep_vars" > /dev/null
date -Ins

if [ "$FUNCTION" == "cap" ]; then
    mkdir -p $emon_path && cd $emon_path

    date -Ins >> $emon_path/TRACE_START-$NAME

    cp $emon_edp_config_file $new_emon_edp_conf_file
    echo "Strat to collect emon edp data..."

    if [ "${CONFIG}" != "" ]; then
         emon -i $CONFIG  $emon_options  -f $emon_path/emon-$NAME.dat | tee $emon_path/mon-$NAME.logs 2>&1 & 
    
         echo $! > $emon_path/emon.pid
     else 
         #emon -collect-edp $emon_options -t $TIME -f $emon_path/emon-$NAME.dat > $emon_path/mon-$NAME.logs 2>&1 &
         emon -collect-edp $emon_options  -f $emon_path/emon-$NAME.dat | tee $emon_path/mon-$NAME.logs 2>&1 & 
          
         echo $! > $emon_path/emon.pid
    fi
    #echo $! > $emon_path/emon.pid

    echo "The emon procees ID is $(cat $emon_path/emon.pid )"

    # sleep

    sleep $TIME

    emon -stop
    sleep 5s
    sed -i "/.*OUTPUT=*/c\OUTPUT=summary-${NAME}.xlsx" $new_emon_edp_conf_file
    sed -i "/.*EMON_DATA=*/c\EMON_DATA=emon-$NAME.dat" $new_emon_edp_conf_file
    if [ "${PROCESS_ALL}" == "1" ]; then
        sed -i "/^VIEW=/c\VIEW=--socket-view --core-view --thread-view --uncore-view" $new_emon_edp_conf_file
    fi

elif [ "$FUNCTION" == "pro" ]; then
    cd $emon_path
    if [ "${CONFIG}" == "" ]; then
        #emon -process-pyedp "/opt/intel/${SEP_VERSION}/emon/sep/config/edp/pyedp_config.txt"
        emon -process-pyedp "$new_emon_edp_conf_file"
    else  
        python3 -m pyedp.edp  --socket-view --core-view --thread-view --uncore-view -i "emon-$NAME.dat" -o "summary-${NAME}.xlsx" \
        -m "${emon_metrics_file}" -f "${emon_metrics_file}"
   fi
elif [ "$FUNCTION" == "install" ]; then
    # incase need to install driver manually.
    emon_install
else 
    echo "no function select, support cap and pro"
fi
date -Ins