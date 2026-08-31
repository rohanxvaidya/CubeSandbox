#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FC_LAB_DIR="${FC_LAB_DIR:-/home/mz/firecracker-lab}"

FC_VERSION_ALIAS="${FC_VERSION_ALIAS:-v1.14.1_431f1fc}"
FC_SOURCE_BIN="${FC_SOURCE_BIN:-${FC_LAB_DIR}/release-v1.16.1-x86_64/firecracker-v1.16.1-x86_64}"
KERNEL_VERSION="${KERNEL_VERSION:-vmlinux-6.18.36}"
KERNEL_SOURCE_BIN="${KERNEL_SOURCE_BIN:-${FC_LAB_DIR}/vmlinux-6.18.36}"

printf '[setup] root=%s\n' "$ROOT_DIR"
printf '[setup] firecracker source=%s\n' "$FC_SOURCE_BIN"
printf '[setup] kernel source=%s\n' "$KERNEL_SOURCE_BIN"

if [[ ! -f "$FC_SOURCE_BIN" ]]; then
  echo "[setup] missing firecracker source binary: $FC_SOURCE_BIN" >&2
  exit 1
fi
if [[ ! -f "$KERNEL_SOURCE_BIN" ]]; then
  echo "[setup] missing kernel source binary: $KERNEL_SOURCE_BIN" >&2
  exit 1
fi

mkdir -p "$ROOT_DIR/packages/fc-versions/builds/${FC_VERSION_ALIAS}/amd64"
mkdir -p "$ROOT_DIR/packages/fc-kernels/${KERNEL_VERSION}/amd64"
ln -sf "$FC_SOURCE_BIN" "$ROOT_DIR/packages/fc-versions/builds/${FC_VERSION_ALIAS}/amd64/firecracker"
cp -f "$KERNEL_SOURCE_BIN" "$ROOT_DIR/packages/fc-kernels/${KERNEL_VERSION}/amd64/vmlinux.bin"
chmod +x "$ROOT_DIR/packages/fc-versions/builds/${FC_VERSION_ALIAS}/amd64/firecracker"

sudo modprobe nbd nbds_max=64
sudo sysctl -w vm.nr_hugepages=2048 >/dev/null

sudo mkdir -p /fc-busybox/1.36.1/amd64
if [[ ! -f /fc-busybox/1.36.1/amd64/busybox ]]; then
  curl -fL https://storage.googleapis.com/e2b-artifact-binaries/busybox/1.36.1/amd64/busybox -o /tmp/busybox.e2b
  sudo cp /tmp/busybox.e2b /fc-busybox/1.36.1/amd64/busybox
  sudo chmod +x /fc-busybox/1.36.1/amd64/busybox
fi

(
  cd "$ROOT_DIR"
  export GOTOOLCHAIN=auto
  make -C packages/envd build
)

echo "[setup] done"
