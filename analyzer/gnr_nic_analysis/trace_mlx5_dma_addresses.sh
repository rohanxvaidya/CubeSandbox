#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OFFSET_SCRIPT="${SCRIPT_DIR}/extract_mlx5_btf_offsets.sh"

NIC_NAME="${NIC_NAME:-ens7f0np0}"
DURATION="${DURATION:-30}"
OUT_DIR="${OUT_DIR:-${SCRIPT_DIR}/mlx5_dma_trace_$(date +%Y%m%d_%H%M%S)}"
TRACE_NAME="mlx5_dma_live"

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Required command missing: $1" >&2
        exit 1
    }
}

cleanup() {
    set +e
    trace-cmd reset >/dev/null 2>&1 || true
    : > /sys/kernel/tracing/kprobe_events 2>/dev/null || true
}

trap cleanup EXIT

require_cmd bpftool
require_cmd trace-cmd
require_cmd ip

[[ -x "$OFFSET_SCRIPT" ]] || {
    echo "Offset helper missing or not executable: $OFFSET_SCRIPT" >&2
    exit 1
}

mkdir -p "$OUT_DIR"

eval "$($OFFSET_SCRIPT)"

RQ_DB_DMA_OFF=$((MLX5_RQ_OFF_WQ_CTRL + MLX5_WQ_CTRL_OFF_DB + MLX5_DB_OFF_DMA))
RQ_FRAGS_PTR_OFF=$((MLX5_RQ_OFF_WQ_CTRL + MLX5_WQ_CTRL_OFF_BUF + MLX5_FRAG_BUF_OFF_FRAGS))
RQ_NPAGES_OFF=$((MLX5_RQ_OFF_WQ_CTRL + MLX5_WQ_CTRL_OFF_BUF + MLX5_FRAG_BUF_OFF_NPAGES))

SQ_DB_DMA_OFF=$((MLX5_SQ_OFF_WQ_CTRL + MLX5_WQ_CTRL_OFF_DB + MLX5_DB_OFF_DMA))
SQ_FRAGS_PTR_OFF=$((MLX5_SQ_OFF_WQ_CTRL + MLX5_WQ_CTRL_OFF_BUF + MLX5_FRAG_BUF_OFF_FRAGS))
SQ_NPAGES_OFF=$((MLX5_SQ_OFF_WQ_CTRL + MLX5_WQ_CTRL_OFF_BUF + MLX5_FRAG_BUF_OFF_NPAGES))

CQ_DB_DMA_OFF=$((MLX5_CQ_OFF_WQ_CTRL + MLX5_WQ_CTRL_OFF_DB + MLX5_DB_OFF_DMA))
CQ_FRAGS_PTR_OFF=$((MLX5_CQ_OFF_WQ_CTRL + MLX5_WQ_CTRL_OFF_BUF + MLX5_FRAG_BUF_OFF_FRAGS))
CQ_NPAGES_OFF=$((MLX5_CQ_OFF_WQ_CTRL + MLX5_WQ_CTRL_OFF_BUF + MLX5_FRAG_BUF_OFF_NPAGES))

cat > "${OUT_DIR}/README.txt" <<EOF
NIC: ${NIC_NAME}
Duration: ${DURATION}s

What this script records:
1. Queue creation probes for mlx5 RQ/SQ/CQ objects, including doorbell DMA and queue buffer metadata.
2. IOMMU map events, which expose actual DMA IOVA and physical address mappings.
3. Page-pool state events, which help correlate mlx5 RX page reuse activity.

Important limits on this host:
- No clang/bpftrace are installed, so there is no stateful CO-RE tracer here.
- Queue creation probes only fire when queues are created or reopened during the trace window.
- iommu:map records actual DMA mappings, but not a queue index by itself.
EOF

ip addr show "$NIC_NAME" > "${OUT_DIR}/nic_addr.txt"
ethtool -i "$NIC_NAME" > "${OUT_DIR}/nic_driver.txt" 2>/dev/null || true

cat > "${OUT_DIR}/offsets.env" <<EOF
MLX5_RQ_OFF_WQ_CTRL=${MLX5_RQ_OFF_WQ_CTRL}
MLX5_RQ_OFF_IX=${MLX5_RQ_OFF_IX}
MLX5_RQ_OFF_WQ_TYPE=${MLX5_RQ_OFF_WQ_TYPE}
MLX5_RQ_OFF_RQN=${MLX5_RQ_OFF_RQN}
MLX5_SQ_OFF_WQ_CTRL=${MLX5_SQ_OFF_WQ_CTRL}
MLX5_SQ_OFF_CH_IX=${MLX5_SQ_OFF_CH_IX}
MLX5_SQ_OFF_TXQ_IX=${MLX5_SQ_OFF_TXQ_IX}
MLX5_SQ_OFF_SQN=${MLX5_SQ_OFF_SQN}
MLX5_CQ_OFF_WQ_CTRL=${MLX5_CQ_OFF_WQ_CTRL}
MLX5_WQ_CTRL_OFF_BUF=${MLX5_WQ_CTRL_OFF_BUF}
MLX5_WQ_CTRL_OFF_DB=${MLX5_WQ_CTRL_OFF_DB}
MLX5_DB_OFF_DMA=${MLX5_DB_OFF_DMA}
MLX5_FRAG_BUF_OFF_FRAGS=${MLX5_FRAG_BUF_OFF_FRAGS}
MLX5_FRAG_BUF_OFF_NPAGES=${MLX5_FRAG_BUF_OFF_NPAGES}
MLX5_BUF_LIST_SIZE=${MLX5_BUF_LIST_SIZE}
MLX5_BUF_LIST_OFF_MAP=${MLX5_BUF_LIST_OFF_MAP}
RQ_DB_DMA_OFF=${RQ_DB_DMA_OFF}
RQ_FRAGS_PTR_OFF=${RQ_FRAGS_PTR_OFF}
RQ_NPAGES_OFF=${RQ_NPAGES_OFF}
SQ_DB_DMA_OFF=${SQ_DB_DMA_OFF}
SQ_FRAGS_PTR_OFF=${SQ_FRAGS_PTR_OFF}
SQ_NPAGES_OFF=${SQ_NPAGES_OFF}
CQ_DB_DMA_OFF=${CQ_DB_DMA_OFF}
CQ_FRAGS_PTR_OFF=${CQ_FRAGS_PTR_OFF}
CQ_NPAGES_OFF=${CQ_NPAGES_OFF}
EOF

cleanup

printf 'p:mlx5q_rq mlx5e_create_rq rq=%%di ix=+%d(%%di):u32 rqn=+%d(%%di):u32 wq_type=+%d(%%di):u8 db_dma=+%d(%%di):x64 frags=+%d(%%di):x64 npages=+%d(%%di):u32\n' \
    "$MLX5_RQ_OFF_IX" "$MLX5_RQ_OFF_RQN" "$MLX5_RQ_OFF_WQ_TYPE" "$RQ_DB_DMA_OFF" "$RQ_FRAGS_PTR_OFF" "$RQ_NPAGES_OFF" \
    >> /sys/kernel/tracing/kprobe_events

printf 'p:mlx5q_sq mlx5e_open_txqsq ch_ix=+%d(%%r9):u32 txq_ix=+%d(%%r9):u32 sqn=+%d(%%r9):u32 db_dma=+%d(%%r9):x64 frags=+%d(%%r9):x64 npages=+%d(%%r9):u32\n' \
    "$MLX5_SQ_OFF_CH_IX" "$MLX5_SQ_OFF_TXQ_IX" "$MLX5_SQ_OFF_SQN" "$SQ_DB_DMA_OFF" "$SQ_FRAGS_PTR_OFF" "$SQ_NPAGES_OFF" \
    >> /sys/kernel/tracing/kprobe_events

printf 'p:mlx5q_cq mlx5e_open_cq db_dma=+%d(%%r8):x64 frags=+%d(%%r8):x64 npages=+%d(%%r8):u32\n' \
    "$CQ_DB_DMA_OFF" "$CQ_FRAGS_PTR_OFF" "$CQ_NPAGES_OFF" \
    >> /sys/kernel/tracing/kprobe_events

grep -q '^p:kprobes/mlx5q_rq ' /sys/kernel/tracing/kprobe_events || {
    echo "Failed to register mlx5q_rq kprobe" >&2
    exit 1
}

grep -q '^p:kprobes/mlx5q_sq ' /sys/kernel/tracing/kprobe_events || {
    echo "Failed to register mlx5q_sq kprobe" >&2
    exit 1
}

grep -q '^p:kprobes/mlx5q_cq ' /sys/kernel/tracing/kprobe_events || {
    echo "Failed to register mlx5q_cq kprobe" >&2
    exit 1
}

trace-cmd record \
    -o "${OUT_DIR}/${TRACE_NAME}.dat" \
    -e kprobes:mlx5q_rq \
    -e kprobes:mlx5q_sq \
    -e kprobes:mlx5q_cq \
    -e iommu:map \
    -e page_pool:page_pool_state_hold \
    -e page_pool:page_pool_state_release \
    -e page_pool:page_pool_release \
    sleep "$DURATION"

[[ -s "${OUT_DIR}/${TRACE_NAME}.dat" ]] || {
    echo "trace-cmd record did not produce ${OUT_DIR}/${TRACE_NAME}.dat" >&2
    exit 1
}

trace-cmd report "${OUT_DIR}/${TRACE_NAME}.dat" > "${OUT_DIR}/${TRACE_NAME}.txt"

grep -E 'mlx5q_(rq|sq|cq)|iommu_map|page_pool_' "${OUT_DIR}/${TRACE_NAME}.txt" > "${OUT_DIR}/${TRACE_NAME}.filtered.txt" || true

echo "Saved trace output under: ${OUT_DIR}"
echo "Main files:"
echo "  ${OUT_DIR}/${TRACE_NAME}.txt"
echo "  ${OUT_DIR}/${TRACE_NAME}.filtered.txt"
echo "  ${OUT_DIR}/offsets.env"