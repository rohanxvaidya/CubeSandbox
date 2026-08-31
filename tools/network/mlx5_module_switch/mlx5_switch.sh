#!/usr/bin/env bash
set -euo pipefail

KVER="${KVER:-$(uname -r)}"
MODLIB="/lib/modules/${KVER}"
STOCK_KO="${MODLIB}/kernel/drivers/net/ethernet/mellanox/mlx5/core/mlx5_core.ko"
CUSTOM_KO="${CUSTOM_KO:-/home/mz/kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/mlx5_core.ko}"
OVERRIDE_DIR="${MODLIB}/updates/mlx5-switch"
OVERRIDE_KO="${OVERRIDE_DIR}/mlx5_core.ko"
BACKUP_DIR="/var/lib/mlx5-switch/${KVER}"
BACKUP_KO="${BACKUP_DIR}/mlx5_core.stock.ko"
NODE="${NUMA_NODE:-1}"

need_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "ERROR: run as root" >&2
        exit 1
    fi
}

run_with_numa() {
    if command -v numactl >/dev/null 2>&1; then
        numactl --cpunodebind="${NODE}" --membind="${NODE}" "$@"
    else
        "$@"
    fi
}

reload_mlx5() {
    run_with_numa modprobe -r mlx5_core || true
    modprobe pci_hyperv_intf
    modprobe mlxfw
    run_with_numa modprobe mlx5_core
}

enable_custom() {
    [[ -f "${CUSTOM_KO}" ]] || {
        echo "ERROR: custom module not found: ${CUSTOM_KO}" >&2
        exit 1
    }
    [[ -f "${STOCK_KO}" ]] || {
        echo "ERROR: stock module not found: ${STOCK_KO}" >&2
        exit 1
    }

    mkdir -p "${BACKUP_DIR}" "${OVERRIDE_DIR}"

    if [[ ! -f "${BACKUP_KO}" ]]; then
        cp -a "${STOCK_KO}" "${BACKUP_KO}"
    fi

    cp -a "${CUSTOM_KO}" "${OVERRIDE_KO}"
    depmod -a "${KVER}"
    reload_mlx5
}

disable_custom() {
    rm -f "${OVERRIDE_KO}"
    depmod -a "${KVER}"
    reload_mlx5
}

show_status() {
    echo "kernel: ${KVER}"
    echo "stock : ${STOCK_KO}"
    echo "custom: ${CUSTOM_KO}"
    echo "override present: $( [[ -f "${OVERRIDE_KO}" ]] && echo yes || echo no )"
    echo "backup present  : $( [[ -f "${BACKUP_KO}" ]] && echo yes || echo no )"
    echo
    echo "modprobe plan:"
    modprobe -n -v mlx5_core || true
    echo
    echo "loaded modules:"
    lsmod | grep '^mlx5_core\|^mlxfw\|^pci_hyperv_intf' || true
}

usage() {
    cat <<'EOF'
Usage: mlx5_switch.sh <command>

Commands:
  enable   Install custom mlx5_core into updates path and reload it.
  disable  Remove custom override and reload stock module.
  reload   Reload mlx5_core using current modprobe resolution.
  status   Show switch status and modprobe resolution.

Environment overrides:
  KVER=<kernel-version>
  CUSTOM_KO=<path-to-custom-mlx5_core.ko>
  NUMA_NODE=<node-id>      (default: 1)
EOF
}

main() {
    local cmd="${1:-}"

    case "${cmd}" in
        enable)
            need_root
            enable_custom
            ;;
        disable)
            need_root
            disable_custom
            ;;
        reload)
            need_root
            reload_mlx5
            ;;
        status)
            show_status
            ;;
        -h|--help|help|"")
            usage
            ;;
        *)
            echo "ERROR: unknown command: ${cmd}" >&2
            usage
            exit 2
            ;;
    esac
}

main "$@"
