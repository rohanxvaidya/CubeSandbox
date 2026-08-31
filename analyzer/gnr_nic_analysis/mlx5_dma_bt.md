# mlx5 bpftrace probe selection and logic

## Why these kprobes were selected

### 1) Queue open probes (exact ring buffer addresses after init)

Probes:
- kprobe: mlx5e_open_rq
- kretprobe: mlx5e_open_rq
- kprobe: mlx5e_open_txqsq
- kretprobe: mlx5e_open_txqsq
- kprobe: mlx5e_open_cq
- kretprobe: mlx5e_open_cq

Reason:
- Queue control objects are fully initialized only after open paths complete.
- Entry probes can observe zero/uninitialized fields.
- Return probes with retval == 0 provide stable, populated fields.

Kernel code evidence:
- /home/mz/kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c
  - mlx5e_open_rq at line around 1276
  - mlx5e_open_txqsq at line around 1764
  - mlx5e_open_cq at line around 2112

### 2) Hot path probes (discover active queues without reopen)

Probes:
- kprobe: mlx5e_post_rx_wqes
- kprobe: mlx5e_sq_xmit_prepare.isra.0

Reason:
- Queue open probes only trigger when channels are opened/reconfigured.
- These hot path probes run during normal traffic, so queue objects can be captured without channel reconfiguration.
- Useful for long-running systems where queues are already active.

Kernel code evidence:
- /home/mz/kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_rx.c
  - mlx5e_post_rx_wqes at line around 894

### 3) DMA API probes (raw data DMA addresses)

Probes:
- kprobe: dma_map_page_attrs
- kretprobe: dma_map_page_attrs

Reason:
- DMA address is returned by mapper, so return probe is required.
- Entry + return pairing allows capturing size and returned DMA address.
- Filtering by pdev learned from mlx5 queue probes reduces unrelated noise.
- Nested calls are handled with per-thread depth maps.

Why this API and not dma_map_single_attrs:
- On this host, dma_map_single_attrs was not reliably traceable.
- dma_map_page_attrs is traceable and provided stable capture.

Kernel code evidence (mlx5 usage paths):
- TX mapping path:
  - /home/mz/kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_tx.c
    - mlx5e_txwqe_build_dsegs at line around 177
    - dma_map_single at line around 186
    - skb_frag_dma_map at line around 204
- RX mapping usage:
  - /home/mz/kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_rx.c
    - page_pool_get_dma_addr at line around 361

## Why these structures were selected

### Queue structures
- struct mlx5e_rq
- struct mlx5e_txqsq
- struct mlx5e_cq

Definition location:
- /home/mz/kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en.h
  - struct mlx5e_cq around line 353
  - struct mlx5e_txqsq around line 425
  - struct mlx5e_rq around line 667

Reason:
- These hold queue identity fields (rqn/sqn/indexes), pdev pointer, and queue control object.

### Queue control and ring backing structures
- struct mlx5_wq_ctrl
- struct mlx5_wq_cyc
- struct mlx5_wq_ll

Definition location:
- /home/mz/kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/wq.h
  - struct mlx5_wq_ctrl around line 45
  - struct mlx5_wq_cyc around line 51
  - struct mlx5_wq_ll around line 70

Reason:
- mlx5_wq_ctrl is the key container:
  - buf (ring backing pages)
  - db (doorbell record)

### Ring page DMA and doorbell DMA source

Allocation logic location:
- /home/mz/kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/alloc.c
  - mlx5_frag_buf_alloc_node around line 74
  - frag map assignment around line 92 via frag->map
  - db dma assignment around line 179 via db->dma

Reason:
- frag->map is the DMA address for each ring backing page.
- db->dma is the doorbell DMA address.

## Tracing logic details

### A) Queue ring capture
1. On queue-open entry, store queue pointer in a per-thread map.
2. On queue-open return with retval == 0, dereference queue pointer and read:
   - queue id fields
   - db_dma from wq_ctrl.db.dma
   - ring page addresses from wq_ctrl.buf.frags[i].map
3. Print SQ_OPEN, RQ_OPEN, CQ_OPEN records.

Why this is reliable:
- Reads happen after successful open path completion.

### B) Current queue capture without reopen
1. Probe RX/TX hot functions.
2. Read queue object directly from function argument.
3. Print once per queue id (seen maps) to avoid flood.

Why this is needed:
- Systems may run for long periods without queue reopen.

### C) Raw DMA capture
1. On dma_map_page_attrs entry (filtered by known mlx5 pdev), store:
   - size
   - pdev
   - per-thread nesting depth
2. On return, use matching depth slot and print RAW_DMA_MAP.
3. Clear slot and decrement depth.

Why this is needed:
- Raw buffer DMA address comes from mapper return value.
- Nested map calls require depth-safe matching.

## Practical notes from this run

- Capture directory used:
  - /home/mz/gnr_nic_perf/260408/mlx5_exact_dma_forced2
- Script used:
  - /home/mz/gnr_nic_perf/260408/trace_mlx5_exact_dma_bpftrace.sh
- Post parser:
  - /home/mz/gnr_nic_perf/260408/parse_mlx5_exact_dma_results.sh

Observed:
- Non-zero SQ and RQ ring addresses were captured.
- RAW_DMA_MAP events were captured in large volume.
- Most mappings correlate to mlx5 pdev; a smaller pdev=0x0 bucket is trace artifact/noise and can be filtered.
