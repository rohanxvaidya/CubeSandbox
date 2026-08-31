#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

LAB_DIR="/home/mz/firecracker-lab"
CHROOT_BASE="$LAB_DIR/jailer-chroot"
VM_BASE="$CHROOT_BASE/firecracker"
MODE="status"
DRY_RUN=0
VERBOSE=0

usage() {
  cat <<USAGE
Usage:
  sudo ./fc_sandbox_manager.sh [status|cleanup] [--dry-run] [--verbose]

Modes:
  status     Show current sandbox counts and details (default)
  cleanup    Remove remaining sandboxes created by this lab scripts

Options:
  --dry-run  Show what would be removed without changing system
  --verbose  Show sandbox detail rows instead of summary only
  -h, --help Show this help

Notes:
  - This script targets sandboxes under: $VM_BASE
  - It also cleans tap interfaces matching: tjNNNN
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    status|cleanup)
      MODE="$1"
      shift ;;
    --dry-run)
      DRY_RUN=1
      shift ;;
    --verbose)
      VERBOSE=1
      shift ;;
    -h|--help)
      usage
      exit 0 ;;
    *)
      echo "[error] unknown argument: $1"
      usage
      exit 1 ;;
  esac
done

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "[error] please run as root (sudo)"
    exit 1
  fi
}

run_cmd() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    eval "$*"
  fi
}

get_dir_ids() {
  if [[ -d "$VM_BASE" ]]; then
    find "$VM_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -u
  fi
}

get_running_jailer_ids() {
  ps -eo args | awk '
    /(^|[[:space:]])jailer([[:space:]]|$)/ {
      for (i = 1; i <= NF; i++) {
        if ($i == "--id" && i + 1 <= NF) {
          print $(i+1)
        }
      }
    }
  ' | sort -u
}

get_tap_for_id() {
  local id="$1"
  if [[ "$id" =~ ^jvm([0-9]{4})$ ]]; then
    echo "tj${BASH_REMATCH[1]}"
  fi
}

count_orphan_taps() {
  ip -o link show | awk -F': ' '{print $2}' | sed 's/@.*//' | grep -Ec '^tj[0-9]{4}$' || true
}

collect_all_ids() {
  {
    get_dir_ids
    get_running_jailer_ids
  } | awk 'NF > 0' | sort -u
}

jailer_pid_for_id() {
  local id="$1"
  local pid
  pid=$(ps -eo pid=,args= | awk -v target="$id" '
    /(^|[[:space:]])jailer([[:space:]]|$)/ {
      for (i = 1; i <= NF; i++) {
        if ($i == "--id" && i + 1 <= NF && $(i+1) == target) {
          print $1
        }
      }
    }
  ' | head -n1)
  echo "$pid"
}

send_shutdown_if_possible() {
  local id="$1"
  local socket="$VM_BASE/$id/root/api.socket"
  if [[ -S "$socket" ]]; then
    run_cmd "curl -sS -X PUT --unix-socket '$socket' -H 'Content-Type: application/json' --data '{\"action_type\":\"SendCtrlAltDel\"}' http://localhost/actions >/dev/null 2>&1 || true"
  fi
}

cleanup_ids_batch() {
  local ids="$1"
  local id pid vm_dir tap_dev
  local -a pids=()
  local -a dirs=()
  local -a taps=()

  while read -r id; do
    [[ -n "$id" ]] || continue
    vm_dir="$VM_BASE/$id"
    tap_dev="$(get_tap_for_id "$id" || true)"
    pid="$(jailer_pid_for_id "$id")"

    if [[ "$VERBOSE" -eq 1 ]]; then
      echo "[cleanup] id=$id pid=${pid:-} tap=${tap_dev:-} dir=$vm_dir"
    fi

    send_shutdown_if_possible "$id"

    if [[ -n "$pid" ]]; then
      pids+=("$pid")
    fi

    if [[ -n "$tap_dev" ]]; then
      taps+=("$tap_dev")
    fi

    if [[ -d "$vm_dir" ]]; then
      dirs+=("$vm_dir")
    fi
  done <<< "$ids"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    if [[ "${#pids[@]}" -gt 0 ]]; then
      echo "[dry-run] kill ${pids[*]}"
    fi
    if [[ "${#taps[@]}" -gt 0 ]]; then
      printf '[dry-run] ip link del %s\n' "${taps[@]}"
    fi
    if [[ "${#dirs[@]}" -gt 0 ]]; then
      printf '[dry-run] rm -rf %s\n' "${dirs[@]}"
    fi
    return 0
  fi

  if [[ "${#pids[@]}" -gt 0 ]]; then
    kill "${pids[@]}" >/dev/null 2>&1 || true

    for _ in $(seq 1 50); do
      local alive=0
      for pid in "${pids[@]}"; do
        if kill -0 "$pid" >/dev/null 2>&1; then
          alive=1
          break
        fi
      done
      [[ "$alive" -eq 0 ]] && break
      sleep 0.05
    done

    for pid in "${pids[@]}"; do
      kill -9 "$pid" >/dev/null 2>&1 || true
    done
  fi

  if [[ "${#taps[@]}" -gt 0 ]]; then
    for tap_dev in "${taps[@]}"; do
      ip link del "$tap_dev" >/dev/null 2>&1 || true
    done
  fi

  if [[ "${#dirs[@]}" -gt 0 ]]; then
    rm -rf -- "${dirs[@]}"
  fi
}

cleanup_orphan_taps() {
  local taps
  taps=$(ip -o link show | awk -F': ' '{print $2}' | sed 's/@.*//' | grep -E '^tj[0-9]{4}$' || true)
  if [[ -n "$taps" ]]; then
    echo "$taps" | while read -r tap; do
      [[ -n "$tap" ]] || continue
      run_cmd "ip link del '$tap' >/dev/null 2>&1 || true"
    done
  fi
}

print_status() {
  local all_ids running_count total_count leftover_count orphan_tap_count
  local id pid vm_dir tap_dev state

  all_ids="$(collect_all_ids || true)"
  running_count=0
  total_count=0

  if [[ "$VERBOSE" -eq 1 ]]; then
    echo "sandbox_id,jailer_pid,vm_dir,tap_dev,state"
  fi

  if [[ -n "$all_ids" ]]; then
    while read -r id; do
      [[ -n "$id" ]] || continue
      total_count=$((total_count + 1))
      pid="$(jailer_pid_for_id "$id")"
      vm_dir="$VM_BASE/$id"
      tap_dev="$(get_tap_for_id "$id" || true)"

      if [[ -n "$pid" ]]; then
        running_count=$((running_count + 1))
        state="running"
      elif [[ -d "$vm_dir" ]]; then
        state="leftover_dir"
      else
        state="unknown"
      fi

      if [[ "$VERBOSE" -eq 1 ]]; then
        echo "$id,${pid:-},${vm_dir},${tap_dev},$state"
      fi
    done <<< "$all_ids"
  fi

  leftover_count=$((total_count - running_count))
  orphan_tap_count=$(count_orphan_taps)

  if [[ "$VERBOSE" -eq 1 ]]; then
    echo ""
  fi
  echo "summary: sandbox_total=$total_count sandbox_running=$running_count sandbox_leftover=$leftover_count orphan_taps=$orphan_tap_count"
}

main() {
  require_root

  case "$MODE" in
    status)
      print_status
      ;;
    cleanup)
      local ids
      ids="$(collect_all_ids || true)"

      if [[ -z "$ids" ]]; then
        echo "[cleanup] no sandbox ids found under $VM_BASE"
      else
        echo "[cleanup] batching sandboxes_found=$(echo "$ids" | awk 'NF>0{c++} END{print c+0}')"
        cleanup_ids_batch "$ids"
      fi

      cleanup_orphan_taps

      echo "[cleanup] done"
      echo "[cleanup] current status:"
      print_status
      ;;
  esac
}

main "$@"
