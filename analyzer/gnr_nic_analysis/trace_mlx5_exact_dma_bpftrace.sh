#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
NIC_NAME="${NIC_NAME:-ens7f0np0}"
DURATION="${DURATION:-20}"
OUT_DIR="${OUT_DIR:-${SCRIPT_DIR}/mlx5_exact_dma_$(date +%Y%m%d_%H%M%S)}"
TMP_WORK_DIR="${TMP_WORK_DIR:-${SCRIPT_DIR}/.tmp_bpftrace}"
BPFTRACE_PERF_RB_PAGES="${BPFTRACE_PERF_RB_PAGES:-1024}"

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Required command missing: $1" >&2
        exit 1
    }
}

require_cmd bpftrace
require_cmd timeout
require_cmd ip

mkdir -p "$OUT_DIR" "$TMP_WORK_DIR"

ip addr show "$NIC_NAME" > "${OUT_DIR}/nic_addr.txt"
ethtool -i "$NIC_NAME" > "${OUT_DIR}/nic_driver.txt" 2>/dev/null || true

BT_SCRIPT="${OUT_DIR}/mlx5_exact_dma.bt"
RAW_LOG="${OUT_DIR}/mlx5_exact_dma_raw.log"

cat > "$BT_SCRIPT" <<'EOF'
BEGIN
{
    printf("[mlx5_exact_dma] start\n");
}

/*
 * Queue ring/doorbell addresses.
 * These probes run when queues are opened (for example driver init/reopen).
 */
kprobe:mlx5e_open_rq
{
    @open_rq_ptr[tid] = (uint64)arg4;
}

kretprobe:mlx5e_open_rq
/@open_rq_ptr[tid] && retval == 0/
{
    $rq = (struct mlx5e_rq *)@open_rq_ptr[tid];
    $fr = $rq->wq_ctrl.buf.frags;
    @mlx5_pdev[(uint64)$rq->pdev] = 1;

    printf("RQ_OPEN pdev=0x%lx ix=%d rqn=%u wq_type=%u db_dma=0x%lx npages=%d frags=0x%lx",
           (uint64)$rq->pdev, $rq->ix, $rq->rqn, $rq->wq_type,
           $rq->wq_ctrl.db.dma, $rq->wq_ctrl.buf.npages, (uint64)$fr);

    if ($rq->wq_ctrl.buf.npages > 0) { printf(" map0=0x%lx", $fr[0].map); }
    if ($rq->wq_ctrl.buf.npages > 1) { printf(" map1=0x%lx", $fr[1].map); }
    if ($rq->wq_ctrl.buf.npages > 2) { printf(" map2=0x%lx", $fr[2].map); }
    if ($rq->wq_ctrl.buf.npages > 3) { printf(" map3=0x%lx", $fr[3].map); }
    printf("\n");

    delete(@open_rq_ptr[tid]);
}

kprobe:mlx5e_open_txqsq
{
    @open_sq_ptr[tid] = (uint64)arg5;
}

kretprobe:mlx5e_open_txqsq
/@open_sq_ptr[tid] && retval == 0/
{
    $sq = (struct mlx5e_txqsq *)@open_sq_ptr[tid];
    $fr = $sq->wq_ctrl.buf.frags;
    @mlx5_pdev[(uint64)$sq->pdev] = 1;

    printf("SQ_OPEN pdev=0x%lx ch_ix=%d txq_ix=%d sqn=%u db_dma=0x%lx npages=%d frags=0x%lx",
           (uint64)$sq->pdev, $sq->ch_ix, $sq->txq_ix, $sq->sqn,
           $sq->wq_ctrl.db.dma, $sq->wq_ctrl.buf.npages, (uint64)$fr);

    if ($sq->wq_ctrl.buf.npages > 0) { printf(" map0=0x%lx", $fr[0].map); }
    if ($sq->wq_ctrl.buf.npages > 1) { printf(" map1=0x%lx", $fr[1].map); }
    if ($sq->wq_ctrl.buf.npages > 2) { printf(" map2=0x%lx", $fr[2].map); }
    if ($sq->wq_ctrl.buf.npages > 3) { printf(" map3=0x%lx", $fr[3].map); }
    printf("\n");

    delete(@open_sq_ptr[tid]);
}

kprobe:mlx5e_open_cq
{
    @open_cq_ptr[tid] = (uint64)arg5;
}

kretprobe:mlx5e_open_cq
/@open_cq_ptr[tid] && retval == 0/
{
    $cq = (struct mlx5e_cq *)@open_cq_ptr[tid];
    $fr = $cq->wq_ctrl.buf.frags;

    printf("CQ_OPEN db_dma=0x%lx npages=%d frags=0x%lx",
           $cq->wq_ctrl.db.dma, $cq->wq_ctrl.buf.npages, (uint64)$fr);

    if ($cq->wq_ctrl.buf.npages > 0) { printf(" map0=0x%lx", $fr[0].map); }
    if ($cq->wq_ctrl.buf.npages > 1) { printf(" map1=0x%lx", $fr[1].map); }
    if ($cq->wq_ctrl.buf.npages > 2) { printf(" map2=0x%lx", $fr[2].map); }
    if ($cq->wq_ctrl.buf.npages > 3) { printf(" map3=0x%lx", $fr[3].map); }
    printf("\n");

    delete(@open_cq_ptr[tid]);
}

/*
 * Non-disruptive current queue snapshots from hot path.
 * These run during normal traffic, so queue reopen is not required.
 */
kprobe:mlx5e_post_rx_wqes
{
    $rq = (struct mlx5e_rq *)arg0;
    $fr = $rq->wq_ctrl.buf.frags;

    @mlx5_pdev[(uint64)$rq->pdev] = 1;

    if (!@seen_rq[$rq->rqn]) {
        @seen_rq[$rq->rqn] = 1;
        printf("RQ_CUR pdev=0x%lx ix=%d rqn=%u wq_type=%u db_dma=0x%lx npages=%d frags=0x%lx",
               (uint64)$rq->pdev, $rq->ix, $rq->rqn, $rq->wq_type,
               $rq->wq_ctrl.db.dma, $rq->wq_ctrl.buf.npages, (uint64)$fr);

        if ($rq->wq_ctrl.buf.npages > 0) { printf(" map0=0x%lx", $fr[0].map); }
        if ($rq->wq_ctrl.buf.npages > 1) { printf(" map1=0x%lx", $fr[1].map); }
        if ($rq->wq_ctrl.buf.npages > 2) { printf(" map2=0x%lx", $fr[2].map); }
        if ($rq->wq_ctrl.buf.npages > 3) { printf(" map3=0x%lx", $fr[3].map); }
        printf("\n");
    }
}

kprobe:mlx5e_sq_xmit_prepare.isra.0
{
    $sq = (struct mlx5e_txqsq *)arg0;
    $fr = $sq->wq_ctrl.buf.frags;

    @mlx5_pdev[(uint64)$sq->pdev] = 1;

    if (!@seen_sq[$sq->sqn]) {
        @seen_sq[$sq->sqn] = 1;
        printf("SQ_CUR pdev=0x%lx ch_ix=%d txq_ix=%d sqn=%u db_dma=0x%lx npages=%d frags=0x%lx",
               (uint64)$sq->pdev, $sq->ch_ix, $sq->txq_ix, $sq->sqn,
               $sq->wq_ctrl.db.dma, $sq->wq_ctrl.buf.npages, (uint64)$fr);

        if ($sq->wq_ctrl.buf.npages > 0) { printf(" map0=0x%lx", $fr[0].map); }
        if ($sq->wq_ctrl.buf.npages > 1) { printf(" map1=0x%lx", $fr[1].map); }
        if ($sq->wq_ctrl.buf.npages > 2) { printf(" map2=0x%lx", $fr[2].map); }
        if ($sq->wq_ctrl.buf.npages > 3) { printf(" map3=0x%lx", $fr[3].map); }
        printf("\n");
    }
}

/*
 * Raw data DMA addresses from DMA API return values.
 * Filter by pdev pointers learned from mlx5 queue open probes.
 */
kprobe:dma_map_page_attrs
/@mlx5_pdev[(uint64)arg0]/
{
    @dma_depth[tid] = @dma_depth[tid] + 1;
    $d = @dma_depth[tid];
    @dma_size[tid, $d] = arg3;
    @dma_dev[tid, $d] = (uint64)arg0;
}

kretprobe:dma_map_page_attrs
/@dma_depth[tid] > 0/
{
    $d = @dma_depth[tid];
    $sz = @dma_size[tid, $d];
    if ($sz > 0) {
        printf("RAW_DMA_MAP pdev=0x%lx size=%lu dma=0x%lx\n",
               @dma_dev[tid, $d], $sz, retval);
        @dma_size[tid, $d] = 0;
        @dma_dev[tid, $d] = 0;
    }

    @dma_depth[tid] = $d - 1;
    if (@dma_depth[tid] == 0) {
        delete(@dma_depth[tid]);
    }
}

END
{
    printf("[mlx5_exact_dma] end\n");
}
EOF

cat > "${OUT_DIR}/README.txt" <<EOF
Script: trace_mlx5_exact_dma_bpftrace.sh
NIC: ${NIC_NAME}
Duration: ${DURATION}s

Outputs:
- mlx5_exact_dma_raw.log
- mlx5_exact_dma_filtered.log
- mlx5_exact_dma.bt

Event meanings:
- RQ_OPEN/SQ_OPEN/CQ_OPEN: queue ring related addresses (doorbell DMA and first 4 ring page DMA mappings) during queue open.
- RQ_CUR/SQ_CUR: current active queue ring addresses from normal RX/TX hot paths.
- RAW_DMA_MAP: raw data DMA addresses from dma_map_page_attrs filtered by mlx5 pdev pointers.

Notes:
- Queue OPEN events only appear when queues open/reopen during capture.
- RQ_CUR/SQ_CUR do not require reopen and are printed once per queue observed in hot path.
EOF

echo "Running bpftrace for ${DURATION}s ..."

set +e
TMPDIR="$TMP_WORK_DIR" BPFTRACE_PERF_RB_PAGES="$BPFTRACE_PERF_RB_PAGES" timeout "$((DURATION + 5))" bpftrace -q "$BT_SCRIPT" > "$RAW_LOG"
BT_RC=$?
set -e

if [[ "$BT_RC" -ne 0 && "$BT_RC" -ne 124 ]]; then
    echo "bpftrace failed with rc=${BT_RC}" >&2
    exit "$BT_RC"
fi

grep -E 'RQ_OPEN|SQ_OPEN|CQ_OPEN|RQ_CUR|SQ_CUR|RAW_DMA_MAP' "$RAW_LOG" > "${OUT_DIR}/mlx5_exact_dma_filtered.log" || true

echo "Saved output in: ${OUT_DIR}"
echo "Main files:"
echo "  ${OUT_DIR}/mlx5_exact_dma_raw.log"
echo "  ${OUT_DIR}/mlx5_exact_dma_filtered.log"