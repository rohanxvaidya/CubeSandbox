# mlx5 Per-Queue NUMA Node Mapping Design

## Background

Current `numa_node` module parameter sets ALL queues to a single NUMA node. For mixed workloads spanning multiple NUMA nodes, per-queue control is needed.

## Interface

```bash
modprobe mlx5_core queue_numa='0-9:0,10-62:1'
```

Format: `start-end:node[,start-end:node,...]` or `single_queue:node`

## Architecture

### What Per-Queue Controls (via IRQ spreading)

- RQ buffer (receive ring DMA memory)
- SQ buffer (send ring DMA memory)
- CQ buffer (completion queue DMA memory)
- Channel struct itself

### What Remains Global (uses `numa_node` param)

- EQ buffers (one EQ serves multiple CQs)
- IRQ table struct
- UAR pages (doorbell mapping)
- Command interface buffers

## Implementation

### Data Flow

```
queue_numa="0-9:0,10-62:1"
  → comp_irq_request_pci(vecidx): lookup mlx5_queue_numa_map[vecidx]
    → mlx5_cpumask_default_spread(target_numa, vecidx): pick CPU on target NUMA
      → mlx5_irq_request_vector(dev, cpu, vecidx): bind comp IRQ to that CPU
        → mlx5_comp_vector_get_cpu(dev, ix): returns the CPU
          → mlx5e_open_channel: c->cpu = that CPU
            → cpu_to_node(c->cpu) = target NUMA node
              → All RQ/SQ/CQ/channel allocations on target node
```

### Files Modified (vs v6.8)

| File | Change |
|------|--------|
| `main.c` | +69 lines: `queue_numa` param, parser, global map array |
| `eq.c` | +24 lines: per-queue NUMA lookup in `comp_irq_request_pci()` and `mlx5_comp_vector_get_cpu()` |

### Key Code

**main.c** — Module parameter and parser:
```c
#define MLX5_MAX_QUEUE_NUMA 256
static char *mlx5_queue_numa;
module_param_named(queue_numa, mlx5_queue_numa, charp, 0444);

int mlx5_queue_numa_map[MLX5_MAX_QUEUE_NUMA];  /* NUMA_NO_NODE = use default */
int mlx5_queue_numa_map_len;
```

**eq.c** — IRQ spreading with per-queue NUMA:
```c
static int comp_irq_request_pci(struct mlx5_core_dev *dev, u16 vecidx)
{
    ...
    extern int mlx5_queue_numa_map[];
    extern int mlx5_queue_numa_map_len;
    if (vecidx < mlx5_queue_numa_map_len &&
        mlx5_queue_numa_map[vecidx] != NUMA_NO_NODE)
        numa = mlx5_queue_numa_map[vecidx];
    else
        numa = dev->priv.numa_node;

    cpu = mlx5_cpumask_default_spread(numa, vecidx);
    ...
}
```

## Why IRQ Affinity Cannot Be Used Post-Load

1. IRQs don't exist until `modprobe` (MSI-X allocated during probe)
2. Even if changed via `/proc/irq/NNN/smp_affinity_list` after load, `mlx5_comp_irq_get_affinity_mask()` reads driver's internal `mlx5_irq->mask`, not kernel's effective affinity
3. Channel buffer allocation happens at `ip link set up`, but uses driver-internal CPU tracking

→ Must control NUMA at IRQ allocation time inside the driver.

## Usage Examples

```bash
# All 63 queues on NUMA 1 (backward compatible)
modprobe mlx5_core numa_node=1

# 10 queues on NUMA 0, 53 on NUMA 1
modprobe mlx5_core queue_numa='0-9:0,10-62:1'

# Mixed: shared infra on NUMA 1, per-queue split
modprobe mlx5_core numa_node=1 queue_numa='0-9:0,10-62:1'

# Single queue override
modprobe mlx5_core numa_node=1 queue_numa='0:0,1-62:1'
```

## EQ Constraint

```
EQ (node 1) ← CQ0 (node 0) ← RQ0/SQ0 (node 0)   // 10 queues on NUMA 0
EQ (node 1) ← CQ1 (node 1) ← RQ1/SQ1 (node 1)   // 53 queues on NUMA 1
```

Queues on NUMA 0 still have their completion events delivered via NUMA 1's EQ buffer. This adds ~10-20ns for EQ access but avoids the much larger penalty of all data path buffers being on the wrong node.

## Git History

```
85d515df8713 mlx5: add per-queue NUMA node mapping via queue_numa parameter
8779453c0374 mlx5: add numa_node module parameter for NUMA-aware allocations
e8f897f4afef Linux 6.8  (tag: v6.8)
```

## EMON Validation (pure numa_node=1, all queues on NUMA 1)

### OCR.READS_TO_CORE.SNC_CACHE.HITM

| Scheme | Effective (40-79) | Global (all cores) |
|--------|------------------:|-------------------:|
| force1 (node forced) | 22,793,006 | 34,161,822 |
| manual sw_numa_node=1 | 19,121,246 | 25,775,819 |
| loaded2 (old baseline) | 16,785,236 | 22,408,148 |
| **pure module_param v6.8** | **15,114,459** | **18,665,131** |

Improvement vs best previous: **-10% effective, -16.7% global**

### System-Level Metrics (fio NVMe test)

| Metric | numa_node=1 | numa_node=0 (baseline) |
|--------|-------------|------------------------|
| OCR.DEMAND_DATA_RD.L3_HIT.SNOOP_HITM | 191,115 | 752,272 (**-75%**) |
| OCR.DEMAND_RFO.L3_HIT.SNOOP_HITM | 129,938 | 316,136 (**-59%**) |
| L2 HITM sibling (per instr) | 5.97e-05 | 1.07e-04 (**-44%**) |
| Memory BW total | 664 MB/s | 643 MB/s (**+3.4%**) |
| CHA RxC IRQ latency | 7.23 ns | 8.12 ns (**-11%**) |
