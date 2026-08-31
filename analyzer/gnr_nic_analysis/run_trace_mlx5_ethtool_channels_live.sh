#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BT_SCRIPT="${BT_SCRIPT:-${SCRIPT_DIR}/trace_mlx5_ethtool_channels_live.bt}"
DURATION="${DURATION:-30}"
OUT_DIR="${OUT_DIR:-${SCRIPT_DIR}/mlx5_ethtool_channels_live_$(date +%Y%m%d_%H%M%S)}"
LOG_FILE="${OUT_DIR}/mlx5_ethtool_channels_live.log"

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

cat > "${OUT_DIR}/README.txt" <<EOF
Run this script, then in another terminal run for example:
  ethtool -L ens7f0np0 combined 2

Environment:
  DURATION=${DURATION}
  BT_SCRIPT=${BT_SCRIPT}

Main log:
  ${LOG_FILE}
EOF

echo "Running ${BT_SCRIPT} for ${DURATION}s"
echo "Output: ${LOG_FILE}"
echo "Trigger in another terminal: ethtool -L ens7f0np0 combined 2"

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
grep -E '^EVT ' "$LOG_FILE" | head -n 80 || true
