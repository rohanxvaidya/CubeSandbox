#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

REPO_ROOT="${REPO_ROOT:-}"
BENCHMARK_MODE="${BENCHMARK_MODE:-single}"
CONCURRENCY="${CONCURRENCY:-1}"
TOTAL_REQUESTS="${TOTAL_REQUESTS:-4}"
OUTPUT_DIR="${OUTPUT_DIR:-}"

log() {
  printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

warn() {
  printf '\n[%s][WARN] %s\n' "$(date +%H:%M:%S)" "$*" >&2
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "This script must run as root." >&2
    exit 1
  fi
}

detect_repo_root() {
  local candidates=(
    "/home/mz/E2B/infra"
    "/home/mz/E2B"
    "/workspace/E2B"
    "/workspace/infra"
  )

  for d in "${candidates[@]}"; do
    if [[ -d "$d" && -f "$d/Makefile" && -d "$d/scripts/e2b-local" ]]; then
      echo "$d"
      return 0
    fi
  done

  echo "Could not detect E2B repo root. Please export REPO_ROOT=/path/to/repo" >&2
  return 1
}

check_support() {
  local ok=0

  log "== E2B benchmark readiness check =="
  printf 'user: %s\n' "$(id -un)"
  printf 'uid: %s\n' "$(id -u)"

  if [[ -e /dev/kvm ]]; then
    echo "KVM: OK (/dev/kvm present)"
  else
    echo "KVM: MISSING (/dev/kvm absent)"
    ok=1
  fi

  if [[ -e /dev/net/tun ]]; then
    echo "TUN: OK (/dev/net/tun present)"
  else
    echo "TUN: MISSING (/dev/net/tun absent)"
    ok=1
  fi

  if command -v docker >/dev/null 2>&1; then
    echo "Docker: OK ($(docker --version 2>/dev/null | head -n1))"
  else
    echo "Docker: MISSING"
    ok=1
  fi

  if command -v go >/dev/null 2>&1; then
    echo "Go: OK ($(go version 2>/dev/null))"
  else
    echo "Go: MISSING"
    ok=1
  fi

  if lsmod 2>/dev/null | grep -qi nbd; then
    echo "NBD module: OK"
  else
    echo "NBD module: NOT LOADED"
    ok=1
  fi

  local hp_total hp_free
  hp_total=$(awk '/HugePages_Total/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
  hp_free=$(awk '/HugePages_Free/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
  echo "HugePages_Total: ${hp_total}"
  echo "HugePages_Free: ${hp_free}"
  if [[ "$hp_total" -lt 256 ]]; then
    warn "Hugepages below 256; benchmark may fail or be unstable"
  fi

  local uf
  uf=$(cat /proc/sys/vm/unprivileged_userfaultfd 2>/dev/null || echo 0)
  echo "vm.unprivileged_userfaultfd: ${uf}"
  if [[ "$uf" -ne 1 ]]; then
    warn "userfaultfd is not enabled; E2B may fail during sandbox creation"
  fi

  if [[ "$ok" -ne 0 ]]; then
    echo "System is not ready for E2B benchmark yet." >&2
    return 1
  fi

  echo "System appears ready for E2B benchmark."
  return 0
}

install_packages() {
  log "== installing OS packages =="
  apt-get update
  apt-get install -y \
    build-essential \
    ca-certificates \
    curl \
    git \
    jq \
    docker.io \
    docker-compose-v2 \
    nbd-client \
    nbd-server \
    squashfs-tools \
    e2fsprogs \
    iproute2 \
    iptables \
    openssh-client \
    util-linux \
    coreutils \
    rsync \
    linux-modules-extra-$(uname -r) 2>/dev/null || true

  if ! docker compose version >/dev/null 2>&1; then
    warn "docker compose plugin not available; verify docker installation"
  fi
}

ensure_go() {
  if command -v go >/dev/null 2>&1; then
    local v
    v=$(go version 2>/dev/null | awk '{print $3}' | sed 's/^go//') || v="0"
    if [[ "${v%%.*}" -ge 1 ]]; then
      log "Go already installed: $(go version 2>/dev/null)"
      return 0
    fi
  fi

  log "Installing Go toolchain"
  local go_tar="/tmp/go1.25.7.linux-amd64.tar.gz"
  curl -fsSL -o "$go_tar" https://go.dev/dl/go1.25.7.linux-amd64.tar.gz
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "$go_tar"
  export PATH="/usr/local/go/bin:${PATH}"
  echo 'export PATH=/usr/local/go/bin:$PATH' > /etc/profile.d/go-path.sh
  chmod +x /etc/profile.d/go-path.sh
  log "Go installed: $(/usr/local/go/bin/go version)"
}

configure_kernel_and_runtime() {
  log "== configuring kernel and runtime =="

  modprobe nbd nbds_max=64 || true
  echo "nbd" > /etc/modules-load.d/e2b.conf
  echo "options nbd nbds_max=64" > /etc/modprobe.d/e2b-nbd.conf

  cat <<'EOF' > /etc/udev/rules.d/97-nbd-device.rules
ACTION=="add|change", KERNEL=="nbd*", OPTIONS:="nowatch"
EOF
  udevadm control --reload-rules >/dev/null 2>&1 || true
  udevadm trigger >/dev/null 2>&1 || true

  mkdir -p /mnt/hugepages
  mount -t hugetlbfs none /mnt/hugepages 2>/dev/null || true

  sysctl -w vm.nr_hugepages=2048 >/dev/null || true
  sysctl -w vm.unprivileged_userfaultfd=1 >/dev/null || true

  grep -qF 'hugetlbfs /mnt/hugepages' /etc/fstab || echo 'hugetlbfs /mnt/hugepages hugetlbfs defaults 0 0' >> /etc/fstab
  echo 'vm.nr_hugepages=2048' >> /etc/sysctl.d/99-e2b-local.conf 2>/dev/null || true
  echo 'vm.unprivileged_userfaultfd=1' >> /etc/sysctl.d/99-e2b-local.conf 2>/dev/null || true
  sysctl --system >/dev/null || true

  if [[ -e /dev/kvm ]]; then
    chmod 666 /dev/kvm || true
  fi
}

prepare_repo() {
  if [[ -n "$REPO_ROOT" ]]; then
    local root="$REPO_ROOT"
    if [[ -d "$root" ]]; then
      echo "$root"
      return 0
    fi
  fi

  REPO_ROOT="$(detect_repo_root)"
  echo "$REPO_ROOT"
}

prepare_firecracker_artifacts() {
  local root="$1"
  local fc_lab="/home/mz/firecracker-lab"
  local fc_bin="${fc_lab}/release-v1.16.1-x86_64/firecracker-v1.16.1-x86_64"
  local kernel_bin="${fc_lab}/vmlinux-6.18.36"

  if [[ ! -f "$fc_bin" ]]; then
    warn "Firecracker binary missing at $fc_bin; benchmark setup will fail until it exists"
  fi

  if [[ ! -f "$kernel_bin" ]]; then
    warn "Kernel binary missing at $kernel_bin; benchmark setup will fail until it exists"
  fi

  cd "$root"
  export GOTOOLCHAIN=auto
  if [[ -f "$root/scripts/e2b-local/setup_local_prereqs.sh" ]]; then
    log "Running repo-local setup script"
    bash "$root/scripts/e2b-local/setup_local_prereqs.sh"
  fi
}

run_benchmark() {
  local root="$1"
  cd "$root"
  export GOTOOLCHAIN=auto
  export PATH="/usr/local/go/bin:${PATH}"

  if [[ "$BENCHMARK_MODE" == "single" ]]; then
    log "Running single benchmark sample: concurrency=${CONCURRENCY}, total_requests=${TOTAL_REQUESTS}"
    bash "$root/packages/orchestrator/benchmarks/preflight_benchmark_env.sh" --apply || true
    bash "$root/packages/orchestrator/benchmarks/run_concurrency_bench.sh" -c "$CONCURRENCY" -n "$TOTAL_REQUESTS" -o "${OUTPUT_DIR:-/tmp/e2b-bench-$(date +%Y%m%d-%H%M%S)}"
    return 0
  fi

  if [[ "$BENCHMARK_MODE" == "matrix" ]]; then
    log "Running full local benchmark matrix"
    bash "$root/scripts/e2b-local/run_all_benchmarks.sh"
    return 0
  fi

  echo "Unknown BENCHMARK_MODE: $BENCHMARK_MODE" >&2
  exit 2
}

main() {
  require_root
  REPO_ROOT="$(prepare_repo)"
  log "repo root: $REPO_ROOT"

  if ! check_support; then
    log "Installing required packages and runtime configuration to make the host benchmark-ready"
    install_packages
    ensure_go
    configure_kernel_and_runtime
    log "Re-running readiness check"
    check_support || true
  fi

  prepare_firecracker_artifacts "$REPO_ROOT"
  run_benchmark "$REPO_ROOT"
}

main "$@"
