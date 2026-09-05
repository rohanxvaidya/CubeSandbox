#!/usr/bin/env bash
set -uo pipefail
# Finite create-delete latency sweep using the REPO's exact per-point cube-bench
# command (as in run_benchmark_288C576G_scaling.sh): -m create-delete -w 3, one
# finite run per concurrency (n = c*10) so avg/p95 are written to JSON.
BENCH=/root/cube-src/CubeSandbox/examples/cube-bench/bin/cube-bench
TID=${CUBE_TEMPLATE_ID:-tpl-cea9de24f21d4d4fac319a15}
export E2B_API_URL=http://127.0.0.1:3000 E2B_API_KEY=e2b_000000 NO_PROXY='*' no_proxy='*'
CLEANUP=/root/linux-io-e2e-performance-analysis/benchmacking/Sandbox/cubeSandbox/tools/cleanup_sandboxes.sh
OUT=/data/cwf-e2e-repo-latency-sweep-$(date +%Y%m%d-%H%M%S); mkdir -p "$OUT"
echo "OUT=$OUT"
CSV="$OUT/cwf_sweep_createdelete.csv"
echo "concurrency,n_total,create_avg_ms,create_p50_ms,create_p95_ms,create_p99_ms,delete_avg_ms,throughput_sb_s,success_pct,errors" > "$CSV"

cleanup(){ API_URL="$E2B_API_URL" API_KEY="$E2B_API_KEY" "$CLEANUP" >/dev/null 2>&1 || true; }
cpupower -c all frequency-set -g performance >/dev/null 2>&1 || true

for c in $(seq 100 10 350); do
  n=$((c*10))
  cleanup; sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
  "$BENCH" --no-tui -m create-delete -c "$c" -n "$n" -w 3 -t "$TID" \
    --api-url "$E2B_API_URL" --api-key "$E2B_API_KEY" -o "$OUT/c${c}_n${n}.json" > "$OUT/c${c}.log" 2>&1 || true
  python3 - "$OUT/c${c}_n${n}.json" "$c" "$n" >> "$CSV" <<'PY'
import json,sys
f,c,n=sys.argv[1],sys.argv[2],sys.argv[3]
try:
    d=json.load(open(f)); cr=d["create"]; de=d.get("delete",{}); s=d["summary"]
    print(f"{c},{n},{round(cr['avg'],1)},{round(cr['p50'],1)},{round(cr['p95'],1)},{round(cr['p99'],1)},{round(de.get('avg',0),1)},{round(s['throughput_qps'],1)},{round(s['success_rate']*100,1)},{s['errors']}")
except Exception as e:
    print(f"{c},{n},NA,NA,NA,NA,NA,NA,NA,NA")
PY
  echo "done c=$c" | tee -a "$OUT/sweep.log"
  cleanup; sleep 3
done
echo "=== LATENCY SWEEP DONE: $OUT ==="
