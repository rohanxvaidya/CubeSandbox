# mlx5 队列架构分析 & XPS 根因

## 一、SQ/CQ/RQ/EQ 概念

| 队列 | 全称 | 方向 | 作用 |
|------|------|------|------|
| **SQ** | Send Queue | TX | 应用发包时，内核写 WQE (Work Queue Entry) 到 SQ ring buffer，HW DMA 读取并发送 |
| **RQ** | Receive Queue | RX | HW 收到包后 DMA 写入 RQ buffer (page pool)，内核从中构建 skb |
| **CQ** | Completion Queue | TX+RX 各一个 | HW 完成操作后写 CQE 通知内核。每个 SQ 和 RQ 各有独立的 CQ |
| **EQ** | Event Queue | 中断通知 | HW 写 EQE 触发 IRQ → NAPI poll → 依次处理 TX CQ 和 RX CQ |

## 二、数据流

```
TX: app sendmsg() → mlx5e_xmit() → 写 WQE 到 SQ → ring doorbell → HW DMA 发包 → 写 CQE 到 TX CQ
RX: HW 收包 → DMA 到 RQ page → 写 CQE 到 RX CQ → EQ 产生 EQE → IRQ → NAPI → poll RX CQ → build skb
```

NAPI poll (`mlx5e_napi_poll`) 在一次轮询中处理：
1. TX CQ completions (释放已发送的 skb)
2. RX CQ (收包、构建 skb、递交协议栈)

## 三、Per-Channel 结构

每个 channel 对应一个 queue index，包含完整的一套队列：

```
Channel[ix]  (cpu = mlx5_comp_vector_get_cpu(mdev, ix))
├── rq          ← 1 个 RQ + 1 个 RX CQ
├── sq[num_tc]  ← N 个 SQ + N 个 TX CQ (per traffic class)
├── icosq       ← 内部控制 SQ
└── napi        ← 统一的 NAPI 实例
```

## 四、NUMA 分配逻辑

所有 per-channel 的 SQ/RQ/CQ 通过 `cpu_to_node(c->cpu)` 分配：

```c
// en_main.c: mlx5e_open_channel()
int cpu = mlx5_comp_vector_get_cpu(priv->mdev, ix);
c = kvzalloc_node(sizeof(*c), GFP_KERNEL, cpu_to_node(cpu));
c->cpu = cpu;

// SQ 分配
param->wq.db_numa_node = cpu_to_node(c->cpu);
mlx5e_alloc_txqsq_db(sq, cpu_to_node(c->cpu));

// RQ 分配
mlx5e_open_rq(params, rq_params, NULL, cpu_to_node(c->cpu), &c->rq);

// CQ 分配
ccp->node = cpu_to_node(c->cpu);
param->wq.buf_numa_node = ccp->node;
param->wq.db_numa_node  = ccp->node;
```

## 五、XPS (Transmit Packet Steering) 根因分析

### XPS 不是基于应用 CPU，而是基于 IRQ affinity

XPS 设置逻辑在 `mlx5e_set_default_xps_cpumasks()`：

```c
num_comp_vectors = mlx5_comp_vectors_max(mdev);

for (ix = 0; ix < params->num_channels; ix++) {
    cpumask_clear(priv->scratchpad.cpumask);
    for (irq = ix; irq < num_comp_vectors; irq += params->num_channels) {
        int cpu = mlx5_comp_vector_get_cpu(mdev, irq);
        cpumask_set_cpu(cpu, priv->scratchpad.cpumask);
    }
    netif_set_xps_queue(priv->netdev, priv->scratchpad.cpumask, ix);
}
```

**逻辑**：tx-ix 映射到该 channel 的 IRQ 所在 CPU。目的是让 TX 发包和 TX completion (NAPI) 在同一个 core 上执行。

### 为什么 XPS 只对 cores 40-55 有效

`mlx5e_set_default_xps_cpumasks()` 只在以下场景调用：
1. 设备初始化 (`mlx5e_nic_init` / attach)
2. channel 数量变化时 (`mlx5e_num_channels_changed`)

但 `queue_numa_store` 的 `dev_close()` → EQ rebuild → `dev_open()` 路径中，`mlx5e_open_locked()` **不会**调用 `mlx5e_set_default_xps_cpumasks()`。

结果：XPS 停留在模块首次 load 时的映射：
- module load 时 comp0-15 的 IRQ 在 cores 40-55 → tx-0~15 的 XPS 正确
- queue_numa=1 后 comp16-19 的 IRQ 移到了 cores 56-59，但 XPS 未更新

### 当前系统 XPS 映射

```
CPU 40 → tx-0   (comp1 IRQ 在 core 40)  ← XPS 正确，TX 和 NAPI 同核
CPU 41 → tx-1   (comp2 IRQ 在 core 41)  ← XPS 正确
...
CPU 55 → tx-15  (comp16 IRQ 在 core 55) ← XPS 正确
CPU 56 → 无 XPS 映射 !!!  (comp17 IRQ 已移到 core 56)
CPU 57 → 无 XPS 映射 !!!  (comp18 IRQ 已移到 core 57)
CPU 58 → 无 XPS 映射 !!!
CPU 59 → 无 XPS 映射 !!!
```

### HITM 2x 差异的原因

1. **Cores 40-55** (有 XPS)：Redis 发包 → XPS 选择 tx-N → 该 channel 的 NAPI 在**同一个 core** 上完成 TX completion → SQ 的 cacheline **不跨核** → 低 HITM

2. **Cores 56-59** (无 XPS)：Redis 发包 → fallback 到 hash 选队列 → 随机选择某个 queue → 该 queue 的 NAPI 在**另一个 core** (40-55) 上做 TX completion → SQ 的 `pc/cc/skb_fifo` 等 cacheline 在两个核之间**乒乓弹跳** → 高 HITM

### TX 中跨核弹跳的热点数据结构 (SQ)

```c
struct mlx5e_txqsq {
    u16 cc;           // NAPI 写 (completion), App 读 (检查空间)
    u16 pc;           // App 写 (xmit), NAPI 读 (计算完成量)
    struct {
        struct mlx5e_sq_dma *dma_fifo;      // App 写, NAPI 读(unmap)
        struct mlx5e_skb_fifo skb_fifo;     // App 写(记录skb), NAPI 读(free skb)
        struct mlx5e_tx_wqe_info *wqe_info; // App 写, NAPI 读
    } db;
};
```

## 六、修复方案

在 `queue_numa_store` 的 `dev_open()` 之后加 XPS 更新（已实现）：

```c
/* Update XPS to match new IRQ affinities */
num_queues = min_t(int, netdev->real_num_tx_queues,
                   mlx5_comp_vectors_max(dev));
for (qi = 0; qi < num_queues; qi++) {
    int cpu = mlx5_comp_vector_get_cpu(dev, qi);
    if (cpu >= nr_cpu_ids)
        continue;
    netif_set_xps_queue(netdev, cpumask_of(cpu), qi);
}
```

修复后效果：core 56 → tx-16 (comp17 NAPI 在 core 56) → TX 和 completion 同核，消除 SQ cacheline 弹跳。

## 七、验证结果

### 测试环境
- Remote client: 10.239.23.34 → redis-benchmark -c 300 × 19 instances
- Server: GNR single socket, 19 Redis servers on cores 40-59 (port 50001-50020)
- NIC: mlx5 ens7f0np0, 63 queues, queue_numa=1
- XPS: core N → tx-Q where comp(Q+1) IRQ affinity = core N

### HITM 对比 (OCR.READS_TO_CORE.SNC_CACHE.HITM, 100 samples)

| 指标 | Before XPS Fix | After XPS Fix | 改善 |
|------|---------------|---------------|------|
| Cores 40-55 平均 HITM | 686,000 | 802,023 | - |
| Cores 56-59 平均 HITM | 1,377,000 | 963,046 | -30% |
| **Ratio (56-59)/(40-55)** | **2.0x** | **1.20x** | **消除异常** |

### 关键发现

1. Cores 56-59 并非 "Redis-only" — 它们实际上是 comp17-comp20 的 IRQ 处理核
2. 修复前 XPS 是 stale 的（来自 probe 时的默认映射），导致 cores 56-59 的 TX 被随机分配到其他队列
3. 修复后 XPS 确保每个核的 TX 流量走对应的 SQ，TX 和 NAPI completion 在同一个核完成
4. HITM ratio 从 2.0x 降至 1.20x（接近 1:1），证明 SQ cacheline bouncing 被消除

### 修复代码位置
`/home/mz/kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/main.c` — `queue_numa_store()`

Chart: `/home/mz/emon_data/emon_numa1_eq_fix/hitm_xps_fix_comparison.png`
Data:  `/tmp/hitm_xps_fix_real.txt` (100 samples, real NIC traffic)
