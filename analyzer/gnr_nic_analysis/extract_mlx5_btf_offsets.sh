#!/usr/bin/env bash

set -euo pipefail

BTF_FILE="${BTF_FILE:-/sys/kernel/btf/mlx5_core}"

if [[ ! -r "$BTF_FILE" ]]; then
    echo "BTF file not readable: $BTF_FILE" >&2
    exit 1
fi

RAW_BTF_FILE="$(mktemp)"
trap 'rm -f "$RAW_BTF_FILE"' EXIT

bpftool btf dump file "$BTF_FILE" format raw > "$RAW_BTF_FILE"

struct_size() {
    local struct_name="$1"

    awk -v s="$struct_name" '
        $0 ~ "STRUCT '\''" s "'\'' size=" {
            match($0, /size=([0-9]+)/, a)
            if (a[1] != "") {
                print a[1]
                exit
            }
        }
    ' "$RAW_BTF_FILE"
}

member_offset() {
    local struct_name="$1"
    local member_name="$2"

    awk -v s="$struct_name" -v m="$member_name" '
        $0 ~ "STRUCT '\''" s "'\'' size=" { in_struct=1; next }
        in_struct && $1 ~ /^\[/ { exit }
        in_struct && $0 ~ "'\''" m "'\''" {
            match($0, /bits_offset=([0-9]+)/, a)
            if (a[1] != "") {
                print a[1] / 8
                exit
            }
        }
    ' "$RAW_BTF_FILE"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Required command missing: $1" >&2
        exit 1
    }
}

require_cmd bpftool

RQ_OFF_WQ_CTRL=$(member_offset mlx5e_rq wq_ctrl)
RQ_OFF_IX=$(member_offset mlx5e_rq ix)
RQ_OFF_WQ_TYPE=$(member_offset mlx5e_rq wq_type)
RQ_OFF_RQN=$(member_offset mlx5e_rq rqn)
RQ_OFF_PDEV=$(member_offset mlx5e_rq pdev)

SQ_OFF_WQ_CTRL=$(member_offset mlx5e_txqsq wq_ctrl)
SQ_OFF_CH_IX=$(member_offset mlx5e_txqsq ch_ix)
SQ_OFF_TXQ_IX=$(member_offset mlx5e_txqsq txq_ix)
SQ_OFF_SQN=$(member_offset mlx5e_txqsq sqn)
SQ_OFF_PDEV=$(member_offset mlx5e_txqsq pdev)

CQ_OFF_WQ_CTRL=$(member_offset mlx5e_cq wq_ctrl)

WQ_CTRL_OFF_BUF=$(member_offset mlx5_wq_ctrl buf)
WQ_CTRL_OFF_DB=$(member_offset mlx5_wq_ctrl db)

DB_OFF_DMA=$(member_offset mlx5_db dma)

FRAG_BUF_OFF_FRAGS=$(member_offset mlx5_frag_buf frags)
FRAG_BUF_OFF_NPAGES=$(member_offset mlx5_frag_buf npages)

BUF_LIST_SIZE=$(struct_size mlx5_buf_list)
BUF_LIST_OFF_MAP=$(member_offset mlx5_buf_list map)

cat <<EOF
export MLX5_RQ_OFF_WQ_CTRL=${RQ_OFF_WQ_CTRL}
export MLX5_RQ_OFF_IX=${RQ_OFF_IX}
export MLX5_RQ_OFF_WQ_TYPE=${RQ_OFF_WQ_TYPE}
export MLX5_RQ_OFF_RQN=${RQ_OFF_RQN}
export MLX5_RQ_OFF_PDEV=${RQ_OFF_PDEV}
export MLX5_SQ_OFF_WQ_CTRL=${SQ_OFF_WQ_CTRL}
export MLX5_SQ_OFF_CH_IX=${SQ_OFF_CH_IX}
export MLX5_SQ_OFF_TXQ_IX=${SQ_OFF_TXQ_IX}
export MLX5_SQ_OFF_SQN=${SQ_OFF_SQN}
export MLX5_SQ_OFF_PDEV=${SQ_OFF_PDEV}
export MLX5_CQ_OFF_WQ_CTRL=${CQ_OFF_WQ_CTRL}
export MLX5_WQ_CTRL_OFF_BUF=${WQ_CTRL_OFF_BUF}
export MLX5_WQ_CTRL_OFF_DB=${WQ_CTRL_OFF_DB}
export MLX5_DB_OFF_DMA=${DB_OFF_DMA}
export MLX5_FRAG_BUF_OFF_FRAGS=${FRAG_BUF_OFF_FRAGS}
export MLX5_FRAG_BUF_OFF_NPAGES=${FRAG_BUF_OFF_NPAGES}
export MLX5_BUF_LIST_SIZE=${BUF_LIST_SIZE}
export MLX5_BUF_LIST_OFF_MAP=${BUF_LIST_OFF_MAP}
EOF