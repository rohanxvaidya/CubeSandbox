#!/usr/bin/env bash
set -euo pipefail

# Firecracker lab deploy helper:
# - install required system packages
# - install firecracker/jailer binaries
# - download kernel/squashfs artifacts
# - build writable ext4 rootfs and ssh key
#
# Defaults are aligned with run_fc_jailer_startup_bench.sh:
#   KERNEL:  <lab>/vmlinux-6.18.36
#   ROOTFS:  <lab>/ubuntu-24.04.ext4
#   KEYFILE: <lab>/ubuntu-24.04.id_rsa
#   SQUASH:  <lab>/ubuntu-24.04.squashfs

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

LAB_DIR="/home/mz/firecracker-lab"
ARCH="$(uname -m)"
S3="https://s3.amazonaws.com/spec.ccfc.min"
RELEASE_URL="https://github.com/firecracker-microvm/firecracker/releases"

FIRECRACKER_VERSION="latest"
ROOTFS_SIZE_MIB=1024
FORCE_ROOTFS_REBUILD=0
SKIP_PACKAGES=0
SKIP_BINARIES=0
SKIP_ARTIFACTS=0
SKIP_ROOTFS_BUILD=0
CHECK_ONLY=0

KERNEL_LINK_NAME="vmlinux-6.18.36"
SQUASHFS_LINK_NAME="ubuntu-24.04.squashfs"
ROOTFS_NAME="ubuntu-24.04.ext4"
KEYFILE_NAME="ubuntu-24.04.id_rsa"

log() {
  printf '[deploy] %s\n' "$*"
}

die() {
  printf '[deploy][error] %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<USAGE
Usage:
  sudo ./firecracker_deploy.sh [options]

Options:
  --lab-dir <path>                Firecracker lab path (default: /home/mz/firecracker-lab)
  --firecracker-version <tag>     Release tag (e.g. v1.16.1) or latest (default: latest)
  --rootfs-size-mib <mib>         Target ext4 size in MiB (default: 1024)
  --force-rootfs-rebuild          Rebuild ext4+ssh key even if they already exist
  --skip-packages                 Skip package installation
  --skip-binaries                 Skip firecracker/jailer installation
  --skip-artifacts                Skip kernel/squashfs artifact download
  --skip-rootfs-build             Skip ext4 rootfs + ssh key build
  --check-only                    Only check environment and expected files
  -h, --help                      Show help

Examples:
  sudo ./firecracker_deploy.sh
  sudo ./firecracker_deploy.sh --firecracker-version v1.16.1
  sudo ./firecracker_deploy.sh --check-only
  sudo ./firecracker_deploy.sh --force-rootfs-rebuild --rootfs-size-mib 2048
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lab-dir)
      LAB_DIR="$2"; shift 2 ;;
    --firecracker-version)
      FIRECRACKER_VERSION="$2"; shift 2 ;;
    --rootfs-size-mib)
      ROOTFS_SIZE_MIB="$2"; shift 2 ;;
    --force-rootfs-rebuild)
      FORCE_ROOTFS_REBUILD=1; shift ;;
    --skip-packages)
      SKIP_PACKAGES=1; shift ;;
    --skip-binaries)
      SKIP_BINARIES=1; shift ;;
    --skip-artifacts)
      SKIP_ARTIFACTS=1; shift ;;
    --skip-rootfs-build)
      SKIP_ROOTFS_BUILD=1; shift ;;
    --check-only)
      CHECK_ONLY=1; shift ;;
    -h|--help)
      usage
      exit 0 ;;
    *)
      die "unknown argument: $1" ;;
  esac
done

KERNEL_PATH="${LAB_DIR}/${KERNEL_LINK_NAME}"
SQUASHFS_PATH="${LAB_DIR}/${SQUASHFS_LINK_NAME}"
ROOTFS_PATH="${LAB_DIR}/${ROOTFS_NAME}"
KEYFILE_PATH="${LAB_DIR}/${KEYFILE_NAME}"

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "please run as root (sudo)"
}

is_positive_integer() {
  local v="$1"
  [[ "$v" =~ ^[1-9][0-9]*$ ]]
}

check_binary() {
  local b="$1"
  command -v "$b" >/dev/null 2>&1 || die "missing binary: $b"
}

check_char_device() {
  local dev="$1"
  [[ -c "$dev" ]] || die "missing char device: $dev"
}

ensure_lab_dir() {
  mkdir -p "$LAB_DIR"
}

install_pkgs() {
  if [[ "$SKIP_PACKAGES" -eq 1 ]]; then
    log "skip package installation"
    return 0
  fi

  log "installing required system packages"
  if command -v dnf >/dev/null 2>&1; then
    dnf install -y curl wget tar jq iproute iptables openssh-clients squashfs-tools e2fsprogs coreutils util-linux
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl wget tar jq iproute iptables openssh-clients squashfs-tools e2fsprogs coreutils util-linux
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y curl wget tar jq iproute2 iptables openssh-client squashfs-tools e2fsprogs coreutils util-linux
  else
    die "unsupported package manager"
  fi
}

resolve_release_tag() {
  if [[ "$FIRECRACKER_VERSION" != "latest" ]]; then
    echo "$FIRECRACKER_VERSION"
    return 0
  fi

  basename "$(curl -fsSLI -o /dev/null -w '%{url_effective}' "${RELEASE_URL}/latest")"
}

install_firecracker_bins() {
  if [[ "$SKIP_BINARIES" -eq 1 ]]; then
    log "skip firecracker/jailer installation"
    return 0
  fi

  local tag tarball shafile rel_dir
  tag="$(resolve_release_tag)"
  tarball="firecracker-${tag}-${ARCH}.tgz"
  shafile="${tarball}.sha256.txt"
  rel_dir="release-${tag}-${ARCH}"

  log "installing firecracker binaries from ${tag}"
  pushd "$LAB_DIR" >/dev/null

  if [[ ! -f "$tarball" ]]; then
    curl -fL -o "$tarball" "${RELEASE_URL}/download/${tag}/${tarball}"
  fi
  if [[ ! -f "$shafile" ]]; then
    curl -fL -o "$shafile" "${RELEASE_URL}/download/${tag}/${shafile}"
  fi

  sha256sum -c "$shafile"
  tar -xzf "$tarball"

  cp -f "${rel_dir}/firecracker-${tag}-${ARCH}" /usr/local/bin/firecracker
  cp -f "${rel_dir}/jailer-${tag}-${ARCH}" /usr/local/bin/jailer
  chmod +x /usr/local/bin/firecracker /usr/local/bin/jailer

  popd >/dev/null

  firecracker --version || true
  jailer --version || true
}

fetch_artifacts() {
  if [[ "$SKIP_ARTIFACTS" -eq 1 ]]; then
    log "skip kernel/squashfs artifact download"
    return 0
  fi

  local ci_prefix kernel_key ubuntu_key kernel_file squash_file
  log "resolving latest CI artifacts from ${S3}"

  ci_prefix=$(curl -fsSL "${S3}?list-type=2&prefix=firecracker-ci/&delimiter=/" \
    | grep -oP "(?<=<Prefix>)firecracker-ci/[0-9]{8}-[^/]+/(?=</Prefix>)" \
    | sort \
    | tail -1)

  [[ -n "$ci_prefix" ]] || die "failed to discover firecracker CI prefix"

  kernel_key=$(curl -fsSL "${S3}?list-type=2&prefix=${ci_prefix}${ARCH}/vmlinux-" \
    | grep -oP "(?<=<Key>)(${ci_prefix}${ARCH}/vmlinux-[0-9]+\.[0-9]+\.[0-9]{1,3})(?=</Key>)" \
    | sort -V | tail -1)

  ubuntu_key=$(curl -fsSL "${S3}?list-type=2&prefix=${ci_prefix}${ARCH}/ubuntu-" \
    | grep -oP "(?<=<Key>)(${ci_prefix}${ARCH}/ubuntu-[0-9]+\.[0-9]+\.squashfs)(?=</Key>)" \
    | sort -V | tail -1)

  [[ -n "$kernel_key" ]] || die "failed to discover kernel artifact"
  [[ -n "$ubuntu_key" ]] || die "failed to discover ubuntu squashfs artifact"

  kernel_file="$(basename "$kernel_key")"
  squash_file="$(basename "$ubuntu_key")"

  pushd "$LAB_DIR" >/dev/null

  if [[ ! -f "$kernel_file" ]]; then
    log "downloading ${kernel_file}"
    wget -q -O "$kernel_file" "${S3}/${kernel_key}"
  else
    log "reuse existing ${kernel_file}"
  fi

  if [[ ! -f "$squash_file" ]]; then
    log "downloading ${squash_file}"
    wget -q -O "$squash_file" "${S3}/${ubuntu_key}"
  else
    log "reuse existing ${squash_file}"
  fi

  ln -sfn "$kernel_file" "$KERNEL_PATH"
  ln -sfn "$squash_file" "$SQUASHFS_PATH"

  popd >/dev/null
}

build_rootfs_and_key() {
  if [[ "$SKIP_ROOTFS_BUILD" -eq 1 ]]; then
    log "skip rootfs/key build"
    return 0
  fi

  if ! is_positive_integer "$ROOTFS_SIZE_MIB"; then
    die "--rootfs-size-mib must be >= 1"
  fi

  if [[ ! -f "$SQUASHFS_PATH" ]]; then
    die "squashfs missing: ${SQUASHFS_PATH}"
  fi

  if [[ "$FORCE_ROOTFS_REBUILD" -eq 0 && -f "$ROOTFS_PATH" && -f "$KEYFILE_PATH" ]]; then
    log "existing rootfs/key found, skip rebuild"
    return 0
  fi

  log "building rootfs ext4 (${ROOTFS_SIZE_MIB} MiB) and ssh key"
  pushd "$LAB_DIR" >/dev/null

  rm -rf squashfs-root id_rsa id_rsa.pub
  unsquashfs -f "$SQUASHFS_LINK_NAME" >/tmp/fc_unsquashfs.log 2>&1

  ssh-keygen -q -t rsa -b 2048 -f id_rsa -N ""
  mkdir -p squashfs-root/root/.ssh
  cp -f id_rsa.pub squashfs-root/root/.ssh/authorized_keys
  mv -f id_rsa "$KEYFILE_NAME"
  chmod 600 "$KEYFILE_NAME"

  chown -R root:root squashfs-root
  truncate -s "${ROOTFS_SIZE_MIB}M" "$ROOTFS_NAME"
  mkfs.ext4 -q -d squashfs-root -F "$ROOTFS_NAME"
  e2fsck -fn "$ROOTFS_NAME" >/tmp/fc_e2fsck.log 2>&1 || true

  popd >/dev/null
}

check_environment() {
  log "checking host prerequisites"
  check_char_device /dev/kvm
  check_binary curl
  check_binary jq
  check_binary unsquashfs
  check_binary mkfs.ext4
  check_binary ssh-keygen

  if [[ -f "$KERNEL_PATH" ]]; then
    log "ok kernel: $KERNEL_PATH"
  else
    die "missing kernel: $KERNEL_PATH"
  fi

  if [[ -f "$SQUASHFS_PATH" ]]; then
    log "ok squashfs: $SQUASHFS_PATH"
  else
    die "missing squashfs: $SQUASHFS_PATH"
  fi

  if [[ -f "$ROOTFS_PATH" ]]; then
    log "ok rootfs: $ROOTFS_PATH"
  else
    log "warn rootfs not found yet: $ROOTFS_PATH"
  fi

  if [[ -f "$KEYFILE_PATH" ]]; then
    log "ok keyfile: $KEYFILE_PATH"
  else
    log "warn keyfile not found yet: $KEYFILE_PATH"
  fi

  if command -v firecracker >/dev/null 2>&1; then
    log "ok binary: $(command -v firecracker)"
  else
    log "warn firecracker binary not found in PATH"
  fi

  if command -v jailer >/dev/null 2>&1; then
    log "ok binary: $(command -v jailer)"
  else
    log "warn jailer binary not found in PATH"
  fi
}

enable_script_exec() {
  chmod +x "$LAB_DIR"/*.sh >/dev/null 2>&1 || true
}

print_summary() {
  cat <<EOF

[deploy] done.
[deploy] LAB_DIR=${LAB_DIR}
[deploy] KERNEL=${KERNEL_PATH}
[deploy] ROOTFS=${ROOTFS_PATH}
[deploy] KEYFILE=${KEYFILE_PATH}
[deploy] SQUASHFS=${SQUASHFS_PATH}

[deploy] try benchmark:
  sudo ${LAB_DIR}/run_fc_jailer_startup_bench.sh --check-only
  sudo ${LAB_DIR}/run_fc_jailer_startup_bench.sh -n 10 -c 2 --ready-criteria both
  sudo ${LAB_DIR}/run_fc_jailer_startup_bench.sh --official-profile -n 20
EOF
}

main() {
  require_root
  ensure_lab_dir

  if [[ "$CHECK_ONLY" -eq 1 ]]; then
    check_environment
    log "check-only finished"
    exit 0
  fi

  install_pkgs
  install_firecracker_bins
  fetch_artifacts
  build_rootfs_and_key
  enable_script_exec
  check_environment
  print_summary
}

main "$@"
