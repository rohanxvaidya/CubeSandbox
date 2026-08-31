#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# analyze_create_latency_v2.sh
#
# CubeSandbox create latency staged breakdown (v2).
#
# What it does
#   Runs cube-bench (or, with --no-run, just analyzes the most recent log tail)
#   and produces a correct, source-grounded per-STAGE latency breakdown of the
#   sandbox create path, aggregated statistically (p50/p90/p95/p99/max/mean).
#
# Why v2 (vs analyze_cubesandbox_create_latency.sh)
#   The create path spans:  cube-bench(client) -> CubeAPI -> CubeMaster -> Cubelet
#   Two data sources are actually available on this host:
#     1) CubeMaster: /data/log/CubeMaster/cubemaster-req.log
#          LogContent string "CreateSandbox_rsp:{json}"      (success, CodeLine :134)
#                    or       "CreateSandbox_rsp fail:{json}" (failure, CodeLine :132)
#          embedded ext_info = { cube-e2e, sandbox-probe, all-probe }, plus sandbox_id.
#          => cube-e2e is the authoritative server-measured end-to-end create time.
#     2) Cubelet:   /data/log/Cubelet/Cubelet-stat.log
#          Action=="Create" trace lines, one per stage:
#            { RequestId, Callee=<stage>, CostTime=<ms> }
#
#   Key correctness facts baked into this script (verified against source):
#     * CubeMaster per-stage traces (cubemaster-inner / schedule / post-redis /
#       post-spec) are NOT persisted: only Cubelet enables trace output. So the
#       master side only yields cube-e2e + probe, nothing finer.
#     * There is NO reliable per-request join between master and cubelet
#       (different RequestId spaces; Cubelet InstanceID is null). Therefore both
#       sides are aggregated independently and compared via percentiles over the
#       same run window.
#     * Workflow actions within a step run in PARALLEL (errgroup). Create steps:
#         [createid, appsnapshot]
#         [images, volume, storage, network, netfile, cube-sandbox-store]  <- PARALLEL
#         [cgroup]
#         [cubebox]  (internally: shim boot binarystart->create->start->wait, then probe)
#       => I/O-group stage CostTimes OVERLAP and MUST NOT be summed; wall-time of
#          that step ~= max(actions). This script labels stages parallel/seq and
#          never sums overlapping stages into a fake total.
#     * Cubelet trace skips successful metrics < 5ms, so a missing stage
#       (e.g. sandbox-binarystart/sandbox-wait) means "fast", not "absent".
#
# Usage
#   ./analyze_create_latency_v2.sh                 # run cube-bench then analyze
#   CONCURRENCY=50 TOTAL=200 ./analyze_create_latency_v2.sh
#   ./analyze_create_latency_v2.sh --no-run        # analyze recent log tail only
#   TAIL_LINES=200000 ./analyze_create_latency_v2.sh --no-run
#
# Env knobs (with defaults):
#   E2B_API_URL, E2B_API_KEY, CUBE_TEMPLATE_ID, BENCH_DIR,
#   CONCURRENCY, TOTAL, WARMUP, MODE, TAIL_LINES
# =============================================================================

NO_RUN=0
for arg in "$@"; do
  case "$arg" in
    --no-run) NO_RUN=1 ;;
    -h|--help) sed -n '2,60p' "$0"; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

E2B_API_URL="${E2B_API_URL:-http://127.0.0.1:3000}"
E2B_API_KEY="${E2B_API_KEY:-e2b_000000}"
# NOTE: use a template that actually exists on this host. tpl-b440... produced
# 100% CreateSandbox_rsp fail. tpl-39f4... is a known-good smoke template.
CUBE_TEMPLATE_ID="${CUBE_TEMPLATE_ID:-tpl-39f484e6780c4d60b4ca18fc}"

BENCH_DIR="${BENCH_DIR:-/home/mz/cubeSandbox/CubeSandbox/examples/cube-bench}"
CONCURRENCY="${CONCURRENCY:-20}"
TOTAL="${TOTAL:-100}"
WARMUP="${WARMUP:-3}"
MODE="${MODE:-create-delete}"
OUT_JSON="${OUT_JSON:-/tmp/cube_v2.json}"
# For --no-run: how many trailing lines of each log to analyze.
TAIL_LINES="${TAIL_LINES:-200000}"

CM_LOG="/data/log/CubeMaster/cubemaster-req.log"
CL_STAT_LOG="/data/log/Cubelet/Cubelet-stat.log"

TS="$(date +%Y%m%d_%H%M%S)"
ANALYSIS_ROOT="/home/mz/cubeSandbox/benchmark_analysis"
if [[ "$NO_RUN" -eq 1 ]]; then
  RUN_DIR="${ANALYSIS_ROOT}/${TS}_norun_tail${TAIL_LINES}"
else
  RUN_DIR="${ANALYSIS_ROOT}/${TS}_c${CONCURRENCY}_n${TOTAL}_${MODE}_v2"
fi
mkdir -p "${RUN_DIR}"

for f in "$CM_LOG" "$CL_STAT_LOG"; do
  [[ -f "$f" ]] || { echo "missing log file: $f" >&2; exit 1; }
done

START_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [[ "$NO_RUN" -eq 1 ]]; then
  echo "[v2] --no-run: analyzing last ${TAIL_LINES} lines of each log"
  tail -n "$TAIL_LINES" "$CM_LOG"      > "${RUN_DIR}/cubemaster.delta.log"
  tail -n "$TAIL_LINES" "$CL_STAT_LOG" > "${RUN_DIR}/cubelet.stat.delta.log"
  BENCH_RC="n/a"
else
  CM_OFFSET="$(stat -c %s "$CM_LOG")"
  CL_STAT_OFFSET="$(stat -c %s "$CL_STAT_LOG")"

  echo "[v2] running cube-bench c=${CONCURRENCY} n=${TOTAL} w=${WARMUP} mode=${MODE}"
  pushd "$BENCH_DIR" >/dev/null
  set +e
  E2B_API_URL="$E2B_API_URL" \
  E2B_API_KEY="$E2B_API_KEY" \
  CUBE_TEMPLATE_ID="$CUBE_TEMPLATE_ID" \
  ./bin/cube-bench -c "$CONCURRENCY" -n "$TOTAL" -w "$WARMUP" -m "$MODE" -o "$OUT_JSON"
  BENCH_RC=$?
  set -e
  popd >/dev/null

  [[ -f "$OUT_JSON" ]] && cp "$OUT_JSON" "${RUN_DIR}/cube.json"

  # Only the log bytes appended during this run.
  tail -c +$((CM_OFFSET + 1))      "$CM_LOG"      > "${RUN_DIR}/cubemaster.delta.log"
  tail -c +$((CL_STAT_OFFSET + 1)) "$CL_STAT_LOG" > "${RUN_DIR}/cubelet.stat.delta.log"
fi

END_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat > "${RUN_DIR}/run_context.env" <<EOF
MODE_RUN=$([[ "$NO_RUN" -eq 1 ]] && echo no-run || echo bench)
E2B_API_URL=${E2B_API_URL}
E2B_API_KEY=${E2B_API_KEY}
CUBE_TEMPLATE_ID=${CUBE_TEMPLATE_ID}
BENCH_DIR=${BENCH_DIR}
CONCURRENCY=${CONCURRENCY}
TOTAL=${TOTAL}
WARMUP=${WARMUP}
MODE=${MODE}
TAIL_LINES=${TAIL_LINES}
CM_LOG=${CM_LOG}
CL_STAT_LOG=${CL_STAT_LOG}
START_UTC=${START_UTC}
END_UTC=${END_UTC}
BENCH_RC=${BENCH_RC}
EOF

# --------------------------------------------------------------------------
# Extract CubeMaster create records (success + failure) -> TSV
#   columns: status \t retcode \t sandbox_id \t cube_e2e_ms \t sandbox_probe_ms \t all_probe_ms
# The LogContent is a string beginning "CreateSandbox_rsp:" or "CreateSandbox_rsp fail:".
# --------------------------------------------------------------------------
CM_TSV="${RUN_DIR}/cubemaster_create.tsv"
grep -a 'CreateSandbox_rsp' "${RUN_DIR}/cubemaster.delta.log" \
| jq -rc '
    . as $rec
    | ($rec.LogContent // "") as $lc
    | if ($lc | test("CreateSandbox_rsp")) then
        (if ($lc | test("CreateSandbox_rsp fail")) then "fail" else "ok" end) as $status
        | ($lc | sub("^CreateSandbox_rsp( fail)?:"; "")) as $body
        | ( try ($body | fromjson) catch null ) as $j
        | if $j == null then empty else
            [ $status,
              ($rec.RetCode // ""),
              ($j.sandbox_id // ""),
              ($j.ext_info["cube-e2e"] // ""),
              ($j.ext_info["sandbox-probe"] // ""),
              ($j.ext_info["all-probe"] // "")
            ] | @tsv
          end
      else empty end
  ' 2>/dev/null > "$CM_TSV" || true

# --------------------------------------------------------------------------
# Extract Cubelet create stage traces -> TSV
#   columns: request_id \t stage \t cost_ms \t retcode
# --------------------------------------------------------------------------
CL_TSV="${RUN_DIR}/cubelet_create_stages.tsv"
grep -a '"Action":"Create"' "${RUN_DIR}/cubelet.stat.delta.log" \
| jq -rc 'select(.Action=="Create")
    | [ (.RequestId // ""), (.Callee // ""), (.CostTime // ""), (.RetCode // "") ]
    | @tsv' 2>/dev/null > "$CL_TSV" || true

# --------------------------------------------------------------------------
# Aggregate + report
# --------------------------------------------------------------------------
SUMMARY="${RUN_DIR}/create_latency_v2_summary.txt"
PERREQ_CSV="${RUN_DIR}/cubelet_per_request.csv"

python3 - "$CM_TSV" "$CL_TSV" "$SUMMARY" "$PERREQ_CSV" "${RUN_DIR}/cube.json" <<'PY'
import sys, os, json, csv

cm_tsv, cl_tsv, summary_path, perreq_csv, bench_json = sys.argv[1:6]

def pct(sorted_vals, p):
    if not sorted_vals:
        return None
    if len(sorted_vals) == 1:
        return sorted_vals[0]
    k = (len(sorted_vals) - 1) * (p / 100.0)
    lo = int(k); hi = min(lo + 1, len(sorted_vals) - 1)
    return sorted_vals[lo] + (sorted_vals[hi] - sorted_vals[lo]) * (k - lo)

def stats(vals):
    v = sorted(x for x in vals if x is not None)
    if not v:
        return None
    return {
        "n": len(v),
        "mean": sum(v) / len(v),
        "p50": pct(v, 50), "p90": pct(v, 90),
        "p95": pct(v, 95), "p99": pct(v, 99),
        "max": v[-1], "min": v[0],
    }

def fnum(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None

# ---- CubeMaster side ----
cm_e2e_ok, cm_e2e_all, cm_probe = [], [], []
cm_ok = cm_fail = 0
if os.path.exists(cm_tsv):
    with open(cm_tsv) as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 6:
                continue
            status, ret, sid, e2e, sprobe, aprobe = parts[:6]
            e2e = fnum(e2e); sprobe = fnum(sprobe)
            if status == "ok":
                cm_ok += 1
                if e2e is not None: cm_e2e_ok.append(e2e)
            else:
                cm_fail += 1
            if e2e is not None: cm_e2e_all.append(e2e)
            if sprobe is not None: cm_probe.append(sprobe)

# ---- Cubelet side ----
# Per-request stage map: request_id -> { stage: cost_ms }
req_stages = {}
stage_vals = {}   # stage -> [cost...]
if os.path.exists(cl_tsv):
    with open(cl_tsv) as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3:
                continue
            rid, stage, cost = parts[0], parts[1], fnum(parts[2])
            if not stage or cost is None:
                continue
            req_stages.setdefault(rid, {})[stage] = cost
            stage_vals.setdefault(stage, []).append(cost)

num_cl_reqs = len(req_stages)

# Ordered/annotated stage taxonomy (label, kind).
#   TOTAL  = wall-clock parent
#   PARALLEL = runs concurrently with siblings in same step; DO NOT SUM
#   SEQ    = sequential sub-phase; summable within its own group
STAGE_ORDER = [
    ("cubebox-service",        "TOTAL   (cubelet gRPC Create handler total)"),
    ("cubebox-service-inner",  "derived (service - probe - volume)"),
    ("create-sandbox-metadata","SEQ     (step1: build sandbox metadata)"),
    ("images",                 "PARALLEL(step2 io-group)"),
    ("volume",                 "PARALLEL(step2 io-group)"),
    ("storage",                "PARALLEL(step2 io-group)"),
    ("network",                "PARALLEL(step2 io-group)"),
    ("netfile",                "PARALLEL(step2 io-group)"),
    ("cube-sandbox-store",     "PARALLEL(step2 io-group)"),
    ("cgroup",                 "SEQ     (step3)"),
    ("cubebox",                "TOTAL   (step4 engine create total)"),
    ("cubebox-inner",          "derived (cubebox - shim stages)"),
    ("gen-spec",               "SEQ     (container spec gen)"),
    ("sandbox-binarystart",    "shim    (launch VMM binary; <5ms often hidden)"),
    ("sandbox-create",         "shim    (create VM; may overlap sandbox-start)"),
    ("sandbox-start",          "shim    (start VM; may overlap sandbox-create)"),
    ("sandbox-wait",           "shim    (wait VM ready; <5ms often hidden)"),
    ("sandbox-probe",          "SEQ     (guest agent readiness probe)"),
]
IO_GROUP = ["images", "volume", "storage", "network", "netfile", "cube-sandbox-store"]
SHIM_SEQ = ["sandbox-binarystart", "sandbox-create", "sandbox-start", "sandbox-wait"]

# Per-request derived metrics (only where the parent stage exists).
io_wall, shim_boot, cubebox_service_list = [], [], []
for rid, sm in req_stages.items():
    ios = [sm[s] for s in IO_GROUP if s in sm]
    if ios:
        io_wall.append(max(ios))
    shim = [sm[s] for s in SHIM_SEQ if s in sm]
    if shim:
        shim_boot.append(sum(shim))
    if "cubebox-service" in sm:
        cubebox_service_list.append(sm["cubebox-service"])

# Any stage seen but not in taxonomy -> append so nothing is silently dropped.
known = {s for s, _ in STAGE_ORDER}
extra = sorted(s for s in stage_vals if s not in known)
for s in extra:
    STAGE_ORDER.append((s, "(unclassified)"))

# ---- bench client-side (optional) ----
bench = None
if os.path.exists(bench_json):
    try:
        with open(bench_json) as f:
            bench = json.load(f)
    except Exception:
        bench = None

# ---- write per-request CSV ----
csv_stages = [s for s, _ in STAGE_ORDER if s in stage_vals]
with open(perreq_csv, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["request_id"] + csv_stages + ["io_group_walltime", "shim_boot_sum"])
    for rid, sm in req_stages.items():
        row = [rid] + [("%.3f" % sm[s]) if s in sm else "" for s in csv_stages]
        ios = [sm[s] for s in IO_GROUP if s in sm]
        shim = [sm[s] for s in SHIM_SEQ if s in sm]
        row.append("%.3f" % max(ios) if ios else "")
        row.append("%.3f" % sum(shim) if shim else "")
        w.writerow(row)

# ---- render summary ----
def fmt(st):
    if not st:
        return "   (no data)"
    return ("n=%-5d mean=%8.2f p50=%8.2f p90=%8.2f p95=%8.2f p99=%8.2f max=%9.2f"
            % (st["n"], st["mean"], st["p50"], st["p90"], st["p95"], st["p99"], st["max"]))

lines = []
def out(s=""):
    lines.append(s)

out("=" * 100)
out("CubeSandbox CREATE latency — staged breakdown (v2)   [all times in ms]")
out("=" * 100)
out("")
out("Pipeline: cube-bench(client) -> CubeAPI -> CubeMaster -> Cubelet(workflow: metadata|io|cgroup|cubebox)")
out("Two independent data sources (NO per-request join available):")
out("  * CubeMaster cube-e2e = authoritative server end-to-end create time")
out("  * Cubelet-stat per-stage traces = node-side create stage costs")
out("Percentiles align statistically across the same run window.")
out("")

# --- Section A: client (cube-bench) ---
out("-" * 100)
out("A) CLIENT-SIDE (cube-bench HTTP create latency, includes CubeAPI + network)")
out("-" * 100)
if bench:
    cfg = bench.get("config", {}) or {}
    summ = bench.get("summary", {}) or {}
    cre = bench.get("create", {}) or {}
    out("  config : c=%s n=%s mode=%s template=%s"
        % (cfg.get("concurrency"), cfg.get("total"), cfg.get("mode"), cfg.get("template")))
    out("  summary: ok=%s fail=%s success_rate=%s qps=%s"
        % (summ.get("successful"), summ.get("errors"),
           summ.get("success_rate"), summ.get("throughput_qps")))
    if cre:
        def g(k):
            v = cre.get(k)
            return ("%.2f" % v) if isinstance(v, (int, float)) else str(v)
        out("  createMs: n=%s avg=%s p50=%s p90=%s p95=%s p99=%s max=%s"
            % (g("count"), g("avg"), g("p50"), g("p90"), g("p95"), g("p99"), g("max")))
    else:
        out("  createMs: (no successful creates in this run)")
else:
    out("  (no cube.json — run without --no-run to capture client-side stats)")
out("")

# --- Section B: master ---
out("-" * 100)
out("B) CUBEMASTER (server end-to-end)   records: ok=%d fail=%d" % (cm_ok, cm_fail))
out("-" * 100)
out("  cube-e2e (success only) : %s" % fmt(stats(cm_e2e_ok)))
out("  cube-e2e (incl. failed) : %s" % fmt(stats(cm_e2e_all)))
out("  sandbox-probe (master)  : %s" % fmt(stats(cm_probe)))
out("")

# --- Section C: cubelet per-stage ---
out("-" * 100)
out("C) CUBELET per-stage   (distinct create requests seen: %d)" % num_cl_reqs)
out("   NOTE: PARALLEL stages OVERLAP — do NOT sum them. Missing stage => <5ms (trace-suppressed).")
out("-" * 100)
out("   %-24s %-42s %s" % ("stage", "kind", "stats"))
for stage, kind in STAGE_ORDER:
    if stage not in stage_vals:
        continue
    cov = len(stage_vals[stage])
    covpct = (100.0 * cov / num_cl_reqs) if num_cl_reqs else 0.0
    out("   %-24s %-42s %s  cov=%.0f%%"
        % (stage, kind, fmt(stats(stage_vals[stage])), covpct))
out("")

# --- Section D: derived phases ---
out("-" * 100)
out("D) DERIVED create phases (per-request, correctly handling parallelism)")
out("-" * 100)
out("  io_group wall-time = max(images,volume,storage,network,netfile,cube-sandbox-store)")
out("     %s" % fmt(stats(io_wall)))
out("  shim_boot(sum)     = binarystart+create+start+wait  (UPPER BOUND: shim timers overlap)")
out("     %s" % fmt(stats(shim_boot)))
out("  NOTE: 'cubebox' TOTAL is the authoritative VM-boot wall-time; shim_boot sum")
out("        can exceed it because sandbox-create/start spans overlap.")
out("")

# --- Section E: cross-tier overhead (percentile-aligned) ---
out("-" * 100)
out("E) CROSS-TIER overhead (percentile-aligned; not per-request)")
out("-" * 100)
e2e = stats(cm_e2e_ok)
svc = stats(cubebox_service_list)
if e2e and svc:
    out("  cube-e2e            : p50=%8.2f p95=%8.2f p99=%8.2f" % (e2e["p50"], e2e["p95"], e2e["p99"]))
    out("  cubebox-service     : p50=%8.2f p95=%8.2f p99=%8.2f" % (svc["p50"], svc["p95"], svc["p99"]))
    out("  master+net overhead : p50=%8.2f p95=%8.2f p99=%8.2f   (cube-e2e - cubebox-service)"
        % (e2e["p50"] - svc["p50"], e2e["p95"] - svc["p95"], e2e["p99"] - svc["p99"]))
    out("  NOTE: overhead = CubeMaster scheduling/queue + gRPC + master<->cubelet network.")
else:
    out("  (insufficient overlapping data for master vs cubelet comparison)")
out("")
out("=" * 100)
out("Artifacts in this run directory:")
out("  create_latency_v2_summary.txt   (this report)")
out("  cubelet_per_request.csv         (per-request stage costs + derived phases)")
out("  cubemaster_create.tsv           (raw master ok/fail + cube-e2e/probe)")
out("  cubelet_create_stages.tsv       (raw cubelet stage traces)")
out("  cubemaster.delta.log / cubelet.stat.delta.log / run_context.env / cube.json")
out("=" * 100)

report = "\n".join(lines) + "\n"
with open(summary_path, "w") as f:
    f.write(report)
print(report)
PY

echo ""
echo "[v2] done -> ${RUN_DIR}"
