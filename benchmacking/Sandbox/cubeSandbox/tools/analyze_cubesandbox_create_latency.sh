#!/usr/bin/env bash
set -euo pipefail

# Run cube-bench and produce segmented create-latency analysis for this run only.
# It snapshots log file byte offsets before run, then extracts only appended logs.

E2B_API_URL="${E2B_API_URL:-http://127.0.0.1:3000}"
E2B_API_KEY="${E2B_API_KEY:-e2b_000000}"
CUBE_TEMPLATE_ID="${CUBE_TEMPLATE_ID:-tpl-b44020f969f64c32ab707607}"

BENCH_DIR="${BENCH_DIR:-/home/mz/cubeSandbox/CubeSandbox/examples/cube-bench}"
CONCURRENCY="${CONCURRENCY:-210}"
TOTAL="${TOTAL:-210}"
WARMUP="${WARMUP:-3}"
MODE="${MODE:-create-delete}"
OUT_JSON="${OUT_JSON:-/tmp/cube.json}"

CM_LOG="/data/log/CubeMaster/cubemaster-req.log"
CL_REQ_LOG="/data/log/Cubelet/Cubelet-req.log"
CL_STAT_LOG="/data/log/Cubelet/Cubelet-stat.log"

TS="$(date +%Y%m%d_%H%M%S)"
ANALYSIS_ROOT="/home/mz/cubeSandbox/benchmark_analysis"
RUN_DIR="${ANALYSIS_ROOT}/${TS}_c${CONCURRENCY}_n${TOTAL}_${MODE}"
mkdir -p "${RUN_DIR}"

for f in "$CM_LOG" "$CL_REQ_LOG" "$CL_STAT_LOG"; do
  if [[ ! -f "$f" ]]; then
    echo "missing log file: $f" >&2
    exit 1
  fi
done

CM_OFFSET="$(stat -c %s "$CM_LOG")"
CL_REQ_OFFSET="$(stat -c %s "$CL_REQ_LOG")"
CL_STAT_OFFSET="$(stat -c %s "$CL_STAT_LOG")"
START_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat > "${RUN_DIR}/run_context.env" <<EOF
E2B_API_URL=${E2B_API_URL}
E2B_API_KEY=${E2B_API_KEY}
CUBE_TEMPLATE_ID=${CUBE_TEMPLATE_ID}
BENCH_DIR=${BENCH_DIR}
CONCURRENCY=${CONCURRENCY}
TOTAL=${TOTAL}
WARMUP=${WARMUP}
MODE=${MODE}
OUT_JSON=${OUT_JSON}
CM_LOG=${CM_LOG}
CL_REQ_LOG=${CL_REQ_LOG}
CL_STAT_LOG=${CL_STAT_LOG}
START_UTC=${START_UTC}
EOF

pushd "$BENCH_DIR" >/dev/null
set +e
E2B_API_URL="$E2B_API_URL" \
E2B_API_KEY="$E2B_API_KEY" \
CUBE_TEMPLATE_ID="$CUBE_TEMPLATE_ID" \
./bin/cube-bench -c "$CONCURRENCY" -n "$TOTAL" -w "$WARMUP" -m "$MODE" -o "$OUT_JSON"
BENCH_RC=$?
set -e
popd >/dev/null

END_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "END_UTC=${END_UTC}" >> "${RUN_DIR}/run_context.env"
echo "BENCH_RC=${BENCH_RC}" >> "${RUN_DIR}/run_context.env"

if [[ -f "$OUT_JSON" ]]; then
    cp "$OUT_JSON" "${RUN_DIR}/cube.json"
fi

tail -c +$((CM_OFFSET + 1)) "$CM_LOG" > "${RUN_DIR}/cubemaster.delta.log"
tail -c +$((CL_REQ_OFFSET + 1)) "$CL_REQ_LOG" > "${RUN_DIR}/cubelet.req.delta.log"
tail -c +$((CL_STAT_OFFSET + 1)) "$CL_STAT_LOG" > "${RUN_DIR}/cubelet.stat.delta.log"

# Extract per-request create e2e/probe records from CubeMaster response ext_info.
jq -rc '
    select(.Action=="POST" and .CodeLine=="sandbox/sandbox_run.go:134")
    | select((.LogContent|type=="string") and (.LogContent|startswith("CreateSandbox_rsp:")))
    | (.LogContent | sub("^CreateSandbox_rsp:"; "") | fromjson?) as $rsp
    | select($rsp != null)
    | [
            ($rsp.RequestID // $rsp.requestID // .RequestId // ""),
            ($rsp.ext_info["cube-e2e"] // ""),
            ($rsp.ext_info["sandbox-probe"] // ""),
            (.RetCode//0),
            ."@timestamp"
        ]
  | @tsv
' "${RUN_DIR}/cubemaster.delta.log" > "${RUN_DIR}/cubemaster_segments.tsv" || true

# Extract per-request create stage traces from Cubelet stat log.
jq -rc '
  select(.Action=="Create" and (.RequestId|type=="string") and (.RequestId|length>0))
    | select((.Callee|type=="string") and (
            .Callee=="sandbox-binarystart"
            or .Callee=="sandbox-create"
            or .Callee=="sandbox-start"
            or .Callee=="sandbox-wait"
            or .Callee=="sandbox-probe"
            or .Callee=="cubebox-service-inner"
            or .Callee=="network"
            or .Callee=="storage"
    ))
  | [.RequestId, .Callee, (.CostTime//0), (.RetCode//0), ."@timestamp"]
  | @tsv
' "${RUN_DIR}/cubelet.stat.delta.log" > "${RUN_DIR}/cubelet_sandbox_segments.tsv" || true

python3 - "$RUN_DIR" <<'PY'
import csv
import json
import math
import statistics
import sys
from pathlib import Path

run_dir = Path(sys.argv[1])
cm_tsv = run_dir / "cubemaster_segments.tsv"
cl_tsv = run_dir / "cubelet_sandbox_segments.tsv"
json_path = run_dir / "cube.json"
per_req_csv = run_dir / "create_segment_breakdown_per_request.csv"
summary_txt = run_dir / "create_segment_summary.txt"

cm = {}
if cm_tsv.exists():
    for line in cm_tsv.read_text().splitlines():
        if not line.strip():
            continue
        rid, cube_e2e, sandbox_probe, ret, ts = line.split("\t")
        if not rid:
            continue
        d = cm.setdefault(rid, {})
        try:
            d["cube-e2e"] = float(cube_e2e) if cube_e2e != "" else None
        except ValueError:
            d["cube-e2e"] = None
        try:
            d["sandbox-probe"] = float(sandbox_probe) if sandbox_probe != "" else None
        except ValueError:
            d["sandbox-probe"] = None
        d.setdefault("retcode", int(ret) if str(ret).strip() else 0)
        d.setdefault("ts", ts)

cl = {}
if cl_tsv.exists():
    for line in cl_tsv.read_text().splitlines():
        if not line.strip():
            continue
        rid, stage, cost, ret, ts = line.split("\t")
        d = cl.setdefault(rid, {})
        d[stage] = d.get(stage, 0.0) + float(cost)
        d.setdefault("retcode", int(ret))
        d.setdefault("ts", ts)

all_rids = sorted(set(cm) | set(cl))

rows = []
for rid in all_rids:
    c = cm.get(rid, {})
    l = cl.get(rid, {})

    e2e = c.get("cube-e2e")

    vm_boot = (
        l.get("sandbox-binarystart", 0.0)
        + l.get("sandbox-create", 0.0)
        + l.get("sandbox-start", 0.0)
        + l.get("sandbox-wait", 0.0)
    )
    probe = l.get("sandbox-probe", 0.0)
    if not probe and c.get("sandbox-probe") is not None:
        probe = c.get("sandbox-probe", 0.0)
    vm_ready = vm_boot + probe
    inner = l.get("cubebox-service-inner")
    queue_or_master = (e2e - vm_ready) if (e2e is not None and vm_ready > 0) else None

    rows.append({
        "request_id": rid,
        "retcode": c.get("retcode", l.get("retcode", 0)),
        "cube_e2e_ms": e2e,
        "cubebox_service_inner_ms": inner,
        "queue_or_master_overhead_ms": queue_or_master,
        "network_ms": l.get("network"),
        "storage_ms": l.get("storage"),
        "sandbox_binarystart_ms": l.get("sandbox-binarystart"),
        "sandbox_create_ms": l.get("sandbox-create"),
        "sandbox_start_ms": l.get("sandbox-start"),
        "sandbox_wait_ms": l.get("sandbox-wait"),
        "sandbox_probe_ms": l.get("sandbox-probe"),
        "vm_boot_ms": vm_boot if vm_boot > 0 else None,
        "vm_ready_ms": vm_ready if vm_ready > 0 else None,
    })

with per_req_csv.open("w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()) if rows else [
        "request_id","retcode","cube_e2e_ms","cubebox_service_inner_ms","queue_or_master_overhead_ms",
        "network_ms","storage_ms","sandbox_binarystart_ms",
        "sandbox_create_ms","sandbox_start_ms","sandbox_wait_ms","sandbox_probe_ms",
        "vm_boot_ms","vm_ready_ms"
    ])
    writer.writeheader()
    writer.writerows(rows)


def pct(vals, p):
    if not vals:
        return None
    vals = sorted(vals)
    k = max(0, min(len(vals)-1, math.ceil(len(vals)*p/100)-1))
    return vals[k]

def summarize(vals):
    if not vals:
        return "count=0"
    return (
        f"count={len(vals)} avg={statistics.fmean(vals):.3f}ms "
        f"p50={pct(vals,50):.3f} p95={pct(vals,95):.3f} "
        f"p99={pct(vals,99):.3f} max={max(vals):.3f}"
    )

cube_e2e = [r["cube_e2e_ms"] for r in rows if isinstance(r["cube_e2e_ms"], (int,float))]
inner = [r["cubebox_service_inner_ms"] for r in rows if isinstance(r["cubebox_service_inner_ms"], (int,float))]
queue_or_master = [r["queue_or_master_overhead_ms"] for r in rows if isinstance(r["queue_or_master_overhead_ms"], (int,float))]
vm_boot = [r["vm_boot_ms"] for r in rows if isinstance(r["vm_boot_ms"], (int,float))]
vm_ready = [r["vm_ready_ms"] for r in rows if isinstance(r["vm_ready_ms"], (int,float))]
probe = [r["sandbox_probe_ms"] for r in rows if isinstance(r["sandbox_probe_ms"], (int,float))]

bench = {}
if json_path.exists():
    bench = json.loads(json_path.read_text())

lines = []
lines.append("Create-latency segmented analysis")
lines.append(f"run_dir={run_dir}")
if bench:
    lines.append(f"bench_config={bench.get('config',{})}")
    lines.append(f"bench_summary={bench.get('summary',{})}")
    lines.append(f"bench_create_stats={bench.get('create',{})}")
lines.append("")
lines.append("[CubeMaster]")
lines.append("cube-e2e: " + summarize(cube_e2e))
lines.append("queue_or_master_overhead (cube-e2e - vm_ready): " + summarize(queue_or_master))
lines.append("")
lines.append("[Cubelet VM-stage]")
lines.append("cubebox_service_inner_ms: " + summarize(inner))
lines.append("vm_boot_ms (binarystart+create+start+wait): " + summarize(vm_boot))
lines.append("probe_ms (sandbox-probe): " + summarize(probe))
lines.append("vm_ready_ms (vm_boot + probe): " + summarize(vm_ready))

summary_txt.write_text("\n".join(lines) + "\n")
print(summary_txt)
print(per_req_csv)
PY

echo "analysis completed: ${RUN_DIR}"
echo "summary: ${RUN_DIR}/create_segment_summary.txt"
echo "per-request csv: ${RUN_DIR}/create_segment_breakdown_per_request.csv"
if [[ ${BENCH_RC} -ne 0 ]]; then
    echo "warning: cube-bench exited with code ${BENCH_RC}" >&2
fi
