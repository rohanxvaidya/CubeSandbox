# mlx5 NUMA Optimization: Complete Project Summary

## 1. Project Objective

**Goal**: Eliminate cross-NUMA cache contention (HITM) in the mlx5 NIC driver when the network workload (Redis) runs on a different NUMA node than the NIC's physical PCIe attachment.

**Problem Statement**:
- ConnectX NIC physically attached to NUMA 0 (PCIe topology)
- Redis workload pinned to NUMA 1 (cores 40-79)
- Default driver behavior: all memory allocations (EQ, CQ, RQ, SQ, UAR, IRQ table) on NUMA 0
- Result: every packet completion requires cross-NUMA memory access → `OCR.READS_TO_CORE.SNC_CACHE.HITM` spikes

**Target Metric**: Reduce `OCR.READS_TO_CORE.SNC_CACHE.HITM` on cores 40-79 (effective range) and globally.

---

## 2. Hardware Environment

| Component | Detail |
|-----------|--------|
| Platform | Granite Rapids (GNR) Server |
| CPU | Single socket, SNC2 enabled (2 NUMA nodes from 1 physical socket) |
| NUMA 0 | cores 0-39, 120-159 |
| NUMA 1 | cores 40-79, 160-199 |
| NUMA 2 | cores 80-119, 200-239 |
| NIC | Mellanox ConnectX (mlx5_core), physically on NUMA 0 |
| Kernel | Linux 6.8 (net6p8 tree) |
| Redis | 20 instances pinned to cores 40-59 |
| NIC IRQs | 63 completion vectors, bound to cores 40-79 |

---

## 3. mlx5 Driver Key Concepts

### 3.1 Memory Allocation Hierarchy

```
modprobe mlx5_core
  └─ mlx5_mdev_init()
       └─ priv->numa_node = <source of truth for all allocations>
            ├─ mlx5_irq_table_create()        → IRQ table struct [priv->numa_node]
            ├─ comp_irq_request_pci(vecidx)    → per-vector IRQ + CPU assignment
            │     └─ mlx5_cpumask_default_spread(numa_node, vecidx) → pick CPU
            ├─ create_comp_eqs()               → EQ ring buffers [priv->numa_node]
            └─ mlx5e_open_channel(ix)          → per-channel allocations
                  ├─ c->cpu = mlx5_comp_vector_get_cpu(dev, ix)
                  ├─ kvzalloc_node(channel, cpu_to_node(c->cpu))
                  ├─ CQ buffer [cpu_to_node(c->cpu)]
                  ├─ RQ buffer [cpu_to_node(c->cpu)]
                  └─ SQ buffer [cpu_to_node(c->cpu)]
```

### 3.2 Key Functions

| Function | File | Role |
|----------|------|------|
| `mlx5_mdev_init()` | main.c | Sets `priv->numa_node`, drives all downstream |
| `mlx5_cpumask_default_spread()` | eq.c | Picks CPU on target NUMA by index |
| `comp_irq_request_pci()` | eq.c | Allocates comp IRQ, assigns to CPU |
| `mlx5_comp_vector_get_cpu()` | eq.c | Returns CPU for a given comp vector |
| `mlx5e_open_channel()` | en_main.c | Opens channel, allocates RQ/SQ/CQ |
| `mlx5e_build_create_cq_param()` | en/params.c | Sets CQ node = cpu_to_node(c->cpu) |

### 3.3 NUMA Decision Chain

```
priv->numa_node
  → comp_irq_request_pci() → CPU selection for IRQ
    → mlx5_comp_vector_get_cpu() → CPU visible to channel open
      → cpu_to_node(c->cpu) → NUMA node for all buffer allocations
```

**Key Insight**: Controlling `priv->numa_node` (or per-queue NUMA in IRQ spread) controls the entire allocation chain. No need to modify individual allocation sites.

### 3.4 Why Hot-Modify (sw_numa_node) Doesn't Work

| Resource | Allocated When | Freed When |
|----------|---------------|------------|
| EQ DMA buffers | mlx5_load() | mlx5_unload() (rmmod) |
| IRQ table struct | mlx5_load() | mlx5_unload() |
| UAR pages | mlx5_load() | mlx5_unload() |
| CQ/RQ/SQ buffers | ip link up | ip link down |

EQ/IRQ/UAR are allocated once at module load and never freed until rmmod. Changing `sw_numa_node` at runtime only affects CQ/RQ/SQ on next link up — the shared infrastructure stays on the original node.

---

## 4. Implementation: Two-Level NUMA Control

### 4.1 Level 1: Global `numa_node` Module Parameter

```c
static int mlx5_numa_node = NUMA_NO_NODE;
module_param_named(numa_node, mlx5_numa_node, int, 0444);
```

Usage: `modprobe mlx5_core numa_node=1`

Effect: ALL allocations (EQ, UAR, IRQ table, CQ, RQ, SQ) go to NUMA 1.

### 4.2 Level 2: Per-Queue `queue_numa` Module Parameter

```c
static char *mlx5_queue_numa;
module_param_named(queue_numa, mlx5_queue_numa, charp, 0444);
```

Usage: `modprobe mlx5_core queue_numa='0-9:0,10-62:1'`

Effect: Queue 0-9 comp IRQs spread to NUMA 0 CPUs, queue 10-62 to NUMA 1 CPUs. Channel buffers follow automatically via `cpu_to_node(c->cpu)`.

### 4.3 Precedence

```
queue_numa[vecidx] defined?  → use it
  else numa_node set?        → use it
    else                     → use dev_to_node(pci_dev)
```

---

## 5. EMON Validation Method

### 5.1 Primary Event

```
OCR.READS_TO_CORE.SNC_CACHE.HITM
```

Measures: cache line reads that hit modified data in a sibling SNC cache cluster (cross-NUMA-node contention within the socket).

### 5.2 Capture Command

```bash
source /opt/intel/sep/sep_vars.sh
cd /home/mz/gnr_nic_perf/260508
EVENT="OCR.READS_TO_CORE.SNC_CACHE.HITM"
TS=$(date +%Y%m%d_%H%M%S)
OUT="emon_hitm_${TS}.txt"

# Wait for workload stabilization
sleep 15

# 20 samples, 1-second interval
emon -t1 -l20 -experimental -C "$EVENT" > "$OUT"
```

### 5.3 Analysis Method

```python
# Parse per-core values from 20 samples
# Compute per-core mean
# Metrics:
#   - Effective total: sum(means[40:80])  ← Redis + IRQ cores
#   - Global total: sum(means[all])
#   - Hotspot identification: p95/p99 percentile cores
```

### 5.4 Key Metrics (Decision Criteria)

| Metric | What it tells you |
|--------|------------------|
| Effective total (cores 40-79) | Direct workload-impacting HITM |
| Global total (all cores) | System-wide cross-cache penalty |
| Hotspot cores | Where contention concentrates |
| Delta vs baseline | Whether change improved or regressed |

### 5.5 Complementary Events (Full EMON Sweep)

For deeper analysis using full emon post-processing:

```bash
./emon.sh <test_name> <config_file>
# Config: graniterapids_server_events_private_chacms_cha_cms_crs_sbo_mdf_iio_irp_b2cxl_ubox-msi_cxl_20260209.txt
```

Key supplementary metrics:
- `OCR.DEMAND_DATA_RD.L3_HIT.SNOOP_HITM` — L3 hit with modified snoop
- `OCR.DEMAND_RFO.L3_HIT.SNOOP_HITM` — RFO (write intent) snoop HITM
- `metric_L2 Any local request that HITM in a sibling core` — L2 contention
- `MEM_LOAD_L3_MISS_RETIRED.REMOTE_HITM` — remote NUMA HITM
- `metric_memory bandwidth total` — memory bandwidth utilization
- `metric_CHA RxC IRQ latency` — interrupt handling latency

---

## 6. Results Summary

| Scheme | Effective (40-79) | Global | vs Best Previous |
|--------|------------------:|-------:|-----------------|
| force1 (hard node1) | 22,793,006 | 34,161,822 | worst |
| manual sw_numa_node=1 | 19,121,246 | 25,775,819 | - |
| loaded2 (old baseline) | 16,785,236 | 22,408,148 | previous best |
| **pure module_param v6.8** | **15,114,459** | **18,665,131** | **-10% / -17%** |

Full EMON sweep (NVMe fio test):
- `SNOOP_HITM` (data reads): **-75%**
- `SNOOP_HITM` (RFO): **-59%**
- L2 sibling HITM: **-44%**
- Memory bandwidth: **+3.4%**
- IRQ latency: **-11%**

---

## 7. Automated Optimization & Validation Loop

### 7.1 Architecture

```
┌──────────────────────────────────────────────────┐
│              Optimization Loop                    │
│                                                  │
│  ┌─────────┐    ┌─────────┐    ┌─────────────┐  │
│  │ 1.Build │───▶│ 2.Deploy│───▶│ 3.Configure │  │
│  └─────────┘    └─────────┘    └─────────────┘  │
│       ▲                              │           │
│       │                              ▼           │
│  ┌─────────┐    ┌─────────┐    ┌─────────────┐  │
│  │6.Decide │◀───│5.Compare│◀───│ 4.Measure   │  │
│  └─────────┘    └─────────┘    └─────────────┘  │
│                                                  │
└──────────────────────────────────────────────────┘
```

### 7.2 Implementation Script

```bash
#!/bin/bash
# auto_validate.sh — Automated build-deploy-measure-compare loop
#
# Usage: ./auto_validate.sh [queue_numa_config]
# Example: ./auto_validate.sh "0-9:0,10-62:1"

set -e
WORK_DIR=/home/mz/gnr_nic_perf/260508
KERNEL_DIR=/home/mz/kernel/net6p8
MLX5_DIR=$KERNEL_DIR/drivers/net/ethernet/mellanox/mlx5/core
REDIS_DIR=/home/mz/redis
CLIENT=10.239.23.34
TS=$(date +%Y%m%d_%H%M%S)
QUEUE_NUMA="${1:-}"
NUMA_NODE="${2:-1}"

echo "=== Step 1: Build mlx5 module ==="
cd $KERNEL_DIR
make -j$(nproc) M=$MLX5_DIR

echo "=== Step 2: Deploy (reload driver) ==="
# Stop workload
ssh root@$CLIENT "pkill -9 redis-benchmark" 2>/dev/null || true
sleep 2

# Unload and reload
rmmod mlx5_ib mlx5_core 2>/dev/null || true
if [ -n "$QUEUE_NUMA" ]; then
    modprobe mlx5_core numa_node=$NUMA_NODE queue_numa="$QUEUE_NUMA"
else
    modprobe mlx5_core numa_node=$NUMA_NODE
fi

echo "=== Step 3: Configure NIC and workload ==="
# Reconfigure NIC (IP, IRQ affinity)
bash /home/mz/redis/reconfig_nic.sh

# Verify driver state
echo "numa_node=$(cat /sys/module/mlx5_core/parameters/numa_node)"
echo "queue_numa=$(cat /sys/module/mlx5_core/parameters/queue_numa 2>/dev/null)"

# Restart Redis servers
cd $REDIS_DIR
base_core=40 SNC=1 bash redis_bench.sh server
sleep 5

# Start benchmark on client
ssh root@$CLIENT "IP=10.10.10.100 nohup bash /home/mz/redis/redis_bench.sh &"

echo "=== Step 4: Measure (wait 15s + capture EMON) ==="
sleep 15
source /opt/intel/sep/sep_vars.sh
EVENT="OCR.READS_TO_CORE.SNC_CACHE.HITM"
OUT="$WORK_DIR/emon_hitm_auto_${TS}.txt"
emon -t1 -l20 -experimental -C "$EVENT" > "$OUT"
ROWS=$(awk '/^OCR\.READS_TO_CORE\.SNC_CACHE\.HITM/ {c++} END{print c+0}' "$OUT")
echo "Captured $ROWS samples → $OUT"

echo "=== Step 5: Compare with baseline ==="
python3 - "$OUT" <<'PYEOF'
import sys, statistics

fname = sys.argv[1]
with open(fname) as f:
    content = f.read()

rows = []
for line in content.split('\n'):
    if line.startswith('OCR.READS_TO_CORE.SNC_CACHE.HITM'):
        parts = line.split()
        nums = []
        for p in parts[1:]:
            p = p.replace(',','')
            try: nums.append(int(p))
            except: pass
        if len(nums) > 2:
            rows.append(nums[2:])

ncores = len(rows[0])
means = [statistics.mean([r[c] for r in rows]) for c in range(ncores)]

effective = sum(means[40:80])
total = sum(means)

# Baseline: pure module_param v6.8 best
base_eff = 15114459
base_total = 18665131

print(f"Effective (40-79): {effective:,.0f}  (baseline: {base_eff:,.0f}, delta: {(effective-base_eff)/base_eff*100:+.1f}%)")
print(f"Global total:      {total:,.0f}  (baseline: {base_total:,.0f}, delta: {(total-base_total)/base_total*100:+.1f}%)")

if effective < base_eff:
    print("RESULT: IMPROVEMENT ✓")
elif effective > base_eff * 1.05:
    print("RESULT: REGRESSION ✗")
else:
    print("RESULT: WITHIN NOISE (~)")
PYEOF

echo "=== Step 6: Done ==="
echo "Review: $OUT"
```

### 7.3 Automated Sweep (Multiple Configurations)

```bash
#!/bin/bash
# sweep_queue_numa.sh — Try multiple queue_numa configurations
CONFIGS=(
    "numa_node=1|"                          # all on NUMA 1
    "numa_node=1|0-9:0,10-62:1"            # 10 on NUMA0, 53 on NUMA1
    "numa_node=1|0-19:0,20-62:1"           # 20 on NUMA0, 43 on NUMA1
    "numa_node=0|"                          # all on NUMA 0 (baseline)
)

for cfg in "${CONFIGS[@]}"; do
    IFS='|' read -r numa qnuma <<< "$cfg"
    node_val=${numa#numa_node=}
    echo "========================================"
    echo "Testing: numa_node=$node_val queue_numa='$qnuma'"
    echo "========================================"
    ./auto_validate.sh "$qnuma" "$node_val" | tee -a sweep_results_$(date +%Y%m%d).log
    echo ""
    sleep 5
done
```

### 7.4 CI Integration Points

| Step | Tool | Automation |
|------|------|-----------|
| Build | `make M=...` | Makefile target |
| Deploy | `rmmod + modprobe` | Shell script |
| Configure | `reconfig_nic.sh` | Existing script |
| Workload | `redis_bench.sh` | Existing scripts |
| Measure | `emon -t1 -l20` | Fixed command |
| Parse | Python inline | Reusable parser |
| Compare | Threshold check | Pass/fail decision |
| Report | CSV append | Historical tracking |

---

## 8. File Organization

```
/home/mz/kernel/net6p8/                     ← Kernel source
  drivers/net/ethernet/mellanox/mlx5/core/
    main.c                                  ← Module params + parser
    eq.c                                    ← Per-queue IRQ spreading

/home/mz/gnr_nic_perf/260508/              ← Experiment data
  NIC_benchmark_master.md                   ← Navigation index
  NIC_emon_analysis.md                      ← EMON methodology
  NIC_driver_optimization.md                ← Driver change notes
  NIC_workload.md                           ← Workload setup
  mlx5_per_queue_numa_design.md             ← Per-queue design doc
  mlx5_numa_optimization_summary.md         ← THIS FILE
  0001-mlx5-add-numa_node-module-parameter*.patch
  0001-mlx5-add-per-queue-NUMA-node*.patch
  emon_hitm_pure_module_param_v68_*.txt     ← Best result data
  emon_hitm_pure_module_param_v68_all_cores.png

/home/mz/redis/                             ← Workload scripts
  redis_bench.sh
  reconfig_nic.sh

/home/mz/reload_mlx5_numa1.sh              ← Quick reload helper
```

---

## 9. Key Learnings

1. **Module load time is the only effective control point** — EQ/IRQ/UAR are allocated once and never freed until rmmod.
2. **IRQ CPU assignment drives buffer NUMA** — the channel open path uses `cpu_to_node(c->cpu)` everywhere.
3. **Simple is better** — 7 lines of code (module param) achieved the best HITM reduction vs all complex sw_numa_node approaches.
4. **Per-queue extends without breaking** — `queue_numa` overrides per-queue while `numa_node` handles shared infrastructure.
5. **Validation must be automated** — manual captures are error-prone; fixed emon protocol + scripted comparison ensures reproducibility.
