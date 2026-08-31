#!/bin/bash -e

IMAGEARCH=${IMAGEARCH:-linux/amd64}
BACKEND=${BACKEND:-docker}
RELEASE=${RELEASE:-:latest}
REGISTRY_PORT=${PORT:-"5000"} # registry port
REGISTRY_IP="10.67.115.219" # default registry
OLD_DOCKER_REGISTRY="${REGISTRY_IP}:${REGISTRY_PORT}/"
REGISTRY=${REGISTRY:-"$REGISTRY_IP:$REGISTRY_PORT/"}
TIMEOUT="7200,3600"  # Wait for log collection | WAIT POD ready timeout, seconds
NAMESPACE=${NAMESPACE:-"default"}
POD_SELECTOR_CONTAINER="telemetry-daemon"
POD_SELECTOR=${POD_SELECTOR:-"app=$POD_SELECTOR_CONTAINER"}
BENCHMARK_LOGS=${BENCHMARK_LOGS:-"logs"}

CASENAME=${CASENAME:-""}

if [ "$CASENAME" == "" ]; then
    LOGPATH_SUFFIX=""
else 
    LOGPATH_SUFFIX="-$CASENAME"
fi

BENCHMARK_NODES=${BENCHMARK_NODES:-3}

# input parameters:
TOP_GREP=${TOP_GREP:-'ceph|fio|kubelet|reactor|qemu|vhost|build|softir'}

duration=100  # 100 seconds
delay_run=10  # 10 seconds
logpath=""
stop_function=0
job_function="telemetry"

DIR="$( cd "$( dirname "$0" )" &> /dev/null && pwd )"

# TODO:
# currently only build telemetry iamge
PRO_CONFIG_PATH="${DIR}/config"
WORK_PATH="${DIR}/deploy/telemetry"
LOG_PATH="${DIR}/logs"
dir_prefix="$(date +%m%d-%H%M%S)-logs${LOGPATH_SUFFIX}"
BENCHMARK_LOGS="${LOG_PATH}/${dir_prefix}/"
#mkdir -p $BENCHMARK_LOGS

function help_usage() {
  echo "--deploy      		Deploy the performance kit"
  echo "--telem       		Run telemetry."
  echo "--benchmark   		Deploy and run benchmark, the testcase depends on env"
  echo "--cleanup     		Clean up the environment"
  echo "--all         		[Default]Deploy the cluster and benchmark, and will cleanup environment."
  echo "--delay_run=<var>   Set the delay duration before real run, unit=second"
  echo "--duration=<var>    Set the time duration for logs callection, unit=second"
  echo "--logpath=<var>     set where to put the logs path"
  echo "--label=<var>       Run the telemetry on the node which have the label"
  echo "--stop              To stop the previouse function"
  echo "--help        		Show help tips"
}


# args: 
#   $1 - benchmark container name
#   $2 ~~ - pods run the benchmark. 
extract_logs () {

    container=$1; shift
    for pod1 in $@; do
        echo "get benchmark pod $pod1"
        # mkdir -p "$pod1"
        # kubectl exec --namespace=$CEPH_CLUSTER_NS $pod1 -c $container -- bash -c 'cat /export-test-logs' | tar -xf - -C "$pod1"        
        kubectl exec --namespace=$NAMESPACE $pod1 -c $container -- bash -c 'cat /export-logs' | tar -xf - -C "$BENCHMARK_LOGS"
    done
}

# arg1 = config_path
# arg2 = function
rebuild_yaml () {
    CONFIGPATH=$1
    FUNCTION=$2

    for m4file in `find ${DIR}/ -name "${FUNCTION}*.yaml"`
    do 
        #echo "transfer $m4file"  # m4file is the file name with path.
        m4 -DCONFIGURATION_OPTIONS=$CONFIGURATION_OPTIONS \
        "$m4file" > "${m4file}"
    done
}

function run_telemetry() {

    code_path="${DIR}"

    # rebuild the yaml file for deploy.
    # rebuild_yaml ${code_path} ${job_function}

    # -- Start the deployment.
    echo "- Start the telemetry daemonset deployment "
    kubectl apply -n $NAMESPACE -f ${WORK_PATH}/telemetry-daemon.yaml
    sleep 5s
    kubectl --namespace=$NAMESPACE wait pod --for=condition=ready --selector=${POD_SELECTOR} --timeout=${TIMEOUT/*,/}s
    echo "- telemetry-daemonset POD is ready "


    # -- Collect the logs from benchmark pod.
    echo "- Collect benchmark logs "
    export BENCHMARK_LOGS  NAMESPACE POD_SELECTOR
    export -pf extract_logs

    echo "- Waiting for the telemtry implementation... "
    if [ "${BENCHMARK_NODES}" == "1" ]; then 
        timeout ${TIMEOUT/,*/}s bash -c "extract_logs ${POD_SELECTOR_CONTAINER} $(kubectl get pod --namespace=$NAMESPACE --selector="$POD_SELECTOR" -o=jsonpath="{.items[*].metadata.name}")"
    else

        # # Prepare stage for work PODs 
        # for work_pod in $(kubectl -n "${NAMESPACE}" get pod --selector="$POD_SELECTOR" -o jsonpath='{.items[*].metadata.name}'); do

        #     mkdir -p ${BENCHMARK_LOGS}/${work_pod}
        #     echo " - Waiting for POD ${work_pod} initialization..."
        #     timeout ${TIMEOUT/*,/}s kubectl -n ${NAMESPACE} exec ${work_pod} -- bash -c 'cat /export-logs' | tar -xf - -C "${BENCHMARK_LOGS}/${work_pod}"

        #     if [ "$?" != "0" ]; then
        #         echo "*** WARNING: POD ${work_pod} is not prepared for running test!"
        #         kubectl -n ${NAMESPACE} describe pod "${work_pod}" > "${BENCHMARK_LOGS}"/"${work_pod}"/"$work_pod".desc
        #         kubectl -n ${NAMESPACE} logs "${work_pod}" > "${BENCHMARK_LOGS}"/"${work_pod}"/"$work_pod".log
        #     fi

        # done

        # # Trigger to start work, and collect data 
        # echo " - Trigger the POD to start the work..."
        # touch _start_
        # for work_pod in $(kubectl -n "${NAMESPACE}" get pod --selector="$POD_SELECTOR" -o jsonpath='{.items[*].metadata.name}'); do
        #     timeout ${TIMEOUT/*,/}s kubectl -n ${NAMESPACE} cp ./_start_ ${work_pod}:/
        # done

        # sleep $delay_run
        # sleep $duration

        full_time=$((${delay_run} + ${duration}))
        i=0
        telem_work_config=/opt/telemetry/tools/telemetry.conf

        while [ $i -le $full_time ]
        do
            source ${PRO_CONFIG_PATH}/config.conf
            if [ "$force_end" == "1" ]; then
                for work_pod in $(kubectl -n "${NAMESPACE}" get pod --selector="$POD_SELECTOR" -o jsonpath='{.items[*].metadata.name}'); do
                    echo " - Force stop the job ${work_pod}..."
                    timeout 10s kubectl -n ${NAMESPACE} exec ${work_pod} -- bash -c "echo 'force_end=1' >> ${telem_work_config}"
                done

                # restore the config files
                sed -i '/force_end=1/d' ${PRO_CONFIG_PATH}/config.conf
                break
            fi
            sleep 3s
            # echo -n "."
            i=$(($i + 3))
        done

        echo "Done, Time's up!!"
        # Collecting data and stop the jobs
        for work_pod in $(kubectl -n "${NAMESPACE}" get pod --selector="$POD_SELECTOR" -o jsonpath='{.items[*].metadata.name}'); do
            echo " - Collecting data from work POD ${work_pod}..."
            Nodename="$(kubectl -n "${NAMESPACE}" get pod ${work_pod} -o wide | grep ${work_pod} | awk '{print $7}')"
            pod_log_path="${BENCHMARK_LOGS}/${work_pod}-${Nodename}"
            mkdir -p ${pod_log_path}
            timeout ${TIMEOUT/,*/}s kubectl -n ${NAMESPACE} exec ${work_pod} -- bash -c 'cat /export-logs' | tar -xf - -C "${pod_log_path}"
            # mkdir -p ${BENCHMARK_LOGS}/${work_pod}
            # timeout ${TIMEOUT/,*/}s kubectl -n ${NAMESPACE} exec ${work_pod} -- bash -c 'cat /export-logs' | tar -xf - -C "${BENCHMARK_LOGS}/${work_pod}"

        done

    fi

    # -- cleanup
    echo "End of log collection, delete the work pods..."
    kubectl -n $NAMESPACE delete -f ${WORK_PATH}/telemetry-daemon.yaml
    sleep 5s

}

# arg1 = parameter
# output = the parameter value without unit
# input: 10s, output: 10
function handle_parameters () {

    input=$1

    if [ -z "${input//[0-9]/}" ]; then
       value=${input}
    else
        unit=${input#${input%?}}
        value=${input%${unit}}
    fi
    echo $value
}

function entrypoint() {
    # Parse the parameter for the main entrypoint.
    echo $*
    if [[ $# == 0 || $* =~ ^"--help"$ ]]; then
      help_usage;
      exit 0;
    fi 

    if [[ $* =~ "--all" ]]; then
      export OPERATOR_ARG="ALL";    # 
    elif [[ $* =~ "--deploy" ]];then
      export OPERATOR_ARG="DEPLOY";
    elif [[ $* =~ "--benchmark" ]];then
      export OPERATOR_ARG="BENCH";
    elif [[ $* =~ "--cleanup" ]];then
      export OPERATOR_ARG="CLEANUP";
    elif [[ $* =~ "--telem" ]];then
      export OPERATOR_ARG="TELEM";
      WORK_PATH="${DIR}/deploy/telemetry"
#      run_telemetry
    else
      echo "please see --help";
      help_usage;
      exit 0;
    fi


    for var in "$@"; do
        case "$var" in
        --logpath=*)
            logpath="${var/--logpath=/}"
            BENCHMARK_LOGS="${logpath}/${dir_prefix}"
            # mkdir -p $BENCHMARK_LOGS
            ;;
        --duration=*)
            duration="${var/--duration=/}"
            duration=$(handle_parameters ${duration})
            ;;
        --delay_run=*)
            delay_run="${var/--delay_run=/}"
            delay_run=$(handle_parameters ${delay_run})
            echo $delay_run
            ;;
        --stop)
            stop_function=1
            ;;
        esac
    done

# Set the configuration options for environment and tools setup. pass through with one parmeter to workload.
CONFIGURATION_OPTIONS="-DNODE_SELECT=$NODE_SELECT;\
-DDEVICE_SELECT=$DEVICE_SELECT;\
-DDELAY_RUN=$delay_run;\
-DTOP_GREP=$TOP_GREP;\
-DDURATION=$duration;"

echo ${CONFIGURATION_OPTIONS}

    if [ "${stop_function}" == "0" ]; then
        echo "*** Will not build.***"
        CONFIGURATION_OPTIONS="${CONFIGURATION_OPTIONS}" \
        bash ${DIR}/build.sh ${WORK_PATH} # specify build path which contains the dockerfile and yaml files.
    fi

    if [ OPERATOR_ARG=="TELEM" ]; then
        job_function="telemetry"
        if [ "${stop_function}" == "1" ]; then
            echo "force_end=1" >> ${PRO_CONFIG_PATH}/config.conf
            echo "*** Notify the function [${job_function}] to stop ***"
            echo " -- please wait ..."

            sleep 10s
            kubectl -n $NAMESPACE get pods -A -o wide | grep  ${job_function}
            exit 0
        fi
        mkdir -p $BENCHMARK_LOGS
        #cd ${WORK_PATH}
        run_telemetry
    fi

}

# Parse the arguments .
entrypoint $*

