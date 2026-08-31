# NIC Cross-Cache EMON Analysis

## Objective

Measure and compare cross-cache contention for NIC workload optimization.
Primary event:

- `OCR.READS_TO_CORE.SNC_CACHE.HITM`

Target: reduce HITM while redis workload runs on NUMA1 with `sw_numa_node=1`.

## Capture Policy

- Interval: 1 second (`-t1`)
- Samples: 20 (`-l20`)
- Mode: `-experimental`
- Before every capture, wait 15 seconds after driver reload or NIC reconfiguration so workload and IRQ placement settle.

If PMU contention reduces sample count, continue analysis with available rows and record row count.

## Environment

```bash
source /opt/intel/sep/sep_vars.sh
```

## Capture Command Template

```bash
cd /home/mz/gnr_nic_perf/260508
EVENT="OCR.READS_TO_CORE.SNC_CACHE.HITM"
TS=$(date +%Y%m%d_%H%M%S)
OUT="emon_capture_${TS}.txt"

# Keep workload stable for 15 seconds before capture.
sleep 15

emon -t1 -l20 -experimental -C "$EVENT" > "$OUT"
awk '/^OCR\.READS_TO_CORE\.SNC_CACHE\.HITM/ {c++} END{print "rows=" c+0}' "$OUT"
```

## Analysis Method

1. Parse all event rows and extract per-core values.
2. Compute per-core `mean`, `max`, `std`.
3. Plot full-core view and effective-range view.
4. Detect hotspot cores via percentiles (`p95`, `p99`).
5. Build contiguous ranges from hotspot IDs.
6. For key range `40-79`, split into two segments by maximizing front/back mean ratio.

## Standard Outputs

- Per-core matrix CSV.
- Per-core stats CSV.
- Full-core comparison chart.
- Effective-range chart.
- Global delta chart.
- Hotspot report markdown.

## NUMA Mapping Requirement

Always map hotspot cores to NUMA domains before conclusion:

```bash
lscpu | grep -E 'NUMA node[0-9] CPU\(s\)'
for n in /sys/devices/system/node/node*; do
  echo -n "$(basename $n): "
  cat $n/cpulist
done
```

Current mapping:

- node0: `0-39,120-159`
- node1: `40-79,160-199`
- node2: `80-119,200-239`

## Latest Three-Way Comparison Baseline

Reference report:

- [emon_hitm_manual_reload_swnuma1_compare.md](emon_hitm_manual_reload_swnuma1_compare.md)

Key numbers:

- Effective total (40-79):
  - loaded2: 16,785,236.25
  - force1: 22,793,006.15
  - manual `sw_numa_node=1`: 19,121,245.75
- Global total (all cores):
  - loaded2: 22,408,148.35
  - force1: 34,161,821.70
  - manual `sw_numa_node=1`: 25,775,818.95

## Visualization References

- [emon_hitm_threeway_all_cores_line.png](emon_hitm_threeway_all_cores_line.png)
- [emon_hitm_manual_vs_loaded2_delta_all_cores.png](emon_hitm_manual_vs_loaded2_delta_all_cores.png)
- [emon_hitm_threeway_effective_40_79.png](emon_hitm_threeway_effective_40_79.png)
- [emon_hitm_compvec_force1_vs_prev_all_cores_tripanel.png](emon_hitm_compvec_force1_vs_prev_all_cores_tripanel.png)

## Related Docs

- Workload setup: [NIC_workload.md](NIC_workload.md)
- Driver changes and optimization: [NIC_driver_optimization.md](NIC_driver_optimization.md)
