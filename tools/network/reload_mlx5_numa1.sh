#!/usr/bin/env bash
set -euo pipefail

KERNEL_ROOT="/home/mz/kernel/net6p8"
MLX5_MOD_DIR="drivers/net/ethernet/mellanox/mlx5/core"
MLX5_KO="$KERNEL_ROOT/drivers/net/ethernet/mellanox/mlx5/core/mlx5_core.ko"
BUILD_LOG="/home/mz/mlx5_build_reload.log"
DO_BUILD=1
DO_RELOAD=1

usage() {
    cat <<'EOF'
Usage: reload_mlx5_numa1.sh [--build-only] [--reload-only] [--no-build]

Options:
  --build-only   Build mlx5_core module only, do not reload.
  --reload-only  Reload module only, do not build.
  --no-build     Alias of --reload-only.
  -h, --help     Show this help message.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build-only)
            DO_BUILD=1
            DO_RELOAD=0
            ;;
        --reload-only|--no-build)
            DO_BUILD=0
            DO_RELOAD=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
    shift
done

build_module() {
    local jobs

    if ! command -v make >/dev/null 2>&1; then
        echo "ERROR: make is not installed" >&2
        exit 1
    fi

    jobs=$(nproc)
    mkdir -p /home/mz/.tmp

    echo "[1/5] Building mlx5_core module..."
    echo "      log: $BUILD_LOG"
    TMPDIR=/home/mz/.tmp make -C "$KERNEL_ROOT" M="$MLX5_MOD_DIR" modules -j"$jobs" \
        2>&1 | tee "$BUILD_LOG"
}

reload_module() {
    echo "[2/5] Unloading mlx5_core (if loaded)..."
    numactl --cpunodebind=1 --membind=1 modprobe -r mlx5_core || true

    sleep 1s

    echo "[3/5] Loading dependencies..."
    modprobe pci_hyperv_intf
    modprobe mlxfw
#if [ "$Q_LIST" != "" ]; then
 #load_para=
#fi 
    echo "[4/5] Loading rebuilt mlx5_core with NUMA node1 affinity..."
   # numactl --cpunodebind=1 --membind=1 insmod "$MLX5_KO"
    #numactl --cpunodebind=1 --membind=1 insmod "$MLX5_KO" numa_node=1
    #numactl --cpunodebind=1 --membind=1 insmod "$MLX5_KO" queue_numa='0-57:0,58-62:1'  #queue_numa='0-9:0,10-62:1'
Q_LIST=${Q_LIST:-""}
if [[ "${Q_LIST}" == "" ]]; then
    #numactl --cpunodebind=1 --membind=1 insmod "$MLX5_KO" "queue_numa=${Q_LIST}"  #queue_numa='0-9:0,10-62:1'
    numactl --cpunodebind=1 --membind=1 insmod "$MLX5_KO"
else

    numactl --cpunodebind=1 --membind=1 insmod "$MLX5_KO" "queue_numa=${Q_LIST}"  #queue_numa='0-9:0,10-62:1'
    #numactl --cpunodebind=1 --membind=1 insmod "$MLX5_KO"
fi
### 方式1: 所有 queue 统一到 NUMA 1（向后兼容）
#modprobe mlx5_core numa_node=1
#
## 方式2: per-queue 分配
#modprobe mlx5_core queue_numa='0-9:0,10-62:1'
#
## 方式3: 混合 - 共享基础设施(EQ/UAR)在 NUMA 1，部分 queue 在 NUMA 0
#modprobe mlx5_core numa_node=1 queue_numa='0-9:0,10-62:1'

    echo "[5/5] Verifying loaded modules..."
    lsmod | rg '^mlx5_core|^mlxfw|^pci_hyperv_intf' || true

    echo
    echo "Recent mlx5 kernel log lines:"
    dmesg | tail -30 | rg -n "mlx5_core|Unknown symbol|alloc_numa|requested_numa|sw_numa_node" || true
}

if [[ ! -f "$MLX5_KO" ]]; then
    echo "ERROR: module not found: $MLX5_KO" >&2
    exit 1
fi

if ! command -v numactl >/dev/null 2>&1; then
    echo "ERROR: numactl is not installed" >&2
    exit 1
fi

if [[ "$DO_BUILD" -eq 1 ]]; then
    build_module
fi

if [[ "$DO_RELOAD" -eq 1 ]]; then
    reload_module
fi

echo
if [[ "$DO_BUILD" -eq 1 && "$DO_RELOAD" -eq 1 ]]; then
    echo "Build + reload completed."
elif [[ "$DO_BUILD" -eq 1 ]]; then
    echo "Build completed."
else
    echo "Reload completed."
fi
