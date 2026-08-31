#!/usr/bin/env bash
set -euo pipefail

###./run_fc_jailer_startup_bench.sh -n 4500 -c 50 --timeout 30  \
#--ready-criteria boottimer -p 1 -m 128 --network off \
#--boot-args "reboot=k panic=1 nomodule 8250.nr_uarts=0 i8042.nomux  i8042.dumbkbd swiotlb=noforce cryptomgr.notests" \
# --official-init-path /usr/local/bin/init --serial-console off

# Keep common sbin/bin locations in PATH even under restrictive sudo secure_path.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

LAB_DIR="/home/mz/firecracker-lab"
CHROOT_BASE="$LAB_DIR/jailer-chroot"
N=10
C=1
TIMEOUT_SEC=20
VCPU=1
MEM_MIB=512
DISK_SIZE_MIB=0
CPU_QUOTA_PERCENT=0
READY_CRITERIA="both"
PREPARE_ROOTFS=0
CHECK_ONLY=0
KEEP_ALIVE=0
OFFICIAL_INIT_PATH=""
SERIAL_CONSOLE="on"
NETWORK_MODE="on"
NETWORK_MODE_SET=0
CUSTOM_BOOT_ARGS=""
OFFICIAL_PROFILE=0
MODE="create-delete"

KERNEL="$LAB_DIR/vmlinux-6.18.36"
ROOTFS="$LAB_DIR/ubuntu-24.04.ext4"
KEYFILE="$LAB_DIR/ubuntu-24.04.id_rsa"
SQUASHFS="$LAB_DIR/ubuntu-24.04.squashfs"
BASE_BOOT_ARGS=""
DEFAULT_BOOT_ARGS="reboot=k panic=1"
OFFICIAL_BOOT_ARGS="reboot=k panic=1 nomodule 8250.nr_uarts=0 i8042.noaux i8042.nomux i8042.nopnp i8042.dumbkbd swiotlb=noforce cryptomgr.notests"

usage() {
  cat <<USAGE
Usage:
  sudo ./run_fc_jailer_startup_bench.sh [options]

Options:
  -n <runs>                    Number of runs (default: 10)
  -c <concurrency>             Number of concurrent startups (default: 1)
  -p, --vcpu <n>               vCPU count (default: 1)
  -m, --mem <mib>              Memory in MiB (default: 512)
  -s, --disk-size-mib <mib>    Sandbox disk size in MiB (0 = source rootfs size)
  --cpu-quota-percent <1-100>  Limit host CPU quota for each sandbox process
  --timeout <sec>              Timeout for readiness checks (default: 20)
  --ready-criteria <mode>      running | network | both | boottimer (default: both)
  --official-init-path <path>  Optional init path used in boottimer mode (e.g. /usr/local/bin/init)
  --official-profile           Apply official-like boot tuning preset
  --mode <mode>                create-delete | create-only (default: create-delete)
  --serial-console <on|off>    Enable/disable serial console boot arg (default: on)
  --network <on|off>           Enable/disable guest TAP+net device (default: on)
  --boot-args "..."            Override boot args completely
  --kernel <path>              Kernel image path (default: $LAB_DIR/vmlinux-6.18.36)
  --rootfs <path>              Rootfs ext4 path (default: $LAB_DIR/ubuntu-24.04.ext4)
  --prepare-rootfs             Build ext4 rootfs and SSH key if missing
  --check-only                 Only run environment checks and exit
  --keep-alive                 Keep sandbox alive after startup check
  -h, --help                   Show this help

Examples:
  sudo ./run_fc_jailer_startup_bench.sh --check-only
  sudo ./run_fc_jailer_startup_bench.sh --prepare-rootfs -n 5 --ready-criteria both
  sudo ./run_fc_jailer_startup_bench.sh -n 10 --ready-criteria boottimer --official-init-path /usr/local/bin/init
  sudo ./run_fc_jailer_startup_bench.sh --official-profile -n 20
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n)
      N="$2"; shift 2 ;;
    -c)
      C="$2"; shift 2 ;;
    -p|--vcpu)
      VCPU="$2"; shift 2 ;;
    -m|--mem)
      MEM_MIB="$2"; shift 2 ;;
    -s|--disk-size-mib)
      DISK_SIZE_MIB="$2"; shift 2 ;;
    --cpu-quota-percent)
      CPU_QUOTA_PERCENT="$2"; shift 2 ;;
    --timeout)
      TIMEOUT_SEC="$2"; shift 2 ;;
    --ready-criteria)
      READY_CRITERIA="$2"; shift 2 ;;
    --official-init-path)
      OFFICIAL_INIT_PATH="$2"; shift 2 ;;
    --official-profile)
      OFFICIAL_PROFILE=1; shift ;;
    --mode)
      MODE="$2"; shift 2 ;;
    --serial-console)
      SERIAL_CONSOLE="$2"; shift 2 ;;
    --network)
      NETWORK_MODE="$2"; NETWORK_MODE_SET=1; shift 2 ;;
    --boot-args)
      CUSTOM_BOOT_ARGS="$2"; shift 2 ;;
    --kernel)
      KERNEL="$2"; shift 2 ;;
    --rootfs)
      ROOTFS="$2"; shift 2 ;;
    --prepare-rootfs)
      PREPARE_ROOTFS=1; shift ;;
    --check-only)
      CHECK_ONLY=1; shift ;;
    --keep-alive)
      KEEP_ALIVE=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "[error] unknown argument: $1"
      usage
      exit 1 ;;
  esac
done

is_non_negative_integer() {
  local v="$1"
  [[ "$v" =~ ^[0-9]+$ ]]
}

is_positive_integer() {
  local v="$1"
  [[ "$v" =~ ^[1-9][0-9]*$ ]]
}

if ! is_positive_integer "$N"; then
  echo "[error] -n must be >= 1"
  exit 1
fi
if ! is_positive_integer "$C"; then
  echo "[error] -c must be >= 1"
  exit 1
fi
if [[ "$C" -gt "$N" ]]; then
  C="$N"
fi
if ! is_positive_integer "$TIMEOUT_SEC"; then
  echo "[error] --timeout must be >= 1"
  exit 1
fi
if ! is_positive_integer "$VCPU"; then
  echo "[error] --vcpu must be a positive integer (Firecracker does not support fractional vCPU, e.g. 0.5)"
  exit 1
fi
if ! is_positive_integer "$MEM_MIB"; then
  echo "[error] --mem must be >= 1"
  exit 1
fi
if ! is_non_negative_integer "$DISK_SIZE_MIB"; then
  echo "[error] --disk-size-mib must be >= 0"
  exit 1
fi
if ! is_non_negative_integer "$CPU_QUOTA_PERCENT"; then
  echo "[error] --cpu-quota-percent must be an integer in range 0..100"
  exit 1
fi
if [[ "$CPU_QUOTA_PERCENT" -gt 100 ]]; then
  echo "[error] --cpu-quota-percent must be <= 100"
  exit 1
fi
if [[ "$READY_CRITERIA" != "running" && "$READY_CRITERIA" != "network" && "$READY_CRITERIA" != "both" && "$READY_CRITERIA" != "boottimer" ]]; then
  echo "[error] --ready-criteria must be one of: running, network, both, boottimer"
  exit 1
fi
if [[ "$SERIAL_CONSOLE" != "on" && "$SERIAL_CONSOLE" != "off" ]]; then
  echo "[error] --serial-console must be one of: on, off"
  exit 1
fi
if [[ "$MODE" != "create-delete" && "$MODE" != "create-only" ]]; then
  echo "[error] --mode must be one of: create-delete, create-only"
  exit 1
fi
if [[ "$NETWORK_MODE" != "on" && "$NETWORK_MODE" != "off" ]]; then
  echo "[error] --network must be one of: on, off"
  exit 1
fi

if [[ "$OFFICIAL_PROFILE" -eq 1 ]]; then
  READY_CRITERIA="boottimer"
  VCPU=1
  MEM_MIB=128
  SERIAL_CONSOLE="off"
  NETWORK_MODE="off"
  if [[ -z "$OFFICIAL_INIT_PATH" ]]; then
    OFFICIAL_INIT_PATH="/usr/local/bin/init"
  fi
fi

if [[ "$READY_CRITERIA" == "boottimer" && "$NETWORK_MODE_SET" -eq 0 ]]; then
  NETWORK_MODE="off"
fi

if [[ "$MODE" == "create-only" ]]; then
  KEEP_ALIVE=1
fi

if [[ "$NETWORK_MODE" == "off" && ( "$READY_CRITERIA" == "network" || "$READY_CRITERIA" == "both" ) ]]; then
  echo "[error] --network off is incompatible with --ready-criteria $READY_CRITERIA"
  exit 1
fi

if [[ -n "$CUSTOM_BOOT_ARGS" ]]; then
  BASE_BOOT_ARGS="$CUSTOM_BOOT_ARGS"
elif [[ "$OFFICIAL_PROFILE" -eq 1 ]]; then
  BASE_BOOT_ARGS="$OFFICIAL_BOOT_ARGS"
else
  BASE_BOOT_ARGS="$DEFAULT_BOOT_ARGS"
  if [[ "$SERIAL_CONSOLE" == "on" ]]; then
    BASE_BOOT_ARGS="console=ttyS0 $BASE_BOOT_ARGS"
  else
    BASE_BOOT_ARGS="${BASE_BOOT_ARGS} 8250.nr_uarts=0"
  fi
fi

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "[error] please run as root (sudo)"
    exit 1
  fi
}

check_binary() {
  local b="$1"
  if command -v "$b" >/dev/null 2>&1; then
    true
  else
    echo "[error] missing binary: $b"
    return 1
  fi
}

check_file_optional() {
  local f="$1"
  if [[ -f "$f" ]]; then
    true
    return 0
  fi
  echo "[error] file missing: $f"
  return 1
}

get_file_size_mib() {
  local f="$1"
  local bytes
  bytes=$(stat -c '%s' "$f")
  echo $(( (bytes + 1048575) / 1048576 ))
}

resolve_binary() {
  local b="$1"
  local cand=""

  if cand=$(command -v "$b" 2>/dev/null); then
    echo "$cand"
    return 0
  fi

  for cand in "/usr/local/bin/$b" "/usr/bin/$b" "/bin/$b"; do
    if [[ -x "$cand" ]]; then
      echo "$cand"
      return 0
    fi
  done

  return 1
}

detect_cgroup_version() {
  if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
    echo 2
  else
    echo 1
  fi
}

prepare_rootfs_if_needed() {
  if [[ -f "$ROOTFS" && -f "$KEYFILE" ]]; then
    return 0
  fi

  if [[ "$PREPARE_ROOTFS" -ne 1 ]]; then
    return 1
  fi

  if [[ ! -f "$SQUASHFS" ]]; then
    echo "[error] cannot prepare rootfs: squashfs missing: $SQUASHFS"
    return 1
  fi

  echo "[prep] building ext4 rootfs and ssh key from squashfs"
  pushd "$LAB_DIR" >/dev/null
  rm -rf squashfs-root id_rsa id_rsa.pub
  unsquashfs -f ubuntu-24.04.squashfs >/tmp/fc_unsquashfs.log 2>&1
  ssh-keygen -q -t rsa -b 2048 -f id_rsa -N ""
  mkdir -p squashfs-root/root/.ssh
  cp -f id_rsa.pub squashfs-root/root/.ssh/authorized_keys
  mv -f id_rsa ubuntu-24.04.id_rsa
  chmod 600 ubuntu-24.04.id_rsa
  chown -R root:root squashfs-root
  truncate -s 1G ubuntu-24.04.ext4
  mkfs.ext4 -q -d squashfs-root -F ubuntu-24.04.ext4
  popd >/dev/null

  echo "[ok] prepared rootfs and key"
}

check_environment() {
  local ok=1
  local firecracker_path=""
  local jailer_path=""
  local need_tap=0

  require_root

  firecracker_path="$(resolve_binary firecracker || true)"
  jailer_path="$(resolve_binary jailer || true)"

  if [[ -z "$firecracker_path" ]]; then
    echo "[error] missing binary: firecracker"
    ok=0
  fi

  if [[ -z "$jailer_path" ]]; then
    echo "[error] missing binary: jailer"
    ok=0
  fi

  for b in curl jq unsquashfs mkfs.ext4; do
    check_binary "$b" || ok=0
  done

  if [[ "$NETWORK_MODE" == "on" ]]; then
    need_tap=1
    for b in ip ssh; do
      check_binary "$b" || ok=0
    done
  fi

  if [[ ! -c /dev/kvm ]]; then
    echo "[error] /dev/kvm missing"
    ok=0
  fi

  if [[ "$need_tap" -eq 1 ]]; then
    if [[ ! -c /dev/net/tun ]]; then
      echo "[error] /dev/net/tun missing"
      ok=0
    fi

    if ip tuntap add dev tap99 mode tap >/dev/null 2>&1; then
      ip link del tap99 >/dev/null 2>&1 || true
    else
      echo "[error] TAP create failed"
      ok=0
    fi
  fi

  check_file_optional "$KERNEL" || ok=0

  if [[ ! -f "$ROOTFS" || ! -f "$KEYFILE" ]]; then
    if ! prepare_rootfs_if_needed; then
      ok=0
    fi
  fi

  if [[ "$ok" -ne 1 ]]; then
    return 1
  fi
  return 0
}

progress_line() {
  local ok_count="$1"
  local err_count="$2"
  local total="$3"
  printf "\rprogress: %d/%d errors: %d" "$ok_count" "$total" "$err_count"
}

calc_metric_stats() {
  local csv_file="$1"
  local column_index="$2"

  awk -F, -v col="$column_index" '
    NR == 1 { next }
    $col ~ /^[0-9]+$/ {
      print $col
    }
  ' "$csv_file" | sort -n | awk '
    {
      values[++count] = $1
      sum += $1
    }
    END {
      if (count == 0) {
        print "0,0,0,0,0"
        exit
      }

      p95_idx = int(((count - 1) * 95) / 100) + 1
      p99_idx = int(((count - 1) * 99) / 100) + 1

      if (p95_idx < 1) p95_idx = 1
      if (p99_idx < 1) p99_idx = 1
      if (p95_idx > count) p95_idx = count
      if (p99_idx > count) p99_idx = count

      printf "%.2f,%d,%d,%d,%d\n", sum / count, values[p95_idx], values[p99_idx], values[1], values[count]
    }
  '
}

run_one() {
  local idx="$1"
  local id="jvm$(printf '%04d' "$idx")"
  local vm_dir="$CHROOT_BASE/firecracker/$id"
  local root_dir="$vm_dir/root"
  local socket_rel="api.socket"
  local socket_host="$root_dir/$socket_rel"

  local tap_dev="tj$(printf '%04d' "$idx")"
  local tap_ip=""
  local guest_ip=""
  local guest_mac=""
  local boot_args="$BASE_BOOT_ARGS"

  local fc_bin=""
  local jailer_bin=""
  local fc_pid=""
  local state_ms=""
  local net_ms=""
  local official_ms=""
  local status="ok"
  local note=""
  local quota_us=""
  local need_official=0
  local need_network_probe=0
  local need_network_device=0
  local -a jailer_extra_args=()

  local stdout_log="$OUT_DIR/${id}.stdout.log"
  local row_file="$OUT_DIR/tmp/${id}.row"

  fc_bin="$(resolve_binary firecracker || true)"
  jailer_bin="$(resolve_binary jailer || true)"
  if [[ -z "$fc_bin" ]]; then
    echo "$idx,$id,,,,fail,firecracker_not_found,$READY_CRITERIA" >"$row_file"
    return 0
  fi
  if [[ -z "$jailer_bin" ]]; then
    echo "$idx,$id,,,,fail,jailer_not_found,$READY_CRITERIA" >"$row_file"
    return 0
  fi

  if [[ "$CPU_QUOTA_PERCENT" -gt 0 ]]; then
    quota_us=$(( CPU_QUOTA_PERCENT * 1000 ))
    if [[ "$EFFECTIVE_CGROUP_VERSION" -eq 2 ]]; then
      jailer_extra_args+=("--cgroup-version" "2")
      jailer_extra_args+=("--cgroup" "cpu.max=${quota_us} 100000")
    else
      jailer_extra_args+=("--cgroup-version" "1")
      jailer_extra_args+=("--cgroup" "cpu.cfs_period_us=100000")
      jailer_extra_args+=("--cgroup" "cpu.cfs_quota_us=${quota_us}")
    fi
  fi

  if [[ "$READY_CRITERIA" == "boottimer" ]]; then
    need_official=1
  fi

  if [[ "$READY_CRITERIA" == "network" || "$READY_CRITERIA" == "both" ]]; then
    need_network_probe=1
  fi

  if [[ "$NETWORK_MODE" == "on" ]]; then
    need_network_device=1
  fi

  rm -rf "$vm_dir"
  mkdir -p "$root_dir"
  cp -f "$KERNEL" "$root_dir/vmlinux"
  cp -f "$ROOTFS" "$root_dir/rootfs.ext4"

  if [[ "$DISK_SIZE_MIB" -gt 0 ]]; then
    truncate -s "${DISK_SIZE_MIB}M" "$root_dir/rootfs.ext4" || {
      status="fail"
      note="disk_resize_failed"
    }
  fi

  boot_args="$BASE_BOOT_ARGS"
  if [[ "$need_official" -eq 1 && -n "$OFFICIAL_INIT_PATH" ]]; then
    boot_args+=" init=${OFFICIAL_INIT_PATH}"
  fi

  if [[ "$need_network_device" -eq 1 ]]; then
    local third fourth_base
    third=$(( (idx * 4) / 256 ))
    fourth_base=$(( (idx * 4) % 256 ))
    if [[ "$third" -gt 254 ]]; then
      status="fail"
      note="subnet_exhausted"
    fi

    if [[ "$status" == "ok" ]]; then
      tap_ip="172.23.${third}.$((fourth_base + 1))"
      guest_ip="172.23.${third}.$((fourth_base + 2))"
      printf -v guest_mac "06:00:ac:17:%02x:%02x" "$third" "$((fourth_base + 2))"
      boot_args+=" ip=${guest_ip}::${tap_ip}:255.255.255.252::eth0:off"

      ip link del "$tap_dev" >/dev/null 2>&1 || true
      ip tuntap add dev "$tap_dev" mode tap || { status="fail"; note="tap_create_failed"; }
    fi

    if [[ "$status" == "ok" ]]; then
      ip addr add "${tap_ip}/30" dev "$tap_dev" || { status="fail"; note="tap_addr_failed"; }
    fi
    if [[ "$status" == "ok" ]]; then
      ip link set dev "$tap_dev" up || { status="fail"; note="tap_up_failed"; }
    fi
  fi

  if [[ "$status" == "ok" ]]; then
    "$jailer_bin" \
      --id "$id" \
      --exec-file "$fc_bin" \
      --uid 0 --gid 0 \
      --chroot-base-dir "$CHROOT_BASE" \
      "${jailer_extra_args[@]}" \
      -- \
      $([[ "$need_official" -eq 1 ]] && echo "--boot-timer") \
      --api-sock "$socket_rel" \
      --no-seccomp >"$stdout_log" 2>&1 &
    fc_pid=$!

    for _ in $(seq 1 500); do
      [[ -S "$socket_host" ]] && break
      sleep 0.02
    done
    if [[ ! -S "$socket_host" ]]; then
      status="fail"
      note="socket_not_ready"
    fi
  fi

  if [[ "$status" == "ok" ]]; then
    curl -sS -X PUT --unix-socket "$socket_host" -H 'Content-Type: application/json' \
      --data "{\"vcpu_count\":${VCPU},\"mem_size_mib\":${MEM_MIB}}" \
      http://localhost/machine-config >/dev/null || { status="fail"; note="machine_config_failed"; }
  fi

  if [[ "$status" == "ok" ]]; then
    curl -sS -X PUT --unix-socket "$socket_host" -H 'Content-Type: application/json' \
      --data "{\"kernel_image_path\":\"/vmlinux\",\"boot_args\":\"${boot_args}\"}" \
      http://localhost/boot-source >/dev/null || { status="fail"; note="boot_source_failed"; }
  fi

  if [[ "$status" == "ok" ]]; then
    curl -sS -X PUT --unix-socket "$socket_host" -H 'Content-Type: application/json' \
      --data '{"drive_id":"rootfs","path_on_host":"/rootfs.ext4","is_root_device":true,"is_read_only":true}' \
      http://localhost/drives/rootfs >/dev/null || { status="fail"; note="drive_failed"; }
  fi

  if [[ "$status" == "ok" && "$need_network_device" -eq 1 ]]; then
    curl -sS -X PUT --unix-socket "$socket_host" -H 'Content-Type: application/json' \
      --data "{\"iface_id\":\"net1\",\"guest_mac\":\"${guest_mac}\",\"host_dev_name\":\"${tap_dev}\"}" \
      http://localhost/network-interfaces/net1 >/dev/null || { status="fail"; note="net_if_failed"; }
  fi

  local start_ns=""
  if [[ "$status" == "ok" ]]; then
    start_ns=$(date +%s%N)
    curl -sS -X PUT --unix-socket "$socket_host" -H 'Content-Type: application/json' \
      --data '{"action_type":"InstanceStart"}' \
      http://localhost/actions >/dev/null || { status="fail"; note="instance_start_failed"; }
  fi

  if [[ "$status" == "ok" ]]; then
    local running_seen=0
    local network_seen=0
    local official_seen=0
    local deadline
    deadline=$(( $(date +%s) + TIMEOUT_SEC ))

    while [[ $(date +%s) -lt "$deadline" ]]; do
      if [[ "$running_seen" -eq 0 ]]; then
        local state
        state=$(curl -sS --unix-socket "$socket_host" http://localhost/ 2>/dev/null | jq -r '.state // empty')
        if [[ "$state" == "Running" ]]; then
          running_seen=1
          state_ms=$(( ($(date +%s%N) - start_ns) / 1000000 ))
        fi
      fi

      if [[ "$need_network_probe" -eq 1 && "$network_seen" -eq 0 ]]; then
        if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=1 -i "$KEYFILE" root@"$guest_ip" 'echo vm_net_ready' >/dev/null 2>&1; then
          network_seen=1
          net_ms=$(( ($(date +%s%N) - start_ns) / 1000000 ))
        fi
      fi

      if [[ "$need_official" -eq 1 && "$official_seen" -eq 0 ]]; then
        local boot_us
        boot_us=$(sed -n 's/.*Guest-boot-time = *\([0-9][0-9]*\) us.*/\1/p' "$stdout_log" | head -n1)
        if [[ -n "$boot_us" ]]; then
          official_seen=1
          official_ms=$(( boot_us / 1000 ))
        fi
      fi

      case "$READY_CRITERIA" in
        running)
          [[ "$running_seen" -eq 1 ]] && break ;;
        network)
          [[ "$network_seen" -eq 1 ]] && break ;;
        both)
          [[ "$running_seen" -eq 1 && "$network_seen" -eq 1 ]] && break ;;
        boottimer)
          [[ "$official_seen" -eq 1 ]] && break ;;
      esac

      sleep 0.05
    done

    case "$READY_CRITERIA" in
      running)
        [[ "$running_seen" -eq 1 ]] || { status="fail"; note="running_timeout"; }
        ;;
      network)
        [[ "$network_seen" -eq 1 ]] || { status="fail"; note="network_timeout"; }
        ;;
      both)
        if [[ "$running_seen" -ne 1 && "$network_seen" -ne 1 ]]; then
          status="fail"; note="running_and_network_timeout"
        elif [[ "$running_seen" -ne 1 ]]; then
          status="fail"; note="running_timeout"
        elif [[ "$network_seen" -ne 1 ]]; then
          status="fail"; note="network_timeout"
        fi
        ;;
      boottimer)
        [[ "$official_seen" -eq 1 ]] || { status="fail"; note="official_timeout_or_no_boot_timer_signal"; }
        ;;
    esac
  fi

  if [[ "$KEEP_ALIVE" -eq 1 ]]; then
    if [[ -n "$note" ]]; then
      note="${note}|kept_alive"
    else
      note="kept_alive"
    fi
  else
    if [[ -S "$socket_host" ]]; then
      curl -sS -X PUT --unix-socket "$socket_host" -H 'Content-Type: application/json' \
        --data '{"action_type":"SendCtrlAltDel"}' \
        http://localhost/actions >/dev/null 2>&1 || true
    fi

    if [[ -n "$fc_pid" ]]; then
      for _ in $(seq 1 100); do
        if ! kill -0 "$fc_pid" 2>/dev/null; then
          break
        fi
        sleep 0.05
      done
      kill "$fc_pid" >/dev/null 2>&1 || true
      wait "$fc_pid" >/dev/null 2>&1 || true
    fi

    if [[ "$need_network_device" -eq 1 ]]; then
      ip link del "$tap_dev" >/dev/null 2>&1 || true
    fi
    rm -rf "$vm_dir"
  fi

  echo "$idx,$id,${state_ms},${net_ms},${official_ms},$status,$note,$READY_CRITERIA" >"$row_file"
}

check_environment
if [[ "$CHECK_ONLY" -eq 1 ]]; then
  exit 0
fi

if [[ ! -f "$ROOTFS" || ! -f "$KEYFILE" ]]; then
  echo "[error] rootfs/key still missing. Use --prepare-rootfs first."
  exit 1
fi

ROOTFS_SIZE_MIB=$(get_file_size_mib "$ROOTFS")
if [[ "$DISK_SIZE_MIB" -gt 0 && "$DISK_SIZE_MIB" -lt "$ROOTFS_SIZE_MIB" ]]; then
  echo "[error] --disk-size-mib (${DISK_SIZE_MIB}) cannot be smaller than source rootfs size (${ROOTFS_SIZE_MIB} MiB)"
  exit 1
fi

EFFECTIVE_DISK_MIB="$ROOTFS_SIZE_MIB"
if [[ "$DISK_SIZE_MIB" -gt 0 ]]; then
  EFFECTIVE_DISK_MIB="$DISK_SIZE_MIB"
fi

EFFECTIVE_CGROUP_VERSION=0
if [[ "$CPU_QUOTA_PERCENT" -gt 0 ]]; then
  EFFECTIVE_CGROUP_VERSION=$(detect_cgroup_version)
fi

OUT_DIR="$LAB_DIR/results-jailer-startup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT_DIR/tmp" "$CHROOT_BASE"

ok_done=0
err_done=0
if [[ "$CPU_QUOTA_PERCENT" -gt 0 ]]; then
  echo "[info] cpu quota enabled: ${CPU_QUOTA_PERCENT}% (cgroup v${EFFECTIVE_CGROUP_VERSION})"
fi
if [[ "$MODE" == "create-only" ]]; then
  echo "[info] mode=create-only: sandboxes will be kept after startup checks"
fi
batch_start_ns=$(date +%s%N)
for i in $(seq 1 "$N"); do
  run_one "$i" &

  # Throttle background jobs to at most C concurrent startups.
  while [[ "$(jobs -pr | wc -l)" -ge "$C" ]]; do
    wait -n || true
    ok_done=$(awk -F, '$6=="ok"{c++} END{print c+0}' "$OUT_DIR"/tmp/*.row 2>/dev/null || echo 0)
    total_done=$(find "$OUT_DIR/tmp" -maxdepth 1 -name '*.row' | wc -l)
    err_done=$((total_done - ok_done))
    progress_line "$ok_done" "$err_done" "$N"
  done
done
while [[ "$(jobs -pr | wc -l)" -gt 0 ]]; do
  wait -n || true
  ok_done=$(awk -F, '$6=="ok"{c++} END{print c+0}' "$OUT_DIR"/tmp/*.row 2>/dev/null || echo 0)
  total_done=$(find "$OUT_DIR/tmp" -maxdepth 1 -name '*.row' | wc -l)
  err_done=$((total_done - ok_done))
  progress_line "$ok_done" "$err_done" "$N"
done
printf "\n"
batch_end_ns=$(date +%s%N)
batch_total_ms=$(( (batch_end_ns - batch_start_ns) / 1000000 ))

echo "run,vm_id,state_running_ms,network_ready_ms,official_boot_ms,status,note,ready_criteria" >"$OUT_DIR/startup-benchmark.csv"
cat "$OUT_DIR"/tmp/*.row | sort -t, -k1,1n >>"$OUT_DIR/startup-benchmark.csv"

stats_line=$(awk -F, '
  NR==1 {next}
  {
    total++
    if ($6=="ok") ok++
    else fail++
  }
  END {
    printf "%d,%d,%d\n", total, ok, fail
  }
' "$OUT_DIR/startup-benchmark.csv")

IFS=',' read -r total ok fail <<<"$stats_line"

IFS=',' read -r s_avg s_p95 s_p99 s_min s_max <<<"$(calc_metric_stats "$OUT_DIR/startup-benchmark.csv" 3)"
IFS=',' read -r n_avg n_p95 n_p99 n_min n_max <<<"$(calc_metric_stats "$OUT_DIR/startup-benchmark.csv" 4)"
IFS=',' read -r o_avg o_p95 o_p99 o_min o_max <<<"$(calc_metric_stats "$OUT_DIR/startup-benchmark.csv" 5)"

batch_total_sec=$(awk -v ms="$batch_total_ms" 'BEGIN { printf("%.3f", ms/1000) }')
avg_throughput=$(awk -v ok="$ok" -v ms="$batch_total_ms" 'BEGIN { if (ms > 0) printf("%.3f", ok / (ms / 1000)); else printf("0.000") }')

{
  printf "summary: total ok=%s fail=%s total_latency_ms=%s total_latency_sec=%s avg_throughput_per_sec=%s\n" \
    "$ok" "$fail" "$batch_total_ms" "$batch_total_sec" "$avg_throughput"

  printf "summary: state avg=%sms p95=%sms p99=%sms min=%sms max=%sms\n" \
    "$s_avg" "$s_p95" "$s_p99" "$s_min" "$s_max"

  if [[ "$READY_CRITERIA" == "network" || "$READY_CRITERIA" == "both" ]]; then
    printf "summary: network avg=%sms p95=%sms p99=%sms min=%sms max=%sms\n" \
      "$n_avg" "$n_p95" "$n_p99" "$n_min" "$n_max"
  fi

  if [[ "$READY_CRITERIA" == "boottimer" ]]; then
    printf "summary: boottimer avg=%sms p95=%sms p99=%sms min=%sms max=%sms\n" \
      "$o_avg" "$o_p95" "$o_p99" "$o_min" "$o_max"
  fi

  printf "summary: paths output_dir=%s csv_path=%s summary_path=%s log_glob=%s\n" \
    "$OUT_DIR" "$OUT_DIR/startup-benchmark.csv" "$OUT_DIR/startup-summary.txt" "$OUT_DIR/*.stdout.log"
} | tee "$OUT_DIR/startup-summary.txt"

echo "[done] output directory: $OUT_DIR"
