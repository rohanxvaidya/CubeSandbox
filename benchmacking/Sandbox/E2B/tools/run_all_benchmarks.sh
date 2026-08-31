#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
OUT_DIR="${1:-$ROOT_DIR/benchmark_reports/e2b-local-$RUN_ID}"
mkdir -p "$OUT_DIR"

"$ROOT_DIR/scripts/e2b-local/setup_local_prereqs.sh"

base_csv="$($ROOT_DIR/scripts/e2b-local/run_base_launch_matrix.sh "$OUT_DIR")"
conc_csv="$($ROOT_DIR/scripts/e2b-local/run_concurrent_resume_matrix.sh "$OUT_DIR")"

summary_md="$OUT_DIR/summary.md"
{
  echo "# E2B Local Benchmark Summary"
  echo
  echo "Run ID: $RUN_ID"
  echo ""
  echo "## Artifacts"
  echo "- Base launch matrix: $base_csv"
  echo "- Concurrent resume matrix: $conc_csv"
  echo
  echo "## Base Launch (top rows)"
  echo '```csv'
  head -n 8 "$base_csv"
  echo '```'
  echo
  echo "## Concurrent Resume (top rows)"
  echo '```csv'
  head -n 8 "$conc_csv"
  echo '```'
} > "$summary_md"

echo "$OUT_DIR"
