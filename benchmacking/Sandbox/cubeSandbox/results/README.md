# CWF CubeSandbox `create-delete` Sweep Results

Summary artifacts (CSV + latency plot + `sweep.log`) for the CWF CubeSandbox
`cube-bench` create-delete concurrency sweeps. Per-concurrency raw JSON reports
are intentionally excluded to keep the repo lean.

Each sweep steps concurrency `c` from 100 to 350 (requests `n = 10 x c`),
measuring create/delete latency, throughput, and success rate.

## Headline: ~318 concurrency at 200 ms create latency

The **~318 concurrency @ 200 ms** operating point comes from sweep
[`cwf-sweep-createdelete-20260827-174207`](cwf-sweep-createdelete-20260827-174207/cwf_sweep_createdelete.csv):

| concurrency | create_avg_ms | create_p50_ms | delete_avg_ms | throughput_sb_s | success% |
|---:|---:|---:|---:|---:|---:|
| 310 | 193.5 | 192.5 | 189.7 | 688.0 | 100 |
| 320 | 201.3 | 200.6 | 196.2 | 686.2 | 100 |

Linear interpolation of `create_avg_ms = 200 ms` lands at **~c318**
(create_p50 -> ~c319, delete_avg -> ~c322), all at 100% success / 0 errors.

## Concurrency at 200 ms create latency, per sweep

Interpolated concurrency where the metric crosses 200 ms:

| sweep | create_avg | create_p50 | delete_avg |
|---|---:|---:|---:|
| cwf-sweep-createdelete-20260827-174207 | **318** | 319 | 322 |
| cwf-sweep-createdelete-20260827-155532 | 317 | 307 | 305 |
| cwf-sweep-createdelete-20260827-202447 | 317 | 315 | 314 |
| cwf-sweep-createdelete-20260827-175853 | 315 | 313 | 297 |
| cwf-sweep-createdelete-20260827-203600 | 314 | 308 | 290 |
| cwf-e2e-repo-latency-sweep-20260830-184645 | 309 | 308 | 305 |
| cwf-sweep-createdelete-20260827-143535 | 307 | 307 | 318 |
| cwf-sweep-createdelete-20260827-153946 | 305 | 304 | 306 |
| cwf-e2e-repo-latency-sweep-20260830-182737 | 296 | 310 | 294 |
| cwf-sweep-createdelete-20260825-121131 | 231 | 236 | 188 |

## Files per sweep

- `cwf_sweep_createdelete.csv` (or `cwf1_sweep_createdelete.csv`) — per-concurrency summary
- `cwf_create_latency_vs_concurrency.png` — create latency vs concurrency plot
- `sweep.log` — run log
