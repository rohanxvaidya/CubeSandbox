#!/usr/bin/env bash
set -euo pipefail

# Preflight for E2B concurrent benchmark runs.
# Usage:
#   ./preflight_benchmark_env.sh            # apply cleanup + checks
#   ./preflight_benchmark_env.sh --check-only
#   ./preflight_benchmark_env.sh --apply

MODE="apply"
if [[ "${1:-}" == "--check-only" ]]; then
  MODE="check"
elif [[ "${1:-}" == "--apply" || -z "${1:-}" ]]; then
  MODE="apply"
else
  echo "Unknown argument: ${1:-}" >&2
  echo "Usage: $0 [--check-only|--apply]" >&2
  exit 2
fi

log() {
  printf '[preflight] %s\n' "$*"
}

warn() {
  printf '[preflight][warn] %s\n' "$*" >&2
}

require_cmd() {
  local c="$1"
  if ! command -v "$c" >/dev/null 2>&1; then
    warn "missing command: $c"
    return 1
  fi
  return 0
}

count_matching_procs() {
  local pattern="$1"
  (pgrep -fa "$pattern" 2>/dev/null || true) | wc -l
}

count_netns() {
  ip netns list 2>/dev/null | wc -l
}

count_z_ifaces() {
  ip -o link show 2>/dev/null | awk -F': ' '/: z192\.168\.0\./{c++} END{print c+0}'
}

count_nbd_used() {
  local used=0
  local f
  for f in /sys/block/nbd*/pid; do
    [[ -f "$f" ]] || continue
    if [[ -n "$(cat "$f" 2>/dev/null || true)" ]]; then
      used=$((used+1))
    fi
  done
  echo "$used"
}

print_status() {
  local go_bench
  local bench_test
  local firecracker
  local ns_count
  local z_count
  local nbd_used
  local hp_total
  local hp_free
  local kvm="missing"
  local tun="missing"

  go_bench="$(count_matching_procs 'go test -run=\^\$ -bench=BenchmarkConcurrentResume/concurrency-')"
  bench_test="$(count_matching_procs '/tmp/go-build.*/benchmarks.test')"
  firecracker="$(count_matching_procs '/fc-versions/builds/.*/firecracker')"
  ns_count="$(count_netns)"
  z_count="$(count_z_ifaces)"
  nbd_used="$(count_nbd_used)"

  hp_total="$(awk '/HugePages_Total/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
  hp_free="$(awk '/HugePages_Free/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"

  [[ -e /dev/kvm ]] && kvm="present"
  [[ -e /dev/net/tun ]] && tun="present"

  log "status: mode=${MODE}"
  log "status: go_bench_procs=${go_bench}, benchmarks_test_procs=${bench_test}, firecracker_procs=${firecracker}"
  log "status: netns=${ns_count}, z_ifaces=${z_count}, nbd_used=${nbd_used}"
  log "status: hugepages_total=${hp_total}, hugepages_free=${hp_free}"
  log "status: /dev/kvm=${kvm}, /dev/net/tun=${tun}"

  if command -v ss >/dev/null 2>&1; then
    local p5016
    p5016="$(ss -ltn 2>/dev/null | awk '$4 ~ /:5016$/ {c++} END{print c+0}')"
    log "status: tcp_port_5016_listeners=${p5016}"
  fi
}

kill_stale_processes() {
  pkill -9 -f 'go test -run=\^\$ -bench=BenchmarkConcurrentResume/concurrency-|benchmarks.test' >/dev/null 2>&1 || true
  pkill -9 -f '/fc-versions/builds/.*/firecracker' >/dev/null 2>&1 || true
}

cleanup_netns_and_ifaces() {
  local ns
  for ns in $(ip netns list 2>/dev/null | awk '{print $1}'); do
    ip netns delete "$ns" >/dev/null 2>&1 || true
  done

  local dev
  for dev in $(ip -o link show 2>/dev/null | awk -F': ' '/: z192\.168\.0\./{print $2}'); do
    ip link delete "$dev" >/dev/null 2>&1 || true
  done
}

cleanup_nbd() {
  local has_nbd_client=0
  local has_qemu_nbd=0
  command -v nbd-client >/dev/null 2>&1 && has_nbd_client=1
  command -v qemu-nbd >/dev/null 2>&1 && has_qemu_nbd=1

  if [[ "$has_nbd_client" -eq 0 && "$has_qemu_nbd" -eq 0 ]]; then
    warn "neither nbd-client nor qemu-nbd found; cannot detach stale nbd mappings"
    return 0
  fi

  local dev
  for dev in /dev/nbd*; do
    [[ -b "$dev" ]] || continue
    if [[ "$has_nbd_client" -eq 1 ]]; then
      nbd-client -d "$dev" >/dev/null 2>&1 || true
    fi
    if [[ "$has_qemu_nbd" -eq 1 ]]; then
      qemu-nbd -d "$dev" >/dev/null 2>&1 || true
    fi
  done

  local remaining
  remaining="$(count_nbd_used)"
  if [[ "$remaining" -gt 0 ]]; then
    warn "nbd cleanup incomplete: remaining_used_nbd=${remaining}"
    return 1
  fi

  return 0
}

main() {
  local missing=0

  require_cmd pgrep || missing=1
  require_cmd pkill || missing=1
  require_cmd ip || missing=1
  require_cmd awk || missing=1

  if [[ "$missing" -ne 0 ]]; then
    warn "missing required tools"
    exit 1
  fi

  print_status

  if [[ "$MODE" == "check" ]]; then
    log "check-only mode: no cleanup actions applied"
    exit 0
  fi

  if [[ "$(id -u)" != "0" ]]; then
    warn "apply mode needs root privileges"
    exit 1
  fi

  log "apply: killing stale benchmark and firecracker processes"
  kill_stale_processes

  log "apply: cleaning netns and z192.168.0.* interfaces"
  cleanup_netns_and_ifaces

  log "apply: detaching stale nbd mappings"
  cleanup_nbd || {
    warn "stale nbd mappings still present after cleanup"
    exit 1
  }

  log "post-clean status"
  print_status

  log "preflight completed"
}

main "$@"
