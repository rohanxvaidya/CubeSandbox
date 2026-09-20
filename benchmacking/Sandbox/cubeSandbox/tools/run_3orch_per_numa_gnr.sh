#!/usr/bin/env bash
# GNR "1 orchestrator per NUMA node" sweep (mirror of Turin run_sweep_1orch_per_numa.sh).
# Launches 3 numactl-pinned CubeMasters (one per NUMA node, ports 8089/8090/8091),
# sharing the single Cubelet/MySQL/Redis. node0 keeps :8089 so Cubelet stays registered.
# Drives a single-stream create-delete sweep (c=100..350) through :3000, keeping the 6
# control-plane containers up + monitored. Fully reversible: on exit restores systemd master.
set -uo pipefail
TOOLBOX="/usr/local/services/cubetoolbox"
MASTER_BIN="${TOOLBOX}/CubeMaster/bin/cubemaster"
BASE_CFG="${TOOLBOX}/CubeMaster/conf.yaml"
BASE_PORT=8089
BENCH=/root/CubeSandbox/examples/cube-bench/bin/cube-bench
API_URL="http://127.0.0.1:3000"
API_KEY="e2b_000000"
TID="${CUBE_TEMPLATE_ID:-tpl-52cda1f349a24f4f96b884c3}"
export NO_PROXY='*' no_proxy='*'
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY 2>/dev/null || true

NNODES=$(numactl -H | awk '/^available:/{print $2}')
echo "NUMA nodes detected: ${NNODES}"
CFG_DIR="$(mktemp -d /tmp/permaster.XXXXXX)"
declare -a PIDS=()
CONTAINERS=(cube-webui cube-proxy cube-egress cube-sandbox-redis cube-sandbox-mysql cube-proxy-coredns)

TS=$(date +%Y%m%d-%H%M%S)
OUT="/data/gnr_createdelete_1orch-perNUMAorch-${NNODES}masters_$(readlink ${TOOLBOX}/cube-kernel-scf/vmlinux)_tpl-52cd_${TS}"
mkdir -p "${OUT}"; echo "OUT=${OUT}"
MON="${OUT}/uptime.log"; : > "${MON}"

cleanup_sb(){ for r in 1 2 3 4; do ids=$(curl -s --noproxy '*' -H "X-API-Key: ${API_KEY}" "${API_URL}/sandboxes" | python3 -c 'import sys,json;[print(x["sandboxID"]) for x in json.load(sys.stdin)]' 2>/dev/null); [ -z "$ids" ] && break; echo "$ids" | xargs -P16 -I{} curl -s --noproxy '*' -o /dev/null -X DELETE -H "X-API-Key: ${API_KEY}" "${API_URL}/sandboxes/{}"; done; }

teardown(){
  echo "=== teardown: restore single systemd orchestrator ==="
  kill "${MONPID:-}" 2>/dev/null || true
  cleanup_sb
  for p in "${PIDS[@]:-}"; do [ -n "${p}" ] && kill "${p}" 2>/dev/null || true; done
  sleep 2
  for p in "${PIDS[@]:-}"; do [ -n "${p}" ] && kill -9 "${p}" 2>/dev/null || true; done
  systemctl start cube-sandbox-cubemaster 2>/dev/null || true
  sleep 3
  echo -n "systemd cubemaster: "; systemctl is-active cube-sandbox-cubemaster
  rm -rf "${CFG_DIR}"
}
trap teardown EXIT INT TERM

# keep-alive monitor for the 6 containers
( while true; do for c in "${CONTAINERS[@]}"; do st=$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null); [ "$st" != "true" ] && echo "$(date +%T) DOWN $c" >> "${MON}"; done; sleep 2; done ) & MONPID=$!

echo "=== stop systemd orchestrator (frees :8089) ==="
systemctl stop cube-sandbox-cubemaster; sleep 2

for ((n=0; n<NNODES; n++)); do
  port=$((BASE_PORT + n)); cfg="${CFG_DIR}/master-node${n}.yaml"; logdir="/data/log/CubeMaster-node${n}"; mkdir -p "${logdir}"
  sed "s/http_port: ${BASE_PORT}/http_port: ${port}/; s#path: \"/data/log/CubeMaster\"#path: \"${logdir}\"#" "${BASE_CFG}" > "${cfg}"
  echo "=== launch orchestrator node ${n} on :${port} (cpunodebind=${n} membind=${n}) ==="
  CUBE_MASTER_CONFIG_PATH="${cfg}" numactl --cpunodebind="${n}" --membind="${n}" "${MASTER_BIN}" > "/tmp/master-node${n}.log" 2>&1 &
  PIDS+=("$!"); sleep 3
done
sleep 5
echo "=== orchestrators ==="
for ((n=0; n<NNODES; n++)); do pid="${PIDS[$n]}"; port=$((BASE_PORT + n)); if kill -0 "${pid}" 2>/dev/null; then echo "node ${n}: pid=${pid} port=${port} affinity=$(taskset -pc ${pid} 2>/dev/null | awk -F': ' '{print $2}') listening=$(ss -ltn 2>/dev/null | grep -cE ":${port}\b")"; else echo "node ${n}: DIED"; tail -5 "/tmp/master-node${n}.log"; exit 1; fi; done

echo "=== smoke create/delete via cube-bench ==="
"${BENCH}" --no-tui -m create-delete -c 5 -n 20 -w 2 -t "${TID}" --api-url "${API_URL}" --api-key "${API_KEY}" -o "${OUT}/smoke.json" >/dev/null 2>&1 && echo "smoke OK" || { echo "SMOKE FAILED"; exit 1; }

cpupower -c all frequency-set -g performance >/dev/null 2>&1 || true
echo "orchestrators=${NNODES}x cubemaster (1 per NUMA, ports 8089..$((BASE_PORT+NNODES-1))); driver=single stream; template=${TID} kernel=$(readlink ${TOOLBOX}/cube-kernel-scf/vmlinux)" | tee "${OUT}/meta.txt"
echo "concurrency,n_total,create_avg_ms,create_p50_ms,create_p95_ms,create_p99_ms,delete_avg_ms,success_pct,errors" > "${OUT}/sweep.csv"

for c in $(seq 100 10 350); do
  n=$((c*10))
  cleanup_sb; sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
  "${BENCH}" --no-tui -m create-delete -c "$c" -n "$n" -w 3 -t "${TID}" --api-url "${API_URL}" --api-key "${API_KEY}" -o "${OUT}/c${c}.json" > "${OUT}/c${c}.log" 2>&1 || true
  python3 - "${OUT}/c${c}.json" "$c" "$n" >> "${OUT}/sweep.csv" <<'PY'
import sys,json,os
f,c,n=sys.argv[1],sys.argv[2],sys.argv[3]
try:
    j=json.load(open(f)); cr=j['create']; de=j.get('delete',{})
    sr=j.get('success_rate',1); err=j.get('errors',0) or 0
    print(f"{c},{n},{cr['avg']:.3f},{cr.get('p50',0):.3f},{cr.get('p95',0):.3f},{cr.get('p99',0):.3f},{de.get('avg',0):.3f},{sr*100:.1f},{err}")
except Exception as e:
    print(f"{c},{n},,,,,,,ERR:{e}")
PY
  echo "c=$c -> $(tail -1 "${OUT}/sweep.csv")"
  cleanup_sb; sleep 4
done
echo "SWEEP DONE: ${OUT}  downtime_events=$(wc -l < "${MON}")"
