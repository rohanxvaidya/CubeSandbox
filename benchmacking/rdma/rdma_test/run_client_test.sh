#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="${SCRIPT_DIR}/rdma_test_tool"

remote_core_list="1"    # corelist 0-12
server_ip=""
mode="write_bw"
size=4096
iters=2000000
tx_depth=512
cq_mod=64
post_list=16
port=18515
use_rdma_cm=1
start_server=0
server_bind_ip=""
server_ssh_host=""
server_workdir="${SCRIPT_DIR}"
ssh_opts="-o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5"
server_start_timeout=8
ssh_cmd_timeout=10
verbose=0
remote_server_pid=""

usage() {
    cat <<EOF
Usage:
  $(basename "$0") -c <server_ip> [options]

Description:
    RDMA test launcher for client runs.
    By default, it only runs the client side.
    Optionally, it can start the server remotely over SSH before running client.
    If remote server start is enabled, the script will stop that server after test ends.

Required:
  -c, --server-ip <ip>         RDMA server IP

Options:
  -m, --mode <pingpong|write_bw>   Test mode (default: ${mode})
  -S, --size <bytes>               Message size (default: ${size})
    -n, --iters <count>              Iterations; use 0 for infinite run (default: ${iters})
  -q, --tx-depth <count>           Tx depth (default: ${tx_depth})
  -Q, --cq-mod <count>             CQ moderation interval (default: ${cq_mod})
  -l, --post-list <count>          WR chain size per post (default: ${post_list})
  -p, --port <port>                Server port (default: ${port})
      --start-server               Start server on remote host via SSH
      --server-bind-ip <ip>        Server bind IP for -a on server side
      --server-ssh-host <host>     SSH host for remote server launch
      --server-workdir <path>      Server workdir (default: ${server_workdir})
      --ssh-opts <opts>            Extra SSH options (default: ${ssh_opts})
    --server-start-timeout <s>   Reserved startup timeout value (default: ${server_start_timeout})
    --ssh-cmd-timeout <s>        Max seconds for one SSH command (default: ${ssh_cmd_timeout})
      --no-cm                      Disable RDMA CM mode
  -v, --verbose                    Print command before running
  -h, --help                       Show this help

Examples:
  $(basename "$0") -c 192.168.0.2 -m write_bw -S 4096 -n 2000000 -q 512 -Q 64 -l 16
  $(basename "$0") -c 192.168.0.2 -m pingpong -S 4096 -n 1000000
    $(basename "$0") -c 192.168.0.2 --start-server --server-bind-ip 192.168.0.2
EOF
}

die() {
    echo "Error: $*" >&2
    exit 1
}

is_positive_int() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

is_non_negative_int() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

run_ssh_quick() {
    local remote_host="$1"
    local remote_cmd="$2"

    timeout "${ssh_cmd_timeout}s" ssh -n ${ssh_opts} "${remote_host}" "${remote_cmd}"
}

run_ssh_quick_background() {
    local remote_host="$1"
    local remote_cmd="$2"

    nohup ssh -n ${ssh_opts} "${remote_host}" "${remote_cmd}" >/dev/null 2>&1 &
}

check_remote_server_prereqs() {
    local remote_host="$1"
    local check_cmd

    check_cmd="cd '${server_workdir}' && test -x ./rdma_test_tool"
    if ! run_ssh_quick "${remote_host}" "${check_cmd}" >/dev/null 2>&1; then
        die "Remote server tool missing or not executable at ${remote_host}:${server_workdir}/rdma_test_tool"
    fi
}

cleanup_remote_server() {
    if [[ "${start_server}" -ne 1 || -z "${remote_server_pid}" ]]; then
        return 0
    fi

    if [[ "${verbose}" -eq 1 ]]; then
        echo "Stopping remote server on ${server_ssh_host} (pid=${remote_server_pid})"
    fi

    if [[ -n "${remote_server_pid}" ]]; then
        run_ssh_quick "${server_ssh_host}" "kill ${remote_server_pid} >/dev/null 2>&1 || true" >/dev/null 2>&1 || true
    else
        # Fallback cleanup when PID was not captured.
        run_ssh_quick "${server_ssh_host}" "pkill -f 'rdma_test_tool -s -a ${server_bind_ip} -m ${mode} -S ${size} -n ${iters} -q ${tx_depth} -Q ${cq_mod} -l ${post_list} -p ${port}' >/dev/null 2>&1 || true" >/dev/null 2>&1 || true
    fi
}

start_remote_server() {
    local remote_host="$1"
    local bind_ip="$2"
    local cm_flag=""
    local remote_cmd

    if [[ "${use_rdma_cm}" -eq 1 ]]; then
        cm_flag="-R"
    fi

    check_remote_server_prereqs "${remote_host}"

    # Start server in background on remote side and return immediately.
    remote_cmd="cd '${server_workdir}' && numactl -C ${remote_core_list} ./rdma_test_tool -s -a '${bind_ip}' -m '${mode}' -S '${size}' -n '${iters}' -q '${tx_depth}' -Q '${cq_mod}' -l '${post_list}' -p '${port}' ${cm_flag} </dev/null >/tmp/rdma_test_server.log 2>&1 & echo \$! > /tmp/rdma_test_server.pid"

    if [[ "${verbose}" -eq 1 ]]; then
        echo "Starting remote server on ${remote_host} (bind_ip=${bind_ip})"
    fi

#    run_ssh_quick "${remote_host}" "${remote_cmd}" >/dev/null 2>&1 || die "Failed to start remote server on ${remote_host}"
     run_ssh_quick_background "${remote_host}" "${remote_cmd}" 

    # Best effort PID capture. Do not block client startup if unavailable.
    remote_server_pid="$(run_ssh_quick "${remote_host}" "cat /tmp/rdma_test_server.pid 2>/dev/null || true" | tr -d '[:space:]')"
    if [[ -n "${remote_server_pid}" && ! "${remote_server_pid}" =~ ^[0-9]+$ ]]; then
        remote_server_pid=""
    fi

    if [[ "${verbose}" -eq 1 ]]; then
        if [[ -n "${remote_server_pid}" ]]; then
            echo "Remote server started on ${remote_host} (pid=${remote_server_pid})"
        else
            echo "Remote server started on ${remote_host} (pid unknown)"
        fi
        echo "Proceeding to client test immediately"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--server-ip)
            [[ $# -ge 2 ]] || die "Missing value for $1"
            server_ip="$2"
            shift 2
            ;;
        -m|--mode)
            [[ $# -ge 2 ]] || die "Missing value for $1"
            mode="$2"
            shift 2
            ;;
        -S|--size)
            [[ $# -ge 2 ]] || die "Missing value for $1"
            size="$2"
            shift 2
            ;;
        -n|--iters)
            [[ $# -ge 2 ]] || die "Missing value for $1"
            iters="$2"
            shift 2
            ;;
        -q|--tx-depth)
            [[ $# -ge 2 ]] || die "Missing value for $1"
            tx_depth="$2"
            shift 2
            ;;
        -Q|--cq-mod)
            [[ $# -ge 2 ]] || die "Missing value for $1"
            cq_mod="$2"
            shift 2
            ;;
        -l|--post-list)
            [[ $# -ge 2 ]] || die "Missing value for $1"
            post_list="$2"
            shift 2
            ;;
        -p|--port)
            [[ $# -ge 2 ]] || die "Missing value for $1"
            port="$2"
            shift 2
            ;;
        --start-server)
            start_server=1
            shift
            ;;
        --server-bind-ip)
            [[ $# -ge 2 ]] || die "Missing value for $1"
            server_bind_ip="$2"
            shift 2
            ;;
        --server-ssh-host)
            [[ $# -ge 2 ]] || die "Missing value for $1"
            server_ssh_host="$2"
            shift 2
            ;;
        --server-workdir)
            [[ $# -ge 2 ]] || die "Missing value for $1"
            server_workdir="$2"
            shift 2
            ;;
        --ssh-opts)
            [[ $# -ge 2 ]] || die "Missing value for $1"
            ssh_opts="$2"
            shift 2
            ;;
        --server-start-timeout)
            [[ $# -ge 2 ]] || die "Missing value for $1"
            server_start_timeout="$2"
            shift 2
            ;;
        --ssh-cmd-timeout)
            [[ $# -ge 2 ]] || die "Missing value for $1"
            ssh_cmd_timeout="$2"
            shift 2
            ;;
        --no-cm)
            use_rdma_cm=0
            shift
            ;;
        -v|--verbose)
            verbose=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown argument: $1 (use -h for help)"
            ;;
    esac
done

[[ -n "${server_ip}" ]] || die "You must provide -c/--server-ip"
[[ "${mode}" == "pingpong" || "${mode}" == "write_bw" ]] || die "Mode must be pingpong or write_bw"
is_positive_int "${size}" || die "size must be a positive integer"
is_non_negative_int "${iters}" || die "iters must be a non-negative integer"
is_positive_int "${tx_depth}" || die "tx_depth must be a positive integer"
is_positive_int "${cq_mod}" || die "cq_mod must be a positive integer"
is_positive_int "${post_list}" || die "post_list must be a positive integer"
is_positive_int "${port}" || die "port must be a positive integer"
is_positive_int "${server_start_timeout}" || die "server_start_timeout must be a positive integer"
is_positive_int "${ssh_cmd_timeout}" || die "ssh_cmd_timeout must be a positive integer"

[[ -x "${TOOL}" ]] || die "${TOOL} not found or not executable; run 'make' first"

if [[ -z "${server_bind_ip}" ]]; then
    server_bind_ip="${server_ip}"
fi

if [[ -z "${server_ssh_host}" ]]; then
    server_ssh_host="${server_ip}"
fi

trap cleanup_remote_server EXIT

if [[ "${start_server}" -eq 1 ]]; then
    require_cmd ssh
    require_cmd timeout
    start_remote_server "${server_ssh_host}" "${server_bind_ip}"
fi

cmd=(
    "${TOOL}"
    -c "${server_ip}"
    -m "${mode}"
    -S "${size}"
    -n "${iters}"
    -q "${tx_depth}"
    -Q "${cq_mod}"
    -l "${post_list}"
    -p "${port}"
)

if [[ "${use_rdma_cm}" -eq 1 ]]; then
    cmd+=( -R )
fi

if [[ "${verbose}" -eq 1 ]]; then
    printf 'Running:'
    printf ' %q' "${cmd[@]}"
    printf '\n'
fi

set +e
"${cmd[@]}"
rc=$?
set -e

exit ${rc}
