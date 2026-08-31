#!/usr/bin/env bash
set -euo pipefail

# Run E2B concurrent benchmark for one concurrency level and summarize key metrics.
#
# Required:
#   -c <concurrency>
#   -n <total_requests>
#
# Optional:
#   -o <output_dir>            Default: /tmp/e2b-opt-YYYYmmdd-HHMMSS
#   -t <go_test_timeout>       Default: 30m
#   --skip-preflight           Do not run preflight cleanup before benchmark
#
# Example:
#   ./run_concurrency_bench.sh -c 8 -n 640

usage() {
  cat <<'USAGE'
Usage:
  run_concurrency_bench.sh -c <concurrency> -n <total_requests> [-o <output_dir>] [-t <go_test_timeout>] [--skip-preflight]

Arguments:
  -c    Concurrency (positive integer)
  -n    Total request/sample target (positive integer)
  -o    Output directory (default: /tmp/e2b-opt-YYYYmmdd-HHMMSS)
  -t    go test timeout (default: 30m)
  --skip-preflight   Skip preflight cleanup
  -h, --help         Show this help
USAGE
}

require_cmd() {
  local c="$1"
  if ! command -v "$c" >/dev/null 2>&1; then
    echo "[error] missing command: $c" >&2
    exit 1
  fi
}

is_pos_int() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

CONCURRENCY=""
TOTAL_REQUESTS=""
GO_TEST_TIMEOUT="30m"
OUTPUT_DIR=""
RUN_PREFLIGHT=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c)
      CONCURRENCY="${2:-}"
      shift 2
      ;;
    -n)
      TOTAL_REQUESTS="${2:-}"
      shift 2
      ;;
    -o)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    -t)
      GO_TEST_TIMEOUT="${2:-}"
      shift 2
      ;;
    --skip-preflight)
      RUN_PREFLIGHT=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[error] unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if ! is_pos_int "${CONCURRENCY:-0}"; then
  echo "[error] -c must be a positive integer" >&2
  usage
  exit 2
fi

if ! is_pos_int "${TOTAL_REQUESTS:-0}"; then
  echo "[error] -n must be a positive integer" >&2
  usage
  exit 2
fi

require_cmd awk
require_cmd grep
require_cmd sed
require_cmd date
require_cmd go

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="/tmp/e2b-opt-$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$OUTPUT_DIR"

# iterations = ceil(total_requests / concurrency)
ITERATIONS=$(( (TOTAL_REQUESTS + CONCURRENCY - 1) / CONCURRENCY ))
TARGET_SAMPLES=$(( CONCURRENCY * ITERATIONS ))

LOG_PATH="$OUTPUT_DIR/c${CONCURRENCY}_n${TOTAL_REQUESTS}_b${ITERATIONS}.log"

if [[ "$RUN_PREFLIGHT" -eq 1 ]]; then
  if [[ -x "$SCRIPT_DIR/preflight_benchmark_env.sh" ]]; then
    "$SCRIPT_DIR/preflight_benchmark_env.sh" --apply > "$OUTPUT_DIR/preflight_c${CONCURRENCY}_b${ITERATIONS}.log" 2>&1 || true
  else
    echo "[warn] preflight script not found or not executable, skip preflight" >&2
  fi
fi

# Run exactly one sub-benchmark case.
# NOTE: total sample count in output depends on OK/FAIL and is reported from logs.
set +e
timeout 2400s env CONCURRENCY_LEVELS="$CONCURRENCY" GOTOOLCHAIN=auto \
  go test -run='^$' -bench="BenchmarkConcurrentResume/concurrency-${CONCURRENCY}\$" -benchtime="${ITERATIONS}x" -count=1 -timeout="$GO_TEST_TIMEOUT" -v ./... \
  > "$LOG_PATH" 2>&1 &
BENCH_PID=$!

progress_done=0
progress_err=0
printf '\rTotal Request: %d, %d/%d, error: %d ' "$TARGET_SAMPLES" "$progress_done" "$TARGET_SAMPLES" "$progress_err"

while kill -0 "$BENCH_PID" >/dev/null 2>&1; do
  # Approximate completion from benchmark firecracker launches; subtract warmup sandbox.
  raw_done=$(grep -c 'Running Firecracker v' "$LOG_PATH" 2>/dev/null || true)
  if [[ "$raw_done" -gt 0 ]]; then
    progress_done=$((raw_done - 1))
  else
    progress_done=0
  fi

  if [[ "$progress_done" -lt 0 ]]; then
    progress_done=0
  fi
  if [[ "$progress_done" -gt "$TARGET_SAMPLES" ]]; then
    progress_done="$TARGET_SAMPLES"
  fi

  progress_err=$(grep -c 'FAIL sandbox' "$LOG_PATH" 2>/dev/null || true)

  printf '\rTotal Request: %d, %d/%d, error: %d '  "$TARGET_SAMPLES" "$progress_done" "$TARGET_SAMPLES" "$progress_err"
  sleep 1
done

wait "$BENCH_PID"
RUN_RC=$?
printf '\rTotal Request: %d, %d/%d, error: %d \n' "$TARGET_SAMPLES" "$progress_done" "$TARGET_SAMPLES" "$progress_err"
set -e

BENCH_LINE="$(grep -E "BenchmarkConcurrentResume/concurrency-${CONCURRENCY}-" "$LOG_PATH" | tail -n 1 || true)"
CONC_LINE="$(grep -E "concurrency=${CONCURRENCY}:" "$LOG_PATH" | tail -n 1 || true)"
PKG_LINE="$(grep -E '^ok[[:space:]]+github.com/e2b-dev/infra/packages/orchestrator/benchmarks' "$LOG_PATH" | tail -n 1 || true)"

OK_COUNT="$(echo "$CONC_LINE" | sed -n 's/.*concurrency=[0-9]\+: \([0-9]\+\) ok, \([0-9]\+\) fail.*/\1/p')"
FAIL_COUNT="$(echo "$CONC_LINE" | sed -n 's/.*concurrency=[0-9]\+: \([0-9]\+\) ok, \([0-9]\+\) fail.*/\2/p')"
AVG_MS="$(echo "$BENCH_LINE" | sed -n 's/.* \([0-9.][0-9.]*\) avg-ms.*/\1/p')"
P95_MS="$(echo "$BENCH_LINE" | sed -n 's/.* \([0-9.][0-9.]*\) p95-ms.*/\1/p')"
P99_MS="$(echo "$BENCH_LINE" | sed -n 's/.* \([0-9.][0-9.]*\) p99-ms.*/\1/p')"
WALL_BATCH_MS="$(echo "$BENCH_LINE" | sed -n 's/.* \([0-9.][0-9.]*\) wall-clock-ms.*/\1/p')"
NS_OP="$(echo "$BENCH_LINE" | sed -n 's/.*-[0-9][0-9]*[[:space:]]\+[0-9][0-9]*[[:space:]]\+\([0-9][0-9]*\) ns\/op.*/\1/p')"
TOTAL_ELAPSED_S="$(echo "$PKG_LINE" | grep -oE '[0-9]+\.[0-9]+s|[0-9]+s' | tail -n1 | tr -d 's')"

THROUGHPUT=""
if [[ -n "$OK_COUNT" && -n "$TOTAL_ELAPSED_S" ]]; then
  THROUGHPUT="$(awk -v ok="$OK_COUNT" -v t="$TOTAL_ELAPSED_S" 'BEGIN{if(t>0) printf "%.2f", ok/t; else print ""}')"
fi

SUMMARY_PATH="$OUTPUT_DIR/c${CONCURRENCY}_n${TOTAL_REQUESTS}_summary.txt"
{
  echo "log_path=$LOG_PATH"
  echo "concurrency=$CONCURRENCY"
  echo "requested_total=$TOTAL_REQUESTS"
  echo "iterations=$ITERATIONS"
  echo "target_samples(concurrency*iterations)=$TARGET_SAMPLES"
  echo "ok_count=${OK_COUNT:-}"
  echo "fail_count=${FAIL_COUNT:-}"
  echo "avg_ms=${AVG_MS:-}"
  echo "p95_ms=${P95_MS:-}"
  echo "p99_ms=${P99_MS:-}"
  echo "wall_clock_batch_ms=${WALL_BATCH_MS:-}"
  echo "total_elapsed_s=${TOTAL_ELAPSED_S:-}"
  echo "avg_throughput_req_per_s=${THROUGHPUT:-}"
  echo "ns_op=${NS_OP:-}"
  echo "go_test_rc=$RUN_RC"
} > "$SUMMARY_PATH"

# User-facing output
printf 'log_path: %s\n' "$LOG_PATH"
printf 'avg_ms: %s\n' "${AVG_MS:-N/A}"
printf 'p95_ms: %s\n' "${P95_MS:-N/A}"
printf 'p99_ms: %s\n' "${P99_MS:-N/A}"
printf 'total_elapsed_s: %s\n' "${TOTAL_ELAPSED_S:-N/A}"
printf 'avg_throughput_req_per_s: %s\n' "${THROUGHPUT:-N/A}"
printf 'summary_file: %s\n' "$SUMMARY_PATH"

# Keep non-zero rc if benchmark command failed and no parseable metrics
if [[ $RUN_RC -ne 0 && -z "$AVG_MS" ]]; then
  echo "[error] benchmark command failed and no metrics were parsed; inspect log: $LOG_PATH" >&2
  exit $RUN_RC
fi

exit 0
