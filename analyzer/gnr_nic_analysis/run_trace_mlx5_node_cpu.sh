#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BT_SCRIPT="${BT_SCRIPT:-${SCRIPT_DIR}/trace_mlx5_node_cpu.bt}"
DURATION="${DURATION:-20}"
OUT_DIR="${OUT_DIR:-${SCRIPT_DIR}/mlx5_node_cpu_$(date +%Y%m%d_%H%M%S)}"
LOG_FILE="${OUT_DIR}/mlx5_node_cpu.log"

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Required command missing: $1" >&2
        exit 1
    }
}

require_cmd bpftrace
require_cmd timeout

if [[ ! -f "$BT_SCRIPT" ]]; then
    echo "bpftrace script not found: $BT_SCRIPT" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"

echo "Running ${BT_SCRIPT} for ${DURATION}s"
echo "Output: ${LOG_FILE}"

set +e
timeout "$((DURATION + 5))" bpftrace -q "$BT_SCRIPT" > "$LOG_FILE"
RC=$?
set -e

if [[ "$RC" -ne 0 && "$RC" -ne 124 ]]; then
    echo "bpftrace failed with rc=${RC}" >&2
    exit "$RC"
fi

echo "Done. Log saved to: ${LOG_FILE}"
echo "Quick preview:"
grep -E 'OPEN_QUEUES|OPEN_RQ|COMP_IRQ_AFF_MASK' "$LOG_FILE" | head -n 40 || true
