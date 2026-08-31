# NIC Benchmark Master Index

## Purpose

This is the single entry point for the NIC cross-cache optimization workstream.
Use this page to navigate workload setup, driver changes, and emon-based validation.

## Primary Docs

1. Workload and runbook:
   - [NIC_workload.md](NIC_workload.md)
2. EMON method and interpretation:
   - [NIC_emon_analysis.md](NIC_emon_analysis.md)
3. Driver modification and optimization notes:
   - [NIC_driver_optimization.md](NIC_driver_optimization.md)

## Legacy Compatibility Docs

- [NIC_workload_Benchmark.md](NIC_workload_Benchmark.md)
- [NIC_croass_cache_emon_data_analys.md](NIC_croass_cache_emon_data_analys.md)

## Experiment Timeline And Key Outputs

### Phase A: Baseline and reusable analysis setup

- Workflow and hotspot method:
  - [NIC_emon_analysis.md](NIC_emon_analysis.md)
- Initial hotspot outputs:
  - [emon_hitm_hotspot_analysis_rerun.md](emon_hitm_hotspot_analysis_rerun.md)
  - [effective_range_two_part_analysis.md](effective_range_two_part_analysis.md)

### Phase B: Loaded module comparison

- Comparison report:
  - [emon_hitm_after_patch_loaded_compare.md](emon_hitm_after_patch_loaded_compare.md)
- Generated data:
  - [emon_hitm_per_core_stats_after_patch_loaded.csv](emon_hitm_per_core_stats_after_patch_loaded.csv)

### Phase C: Force comp vector to node1 experiment

- Main reports:
  - [emon_hitm_compvec_force1_compare.md](emon_hitm_compvec_force1_compare.md)
  - [emon_hitm_compvec_force1_global_compare.md](emon_hitm_compvec_force1_global_compare.md)
- Visuals:
  - [emon_hitm_compvec_force1_vs_prev_key_metrics.png](emon_hitm_compvec_force1_vs_prev_key_metrics.png)
  - [emon_hitm_compvec_force1_vs_prev_share.png](emon_hitm_compvec_force1_vs_prev_share.png)
  - [emon_hitm_compvec_force1_vs_prev_curve_40_79.png](emon_hitm_compvec_force1_vs_prev_curve_40_79.png)
  - [emon_hitm_compvec_force1_vs_prev_all_cores_line.png](emon_hitm_compvec_force1_vs_prev_all_cores_line.png)
  - [emon_hitm_compvec_force1_vs_prev_all_cores_delta.png](emon_hitm_compvec_force1_vs_prev_all_cores_delta.png)
  - [emon_hitm_compvec_force1_vs_prev_all_cores_tripanel.png](emon_hitm_compvec_force1_vs_prev_all_cores_tripanel.png)
  - [emon_hitm_prev_loaded_heatmap_all_cores.png](emon_hitm_prev_loaded_heatmap_all_cores.png)
  - [emon_hitm_force1_heatmap_all_cores.png](emon_hitm_force1_heatmap_all_cores.png)

### Phase D: Manual reload + sw_numa_node=1 three-way compare

- Main report:
  - [emon_hitm_manual_reload_swnuma1_compare.md](emon_hitm_manual_reload_swnuma1_compare.md)
- Visuals:
  - [emon_hitm_threeway_all_cores_line.png](emon_hitm_threeway_all_cores_line.png)
  - [emon_hitm_manual_vs_loaded2_delta_all_cores.png](emon_hitm_manual_vs_loaded2_delta_all_cores.png)
  - [emon_hitm_threeway_effective_40_79.png](emon_hitm_threeway_effective_40_79.png)
- Data:
  - [emon_hitm_per_core_stats_after_manual_reload_swnuma1.csv](emon_hitm_per_core_stats_after_manual_reload_swnuma1.csv)

## Current Decision Context

- Hard forcing completion vector CPU to NUMA1 is useful as a stress experiment, but tends to increase HITM.
- Runtime sw_numa_node path is preferred as the default optimization direction.
- Every driver change should be validated with the same workload window and same emon method.

## Suggested Repeatable Validation Loop

1. Apply driver change.
2. Build and reload mlx5 modules.
3. Reconfigure NIC and set sw_numa_node and link down/up NIC device to let the sw_numa_node take effort.
4. Run stable redis benchmark workload.
5. Capture emon with fixed policy.
6. Compare against the latest accepted baseline with all-core and effective-range views.
