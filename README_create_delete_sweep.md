# CubeSandbox create-delete concurrency sweep — run README

Exact, reproducible steps for the create-delete latency/throughput sweep used to
compare CubeSandbox on CWF (Intel) and Turin (AMD) hosts.

The workload drives the CubeAPI **E2B** endpoint with `cube-bench` in
`create-delete` mode, sweeping concurrency `c = 100..350` (step 10), with
`n = c*10` operations per point. Each point is isolated (leftover sandboxes
deleted, page cache dropped) so points do not contaminate each other.

---

## 1. Prerequisites

Bring up / verify the control plane and a READY template before benchmarking.

```bash
# Control plane must be up (6 containers: proxy, proxy-coredns, egress,
# mysql, redis, webui). egress is kept ON for these runs (in-path, idle on
# the create-delete data path).
systemctl status cube-sandbox-control.target
docker ps --format '{{.Names}}'         # expect the 6 control-plane containers

# A template must exist and be READY. Record its ID for CUBE_TEMPLATE_ID.
cubemastercli tpl list                  # status must be READY

# Build the benchmark binary (Go).
cd <path>/CubeSandbox/examples/cube-bench && make
ls bin/cube-bench
```

Key facts held constant across all runs:

| Setting | Value |
| --- | --- |
| API endpoint | `http://127.0.0.1:3000` |
| API key | `e2b_000000` |
| Mode | `create-delete` (each op = create a sandbox, then delete that same sandbox) |
| Warmup | `-w 3` (3 cycles per point, not measured) |
| Concurrency sweep | `c = 100, 110, … 350` |
| Ops per point | `n = c * 10` |
| CPU governor | `performance` |
| Per-point isolation | delete leftovers → `sync` → `drop_caches` → run → cleanup → sleep |
| Egress | ON (`cube-egress` container up) |

---

## 2. Environment variables

```bash
export E2B_API_URL="http://127.0.0.1:3000"
export E2B_API_KEY="e2b_000000"
export CUBE_TEMPLATE_ID="<READY template id, e.g. tpl-cea9de24f21d4d4fac319a15>"
```

---

## 3. Run the full sweep (automated wrapper)

> For the default/manual per-point method, see **§3b** below. This section is the
> automated wrapper that runs the entire c=100..350 sweep unattended.

The canonical driver is `cwf-sweep-createdelete.sh`. Its exact loop:

```bash
#!/usr/bin/env bash
set -euo pipefail

export E2B_API_URL=${E2B_API_URL:-http://127.0.0.1:3000}
export E2B_API_KEY=${E2B_API_KEY:-e2b_000000}
TID=${CUBE_TEMPLATE_ID:-tpl-cea9de24f21d4d4fac319a15}
BENCH=<path>/CubeSandbox/examples/cube-bench/bin/cube-bench
OUT=/data/cwf-sweep-createdelete-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"; echo "OUT=$OUT"

# delete every sandbox currently registered (per-point isolation)
cleanup(){
  local tries=0
  while :; do
    ids=$(curl -s -H "X-API-Key: $E2B_API_KEY" "$E2B_API_URL/sandboxes" \
      | python3 -c 'import sys,json;[print(x["sandboxID"]) for x in json.load(sys.stdin)]')
    [ -z "$ids" ] && break
    for i in $ids; do
      curl -s -o /dev/null -X DELETE -H "X-API-Key: $E2B_API_KEY" \
        "$E2B_API_URL/sandboxes/$i" || true
    done
    tries=$((tries+1)); [ "$tries" -gt 240 ] && break; sleep 1
  done
}

cpupower -c all frequency-set -g performance >/dev/null 2>&1 || true

for c in $(seq 100 10 350); do
  n=$((c*10))
  cleanup; sync; echo 3 > /proc/sys/vm/drop_caches || true
  "$BENCH" --no-tui -m create-delete -c "$c" -n "$n" -w 3 -t "$TID" \
    --api-url "$E2B_API_URL" --api-key "$E2B_API_KEY" \
    -o "$OUT/c${c}_n${n}.json" > "$OUT/c${c}.log" 2>&1 || true
  cleanup; sleep 4
done
```

Run it (long-running; keep it off the SSH foreground):

```bash
nohup bash cwf-sweep-createdelete.sh > /data/<run-name>.boot.log 2>&1 &
tail -f /data/<run-name>.boot.log     # watch progress
```

Output directory contents per run:
- `c<c>_n<n>.json` — full per-point stats (create + delete blocks with
  avg/p50/p90/p95/p99/min/max/std, plus `raw[]` per-sandbox create_ms/delete_ms).
- `c<c>.log` — cube-bench stdout for that point.
- `sweep.log` — one progress line per point.
- `cwf_sweep_createdelete.csv` — reduced aggregate table (auto-generated at the
  end of the driver).

CSV columns:
```
concurrency, n_total, create_avg_ms, create_p50_ms, create_p95_ms,
create_p99_ms, delete_avg_ms, throughput_sb_s, success_pct, errors
```

> Note: the CSV stores **delete_avg only**. Delete percentiles (p50/p90/p95/p99)
> live in the per-point JSON `delete` block.

---

## 3b. Running manually (DEFAULT method)

**This is the default way we run the workload** — a direct `cube-bench`
invocation per point. The full sweep driver in §3 is the automated wrapper
around this; use it only when you want the whole c=100..350 sweep unattended.

Set up the shell once:

```bash
export E2B_API_URL="http://127.0.0.1:3000"
export E2B_API_KEY="e2b_000000"
export CUBE_TEMPLATE_ID="tpl-cea9de24f21d4d4fac319a15"   # any READY template
BENCH=/root/cube-src/CubeSandbox/examples/cube-bench/bin/cube-bench
```

**Smoke test** — confirm the pipeline with a tiny load first:

```bash
$BENCH --no-tui -m create-delete -c 10 -n 100 -w 3 \
  -t "$CUBE_TEMPLATE_ID" --api-url "$E2B_API_URL" --api-key "$E2B_API_KEY" \
  -o /data/smoke.json && echo OK
```

**Single point** — one concurrency level (e.g. c=200, n=2000), exact sweep flags:

```bash
cpupower -c all frequency-set -g performance      # match run conditions
$BENCH --no-tui -m create-delete -c 200 -n 2000 -w 3 \
  -t "$CUBE_TEMPLATE_ID" \
  --api-url "$E2B_API_URL" --api-key "$E2B_API_KEY" \
  -o /data/manual-c200.json
```

Read the result:

```bash
python3 -c 'import json;d=json.load(open("/data/manual-c200.json"));
print("create avg",round(d["create"]["avg"],1),"ms  p95",round(d["create"]["p95"],1));
print("delete avg",round(d["delete"]["avg"],1),"ms  p95",round(d["delete"]["p95"],1));
print("throughput",round(d["summary"]["throughput_qps"],1),"sb/s  success",d["summary"]["success_rate"])'
```

**Per-point isolation** — do the same cleanup the sweep does between points, so a
manual point is not skewed by leftovers or warm cache:

```bash
for i in $(curl -s -H "X-API-Key: $E2B_API_KEY" "$E2B_API_URL/sandboxes" \
  | python3 -c 'import sys,json;[print(x["sandboxID"]) for x in json.load(sys.stdin)]'); do
  curl -s -o /dev/null -X DELETE -H "X-API-Key: $E2B_API_KEY" "$E2B_API_URL/sandboxes/$i"
done
sync; echo 3 > /proc/sys/vm/drop_caches
```

Flag reference: `-c` = concurrency (in-flight create→delete cycles), `-n` = total
ops (sweep uses `n = c*10`), `-w 3` = warmup cycles excluded from stats,
`-t` = template ID, `-o` = per-point JSON output.

---

## 4. Orchestrator / NUMA variants

The same sweep is repeated under different orchestrator placements. Name the
output dir accordingly so runs stay distinguishable, e.g.:

- `1orch-all4numa`   — single orchestrator spanning all NUMA nodes (baseline).
- `1orch-per-numa`   — orchestrator pinned per NUMA node.
- `+6containers-kept`— control-plane containers kept up during the sweep.
- `+tunedpools`      — tuned worker/DB pools (workers=4, DB 100/25, MySQL max_conn=500).

Concurrency limits in `CubeMaster/conf.yaml`
(`create_concurrent_limit` / `destroy_concurent_limit`) were raised 100 → 500 to
remove the delete-side throttle.

---

## 5. Post-processing (charts + Excel)

Reduce a completed run dir to charts and an Excel workbook.

```bash
# Create-latency chart + full summary workbook (Summary/PerPoint/PerSandbox tabs)
python3 make_summary_xlsx.py            <run_dir>

# Delete-latency chart + delete-focused workbook
python3 make_delete_summary.py          <run_dir>

# Overlay: create vs delete on one axis, marks each 200 ms crossing
python3 make_create_delete_overlay.py   <run_dir>

# Combine multiple runs (e.g. Turin vs CWF) onto one plot
python3 combine_turin_cwf.py
```

Artifacts written into `<run_dir>`:
- `cwf_create_latency_vs_concurrency.png` / `create_latency_vs_concurrency_avg_p95.png`
- `delete_latency_vs_concurrency_avg_p95.png`
- `create_delete_latency_vs_concurrency_overlay.png`
- `per_sandbox_latency.png`
- `<run_dir_basename>_summary.xlsx`, `<run_dir_basename>_delete_summary.xlsx`

---

## 6. How to read the results

- **create-delete cycle**: each op creates a sandbox then immediately deletes that
  same sandbox. `c` = number of these cycles in flight at once (semaphore size);
  create→delete is sequential *within* a cycle, cycles run in parallel.
- **Latency curves (lower is better)**: `create_avg` / `delete_avg` vs `c`. The
  **200 ms crossing** (concurrency where avg latency hits 200 ms) is the headline
  comparison point — a *higher* crossing `c` is better. Delete typically crosses
  first (teardown is the heavier op).
- **Throughput `sb/s` (higher is better)** and **success_pct**: the **knee** is the
  concurrency where success drops below 100% or throughput plateaus.

---

## 7. Reference numbers (context, not a guarantee)

| Run | 200 ms create crossing | 200 ms delete crossing | Peak throughput | Success |
| --- | --- | --- | --- | --- |
| Turin `1orch-per-numa` (egress on) | c≈246 | c≈186 | c350, 572.6 sb/s | 100% to c350 |
| Turin `+6containers-kept` | c≈248 | — | c310, 570.1 sb/s | 100% to c350 |
| Turin `+tunedpools+6c` (latest) | c≈238 | — | c350, 589.0 sb/s | 100% to c350 |
| CWF reference (Intel, `vmlinux-bm`, 1orch-perNUMA) | c≈313 | c≈272 | — | — |

> Caveat: the host kernel active during a given run was **not recorded** in the
> run dirs. Record `uname -r` into each output directory so kernel ↔ run mapping
> is provable in future sweeps.
