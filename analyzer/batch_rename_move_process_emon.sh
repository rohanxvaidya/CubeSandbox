#!/bin/bash
set -euo pipefail

ROOT_DIR="${1:-/home/mz/0_work/1_ByteDance/bytedance_cxl/emon}"
EMON_TOOL="${2:-/root/Mydata-SPRinspur22/0_work/tools/Storage-performance-analysis/analyzer/emon_tool.sh}"

if [[ ! -d "$ROOT_DIR" ]]; then
  echo "ERROR: ROOT_DIR not found: $ROOT_DIR" >&2
  exit 1
fi

if [[ ! -f "$EMON_TOOL" ]]; then
  echo "ERROR: EMON_TOOL not found: $EMON_TOOL" >&2
  exit 1
fi

if [[ ! -x "$EMON_TOOL" ]]; then
  chmod +x "$EMON_TOOL" 2>/dev/null || true
fi

renamed=0
rename_skipped=0
processed=0
process_failed=0

echo "ROOT_DIR=$ROOT_DIR"
echo "EMON_TOOL=$EMON_TOOL"

# Phase 1: rename and move only source files directly under first-level dataset folders.
# Pattern: ROOT_DIR/<dataset>/<file>.dat
declare -a source_dats
while IFS= read -r -d '' dat; do
  source_dats+=("$dat")
done < <(find "$ROOT_DIR" -mindepth 2 -maxdepth 2 -type f -name "*.dat" -print0)

for dat in "${source_dats[@]}"; do
  parent_dir="$(dirname "$dat")"
  parent_name="$(basename "$parent_dir")"
  file_name="$(basename "$dat")"
  old_base="${file_name%.dat}"

  new_base="${parent_name}_${old_base}"
  new_dir="${parent_dir}/${new_base}"
  new_dat="${new_dir}/${new_base}.dat"

  if [[ -e "$new_dat" ]]; then
    echo "[SKIP-RENAME] target exists: $new_dat"
    ((rename_skipped+=1))
    continue
  fi

  mkdir -p "$new_dir"
  mv "$dat" "$new_dat"
  echo "[RENAMED] $dat -> $new_dat"
  ((renamed+=1))
done

# Phase 2: process only canonical moved files with pattern <dir>/<dir>.dat
declare -a to_process
while IFS= read -r -d '' dat; do
  d="$(dirname "$dat")"
  stem="$(basename "$d")"
  base="$(basename "$dat" .dat)"
  if [[ "$stem" == "$base" ]]; then
    to_process+=("$dat")
  fi
done < <(find "$ROOT_DIR" -type f -name "*.dat" -print0)

report_file="$ROOT_DIR/processing_report_$(date +%Y%m%d_%H%M%S).log"

echo "Process report: $report_file"

for dat in "${to_process[@]}"; do
  d="$(dirname "$dat")"
  stem="$(basename "$d")"
  out_xlsx="$d/$stem.xlsx"

  (
    cd "$d"
    bash "$EMON_TOOL" pro "$stem"
  ) >> "$report_file" 2>&1 || true

  if [[ -s "$out_xlsx" ]]; then
    echo "[PROCESSED] $out_xlsx"
    ((processed+=1))
  else
    echo "[FAIL] $dat (no xlsx generated)"
    ((process_failed+=1))
  fi
done

echo "SUMMARY: renamed=$renamed rename_skipped=$rename_skipped processed=$processed process_failed=$process_failed"
echo "DETAILS: $report_file"
if [[ "$process_failed" -gt 0 ]]; then
  exit 3
fi
