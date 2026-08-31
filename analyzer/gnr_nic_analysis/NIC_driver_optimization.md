# NIC Driver Modifications And Optimization Notes

## Objective

Optimize mlx5 behavior for redis workload pinned to NUMA1, so cross-cache HITM decreases under stable traffic.

## Optimization Focus

1. Make software NUMA override (`sw_numa_node`) effective in runtime paths.
2. Ensure completion vector CPU choice follows the intended NUMA policy.
3. Verify behavior after link down/up and channel reopen.

## Primary Code Area

- Driver file: `/home/mz/kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/eq.c`
- Key function: `mlx5_comp_vector_get_cpu`

## Current Function Behavior (Intent)

Preferred logic:

1. Read `dev->priv.sw_numa_node`.
2. If it is set, use `mlx5_cpumask_default_spread(sw_numa_node, vector)`.
3. Otherwise fall back to IRQ affinity mask / device NUMA spread.

This keeps behavior configurable and avoids hardwired NUMA pinning.

## Experimental Variants Used

### Variant A: Dynamic sw_numa_node path

- `mlx5_comp_vector_get_cpu` follows runtime `sw_numa_node`.
- Used to represent intended production behavior.

### Variant B: Hard force node1 return

- Temporary experiment path:
  - `return mlx5_cpumask_default_spread(1, vector);`
- Used to measure upper-bound impact of hard steering.
- Not intended as final production policy.

## Observed Pattern From EMON

Based on existing reports:

- Hard force node1 generally increases HITM significantly.
- Dynamic `sw_numa_node=1` is better than hard force, but still above loaded2 baseline in latest run.
- Hotspots migrate across runs, so decisions must rely on repeated controlled measurements.

Reference reports:

- [emon_hitm_compvec_force1_global_compare.md](emon_hitm_compvec_force1_global_compare.md)
- [emon_hitm_manual_reload_swnuma1_compare.md](emon_hitm_manual_reload_swnuma1_compare.md)

## Build And Reload Reminder

When code changes are made:

1. Build mlx5 modules.
2. Install module to active path.
3. Reload mlx5 stack.
4. Re-run NIC reconfiguration script.
5. Restart stable workload window.
6. Capture emon and compare with same method.

## Optimization Recommendations

1. Keep dynamic `sw_numa_node` logic as default policy.
2. Avoid permanent hard force return unless strictly needed for a targeted experiment.
3. Add repeated-run protocol (for example 3-5 runs per variant) and compare median totals.
4. Track both global total and effective interval (`40-79`) to avoid local optimization that hurts global behavior.
5. Confirm both traffic-side and interrupt-side affinity after link toggle.

## Related Docs

- Workload setup: [NIC_workload.md](NIC_workload.md)
- EMON analysis workflow: [NIC_emon_analysis.md](NIC_emon_analysis.md)
