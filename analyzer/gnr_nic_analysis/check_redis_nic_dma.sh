#!/usr/bin/env bash

set -u

NIC_NAME="${NIC_NAME:-ens7f0np0}"
TARGET_IP="${TARGET_IP:-10.10.10.100}"
REDIS_NAME="${REDIS_NAME:-redis-server}"

need_cmd() {
    command -v "$1" >/dev/null 2>&1
}

section() {
    printf '\n=== %s ===\n' "$1"
}

warn() {
    printf 'WARN: %s\n' "$1" >&2
}

show_file_value() {
    local path="$1"
    local label="$2"

    if [[ -r "$path" ]]; then
        printf '%s: ' "$label"
        cat "$path"
    else
        printf '%s: N/A\n' "$label"
    fi
}

get_pci_bdf() {
    local dev_path

    dev_path=$(readlink -f "/sys/class/net/${NIC_NAME}/device" 2>/dev/null) || return 1
    basename "$dev_path"
}

show_nic_basics() {
    section "NIC Device ${NIC_NAME}"

    if need_cmd ethtool; then
        ethtool -i "$NIC_NAME" 2>/dev/null || warn "ethtool -i failed for ${NIC_NAME}"
    else
        warn "ethtool is not installed"
    fi

    section "NIC IP Address ${NIC_NAME}"
    ip addr show "$NIC_NAME" 2>/dev/null || warn "ip addr show failed for ${NIC_NAME}"
}

show_redis_affinity() {
    local pids pid

    section "Redis Process Status"
    systemctl is-active redis redis-server 2>/dev/null || true

    pids=$(pgrep "$REDIS_NAME" 2>/dev/null || true)
    if [[ -z "$pids" ]]; then
        echo "No ${REDIS_NAME} process found"
        return
    fi

    pgrep -a "$REDIS_NAME" 2>/dev/null || true

    for pid in $pids; do
        echo "PID ${pid}"
        taskset -pc "$pid" 2>/dev/null || warn "taskset failed for PID ${pid}"
    done
}

show_irq_affinity() {
    local pci_bdf irq_list irq aff

    pci_bdf=$(get_pci_bdf) || {
        warn "Unable to determine PCI BDF for ${NIC_NAME}"
        return
    }

    section "NIC Interrupt Entries for ${NIC_NAME} (${pci_bdf})"
    grep "@pci:${pci_bdf}" /proc/interrupts || warn "No interrupt entries found for ${pci_bdf}"

    irq_list=$(awk -v bdf="@pci:${pci_bdf}" '$0 ~ bdf { gsub(":", "", $1); print $1 }' /proc/interrupts)
    if [[ -z "$irq_list" ]]; then
        return
    fi

    section "IRQ Affinity List for ${NIC_NAME} (${pci_bdf})"
    for irq in $irq_list; do
        if [[ -r "/proc/irq/${irq}/smp_affinity_list" ]]; then
            aff=$(<"/proc/irq/${irq}/smp_affinity_list")
            printf 'IRQ %s -> %s\n' "$irq" "$aff"
        else
            printf 'IRQ %s -> unavailable\n' "$irq"
        fi
    done
}

show_dma_info() {
    local pci_bdf sample_cq sample_eq

    pci_bdf=$(get_pci_bdf) || {
        warn "Unable to determine PCI BDF for ${NIC_NAME}"
        return
    }

    section "PCI Info for ${NIC_NAME} (${pci_bdf})"
    readlink -f "/sys/class/net/${NIC_NAME}/device" 2>/dev/null || true
    if need_cmd lspci; then
        lspci -s "$pci_bdf" -vv 2>/dev/null | egrep -i "Region|Memory at|NUMA|MSI-X|BusMaster" || true
    else
        warn "lspci is not installed"
    fi

    section "sysfs DMA Mask Bits"
    show_file_value "/sys/class/net/${NIC_NAME}/device/dma_mask_bits" "dma_mask_bits"
    show_file_value "/sys/class/net/${NIC_NAME}/device/consistent_dma_mask_bits" "consistent_dma_mask_bits"
    show_file_value "/sys/class/net/${NIC_NAME}/device/numa_node" "numa_node"

    section "/proc/iomem Entries for ${pci_bdf}"
    egrep "mlx5|${pci_bdf}" /proc/iomem || true

    section "dmesg mlx5/dma/iommu Hints"
    dmesg -T 2>/dev/null | egrep -i "mlx5|dma|iommu" | tail -n 120 || true

    section "mlx5 debugfs Root"
    ls -la /sys/kernel/debug/mlx5 2>/dev/null || warn "/sys/kernel/debug/mlx5 is unavailable"
    ls -la "/sys/kernel/debug/mlx5/${pci_bdf}" 2>/dev/null || true

    section "mlx5 Firmware Page Accounting"
    if compgen -G "/sys/kernel/debug/mlx5/${pci_bdf}/pages/*" >/dev/null; then
        for path in /sys/kernel/debug/mlx5/${pci_bdf}/pages/*; do
            printf '%s = ' "$(basename "$path")"
            cat "$path"
        done
    else
        warn "No mlx5 page accounting files found for ${pci_bdf}"
    fi

    sample_cq=$(find "/sys/kernel/debug/mlx5/${pci_bdf}/CQs" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n 1)
    section "Sample mlx5 CQ Debugfs Entry"
    if [[ -n "$sample_cq" ]]; then
        echo "Sample CQ dir: ${sample_cq}"
        ls "$sample_cq"
        for path in "$sample_cq"/*; do
            echo "--- ${path}"
            head -n 20 "$path" 2>/dev/null || true
        done
    else
        warn "No CQ debugfs entries found for ${pci_bdf}"
    fi

    sample_eq=$(find "/sys/kernel/debug/mlx5/${pci_bdf}/EQs" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n 1)
    section "Sample mlx5 EQ Debugfs Entry"
    if [[ -n "$sample_eq" ]]; then
        echo "Sample EQ dir: ${sample_eq}"
        ls "$sample_eq"
        for path in "$sample_eq"/*; do
            echo "--- ${path}"
            head -n 20 "$path" 2>/dev/null || true
        done
    else
        warn "No EQ debugfs entries found for ${pci_bdf}"
    fi

    section "IOMMU Debugfs Roots"
    ls /sys/kernel/debug/iommu 2>/dev/null || warn "/sys/kernel/debug/iommu is unavailable"
    find /sys/kernel/debug/iommu -maxdepth 3 -type f 2>/dev/null | head -n 80 || true

    section "IOMMU domain_translation_struct Matches"
    grep -n "${pci_bdf}" /sys/kernel/debug/iommu/intel/domain_translation_struct 2>/dev/null || true

    section "IOMMU dmar_translation_struct Matches"
    grep -n "${pci_bdf#0000:}" /sys/kernel/debug/iommu/intel/dmar_translation_struct 2>/dev/null || true
}

main() {
    show_nic_basics
    show_redis_affinity
    show_irq_affinity
    show_dma_info
}

main "$@"