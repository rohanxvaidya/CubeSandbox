#!/usr/bin/env bash
set -euovx pipefail # strict mode + debug + verbose
export PS4='+${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }' # line number shown on failure

# CWF create-delete concurrency sweep (matches run_benchmark_288C576G_scaling.sh):
#   cube-bench -m create-delete -w 3, -c 100..350 step 10, n = c*10, avg create latency per point.
export E2B_API_URL=${E2B_API_URL:-http://127.0.0.1:3000}
export E2B_API_KEY=${E2B_API_KEY:-e2b_000000}
TID=${CUBE_TEMPLATE_ID:-tpl-cea9de24f21d4d4fac319a15}
BENCH=/root/cube-src/CubeSandbox/examples/cube-bench/bin/cube-bench
OUT=/data/cwf-sweep-createdelete-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"
echo "OUT=$OUT"

cleanup(){
  local tries=0
  while :; do
    local ids
    ids=$(curl -s -H "X-API-Key: $E2B_API_KEY" "$E2B_API_URL/sandboxes" \
      | python3 -c 'import sys,json;[print(x["sandboxID"]) for x in json.load(sys.stdin)]')
    [ -z "$ids" ] && break
    for i in $ids; do curl -s -o /dev/null -X DELETE -H "X-API-Key: $E2B_API_KEY" "$E2B_API_URL/sandboxes/$i" || true; done
    tries=$((tries+1)); [ "$tries" -gt 240 ] && break
    sleep 1
  done
}

cpupower -c all frequency-set -g performance >/dev/null 2>&1 || true

for c in $(seq 100 10 350); do
  n=$((c*10))
  cleanup; sync; echo 3 > /proc/sys/vm/drop_caches || true
  "$BENCH" --no-tui -m create-delete -c "$c" -n "$n" -w 3 -t "$TID" \
    --api-url "$E2B_API_URL" --api-key "$E2B_API_KEY" \
    -o "$OUT/c${c}_n${n}.json" > "$OUT/c${c}.log" 2>&1 || true
  # progress line to the driver log
  avg=$(python3 -c "import json;d=json.load(open('$OUT/c${c}_n${n}.json'));print(round(d['create']['avg'],1))" 2>/dev/null || echo NA)
  echo "SWEEP c=$c n=$n create_avg=${avg}ms" | tee -a "$OUT/sweep.log"
  cleanup; sleep 4
done

# ---- reduce all points to a CSV ----
python3 - "$OUT" <<'PY'
import json,glob,os,sys,csv
d=sys.argv[1]
rows=[]
for f in glob.glob(os.path.join(d,"c*_n*.json")):
    j=json.load(open(f)); cfg=j["config"]; cr=j["create"]; de=j.get("delete",{}); s=j["summary"]
    rows.append([cfg["concurrency"], cfg["total"], round(cr["avg"],1), round(cr["p50"],1),
                 round(cr["p95"],1), round(cr["p99"],1),
                 round(de.get("avg",0),1), round(s["throughput_qps"],1),
                 round(s["success_rate"]*100,1), s["errors"]])
rows.sort(key=lambda r:r[0])
out=os.path.join(d,"cwf_sweep_createdelete.csv")
with open(out,"w",newline="") as fh:
    w=csv.writer(fh)
    w.writerow(["concurrency","n_total","create_avg_ms","create_p50_ms","create_p95_ms","create_p99_ms","delete_avg_ms","throughput_sb_s","success_pct","errors"])
    w.writerows(rows)
print("wrote",out,"points:",len(rows))
for r in rows: print(r)
PY
echo "=== SWEEP DONE: $OUT ==="
