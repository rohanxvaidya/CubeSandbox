#!/bin/bash
# 3-orchestrator-per-NUMA FULL sweep, comparable to the 1-orch-all-NUMA RUN 2.
# At each aggregate concurrency C, split evenly across 3 NUMA-pinned cube-bench streams.
set -uo pipefail
BENCH=/root/cube-src/CubeSandbox/examples/cube-bench/bin/cube-bench
TID=${CUBE_TEMPLATE_ID:-tpl-cea9de24f21d4d4fac319a15}
E2B_API_URL=${E2B_API_URL:-http://127.0.0.1:3000}
E2B_API_KEY=${E2B_API_KEY:-e2b_000000}
export NO_PROXY='*' no_proxy='*'
OUT=/data/cwf_createdelete_repo-scaling-benchmark_3orch-perNUMA_6.6.119-49.6-rebuild_tpl-cea9_$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"; echo "OUT=$OUT"
declare -A RANGE=([0]=0-95 [1]=96-191 [2]=192-287)
CONTAINERS=(cube-webui cube-proxy cube-egress cube-sandbox-redis cube-sandbox-mysql cube-proxy-coredns)
MON="$OUT/uptime.log"; : > "$MON"
cleanup(){ ids=$(curl -s --noproxy '*' -H "X-API-Key: $E2B_API_KEY" "$E2B_API_URL/sandboxes" 2>/dev/null | python3 -c 'import sys,json;[print(x["sandboxID"]) for x in json.load(sys.stdin)]' 2>/dev/null); for i in $ids; do curl -s --noproxy '*' -o /dev/null -X DELETE -H "X-API-Key: $E2B_API_KEY" "$E2B_API_URL/sandboxes/$i" 2>/dev/null; done; }
( while true; do for c in "${CONTAINERS[@]}"; do st=$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null); [ "$st" != "true" ] && echo "$(date +%T) DOWN $c" >> "$MON"; done; sleep 2; done ) & MONPID=$!
cpupower -c all frequency-set -g performance >/dev/null 2>&1 || true
echo "orchestrator=1x cubemaster affinity=$(taskset -pc $(pgrep -x cubemaster|head -1) 2>/dev/null | awk -F': ' '{print $2}'); driver=3 NUMA-pinned streams; template=$TID kernel=$(readlink /usr/local/services/cubetoolbox/cube-kernel-scf/vmlinux)" | tee "$OUT/meta.txt"
: > "$OUT/sweep.csv"
echo "agg_concurrency,per_stream,create_avg_ms,p95_ms,success_pct,errors" >> "$OUT/sweep.csv"
for AGG in $(seq 100 10 350); do
  base=$((AGG/3)); s0=$((AGG-2*base)); declare -a S=($s0 $base $base)
  cleanup; sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
  pids=()
  for node in 0 1 2; do
    c=${S[$node]}; n=$((c*10))
    taskset -c "${RANGE[$node]}" "$BENCH" --no-tui -m create-delete -c "$c" -n "$n" -w 3 -t "$TID" \
      --api-url "$E2B_API_URL" --api-key "$E2B_API_KEY" -o "$OUT/agg${AGG}_node${node}.json" > "$OUT/agg${AGG}_node${node}.log" 2>&1 &
    pids+=($!)
  done
  for p in "${pids[@]}"; do wait "$p"; done
  # combine the 3 streams into an aggregate point
  python3 - "$OUT" "$AGG" "$base" >> "$OUT/sweep.csv" <<'PY'
import sys,json,os
d,agg,per=sys.argv[1],int(sys.argv[2]),sys.argv[3]
tot_n=0; wavg=0; wp95=0; err=0; ok=True
for node in (0,1,2):
    f=os.path.join(d,f'agg{agg}_node{node}.json')
    if not os.path.exists(f): ok=False; continue
    j=json.load(open(f)); cr=j['create']; n=j.get('config',{}).get('total',0) or 0
    tot_n+=n; wavg+=cr['avg']*n; wp95+=cr.get('p95',0)*n
    sr=j.get('success_rate',1); err+=j.get('errors',0) or 0
    if sr not in (1,1.0): ok=False
avg=wavg/tot_n if tot_n else 0; p95=wp95/tot_n if tot_n else 0
print(f"{agg},{per},{avg:.3f},{p95:.3f},{100.0 if err==0 else 0},{err}")
PY
  line=$(tail -1 "$OUT/sweep.csv"); echo "AGG=$AGG (per~$base x3) -> $line"
  cleanup; sleep 4
done
kill "$MONPID" 2>/dev/null
echo "SWEEP DONE: $OUT  downtime_events=$(wc -l < "$MON")"
