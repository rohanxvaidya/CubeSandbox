#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  capture_core_flamegraph.sh [options]

Options:
  -p <pid>      Target PID. If omitted, auto-detect rdma_test_tool client on core.
  -c <core>     CPU core to match for auto-detect. Default: 64
  -d <seconds>  Perf recording duration. Default: 20
  -F <freq>     Perf sample frequency (Hz). Default: 199
  -w <dir>      Working/output base directory. Default: /home/mz/rdma/rdma_test
  -g <dir>      FlameGraph tool directory. Default: /home/mz/tools/FlameGraph
  -h            Show this help.

Examples:
  ./capture_core_flamegraph.sh
  ./capture_core_flamegraph.sh -c 64 -d 30 -F 299
  ./capture_core_flamegraph.sh -p 915862
EOF
}

CORE=64
DURATION=20
FREQ=199
WORKDIR="/home/mz/rdma/rdma_test"
FLAMEGRAPH_DIR="/home/mz/tools/FlameGraph"
PID=""

while getopts ":p:c:d:F:w:g:h" opt; do
  case "$opt" in
    p) PID="$OPTARG" ;;
    c) CORE="$OPTARG" ;;
    d) DURATION="$OPTARG" ;;
    F) FREQ="$OPTARG" ;;
    w) WORKDIR="$OPTARG" ;;
    g) FLAMEGRAPH_DIR="$OPTARG" ;;
    h)
      usage
      exit 0
      ;;
    :)
      echo "Missing value for -$OPTARG" >&2
      usage
      exit 2
      ;;
    \?)
      echo "Unknown option: -$OPTARG" >&2
      usage
      exit 2
      ;;
  esac
done

if ! command -v perf >/dev/null 2>&1; then
  echo "perf is not installed or not in PATH" >&2
  exit 1
fi

if [[ ! -x "$FLAMEGRAPH_DIR/stackcollapse-perf.pl" || ! -x "$FLAMEGRAPH_DIR/flamegraph.pl" ]]; then
  echo "FlameGraph tools not found or not executable in: $FLAMEGRAPH_DIR" >&2
  exit 1
fi

if [[ -z "$PID" ]]; then
  PID="$(ps -eo pid,psr,args --sort=pid | awk -v core="$CORE" '$2 == core && /rdma_test_tool/ && / -c / { print $1; exit }')"
fi

if [[ -z "$PID" ]]; then
  echo "No rdma_test_tool client process found on core $CORE" >&2
  exit 1
fi

if ! kill -0 "$PID" 2>/dev/null; then
  echo "PID $PID is not running" >&2
  exit 1
fi

mkdir -p "$WORKDIR"
TS="$(date +%Y%m%d_%H%M%S)"
OUTDIR="$WORKDIR/perf_flame_${TS}"
mkdir -p "$OUTDIR"

echo "Target PID: $PID"
echo "Core: $CORE"
echo "Duration: ${DURATION}s"
echo "Frequency: ${FREQ}Hz"
echo "Output directory: $OUTDIR"

perf record -F "$FREQ" -g -p "$PID" -o "$OUTDIR/perf.data" -- sleep "$DURATION"
perf script -i "$OUTDIR/perf.data" > "$OUTDIR/perf.script"
"$FLAMEGRAPH_DIR/stackcollapse-perf.pl" "$OUTDIR/perf.script" > "$OUTDIR/out.folded"

SVG_NAME="rdma_test_tool_client_core${CORE}.svg"
"$FLAMEGRAPH_DIR/flamegraph.pl" "$OUTDIR/out.folded" > "$OUTDIR/$SVG_NAME"

echo
echo "Generated artifacts:"
echo "  $OUTDIR/perf.data"
echo "  $OUTDIR/perf.script"
echo "  $OUTDIR/out.folded"
echo "  $OUTDIR/$SVG_NAME"
