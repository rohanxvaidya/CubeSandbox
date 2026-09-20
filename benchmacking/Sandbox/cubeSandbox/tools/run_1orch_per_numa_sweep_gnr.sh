#!/bin/bash
# GNR 1-orch-per-NUMA sweep (mirror of CWF run_3orch_per_numa_sweep.sh), 3 NUMA nodes (SNC3).
# Single shared CubeMaster (1 orchestrator) + cube-bench driver split into 3 NUMA-pinned
# streams. At each aggregate concurrency C, split evenly across the 3 streams.
# The 6 control-plane containers are kept up and monitored throughout (uptime.log).
set -uo pipefail
BENCH=/root/CubeSandbox/examples/cube-bench/bin/cube-bench
TID=${CUBE_TEMPLATE_ID:-tpl-52cda1f349a24f4f96b884c3}
E2B_API_URL=${E2B_API_URL:-http://127.0.0.1:3000}
E2B_API_KEY=${E2B_API_KEY:-e2b_000000}
export NO_PROXY='*' no_proxy='*'
OUT=/data/gnr_createdelete_1orch-perNUMA-3stream_$(readlink /usr/local/services/cubetoolbox/cube-kernel-scf/vmlinux)_tpl-52cd_$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"; echo "OUT=$OUT"
# GNR SNC3 per-node CPU ranges (from /sys/devices/system/node; two SMT halves per node).
declare -A RANGE=([0]="0-42,128-170" [1]="43-85,171-213" [2]="86-127,214-255")
CONTAINERS=(cube-webui cube-proxy cube-egress cube-sandbox-redis cube-sandbox-mysql cube-proxy-coredns)
MON="$OUT/uptime.log"; : > "$MON"
cleanup(){ ids=$(curl -s --noproxy '*' -H "X-API-Key: $E2B_API_KEY" "$E2B_API_URL/sandboxes" 2>/dev/null | python3 -c 'import sys,json;[print(x["sandboxID"]) for x in json.load(sys.stdin)]' 2>/dev/null); for i in $ids; do curl -s --noproxy '*' -o /dev/null -X DELETE -H "X-API-Key: $E2B_API_KEY" "$E2B_API_URL/sandboxes/$i" 2>/dev/null; done; }
# keep-alive monitor: log any container that is not Running (checked every 2s)
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
  # combine the 3 streams into one aggregate point (n-weighted create avg/p95)
  python3 - "$OUT" "$AGG" "$base" >> "$OUT/sweep.csv" <<'PY'
import sys,json,os
d,agg,per=sys.argv[1],int(sys.argv[2]),sys.argv[3]
tot_n=0; wavg=0; wp95=0; err=0
for node in (0,1,2):
    f=os.path.join(d,f'agg{agg}_node{node}.json')
    if not os.path.exists(f): continue
    j=json.load(open(f)); cr=j['create']; n=j.get('config',{}).get('total',0) or 0
    tot_n+=n; wavg+=cr['avg']*n; wp95+=cr.get('p95',0)*n
    err+=j.get('errors',0) or 0
avg=wavg/tot_n if tot_n else 0; p95=wp95/tot_n if tot_n else 0
print(f"{agg},{per},{avg:.3f},{p95:.3f},{100.0 if err==0 else 0},{err}")
PY
  line=$(tail -1 "$OUT/sweep.csv"); echo "AGG=$AGG (per~$base x3) -> $line"
  cleanup; sleep 4
done
kill "$MONPID" 2>/dev/null
echo "SWEEP DONE: $OUT  downtime_events=$(wc -l < "$MON")"
