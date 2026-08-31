# mlx5 NIC DMA analysis

## What is already confirmed

- NIC interface is `ens7f0np0` with IP `10.10.10.100`.
- Driver is `mlx5_core` on PCI function `0000:64:00.0`.
- Redis processes are pinned to cores `40-59`.
- NIC IRQs are not only on `0-39`; some vectors are pinned to `120-142`, and one vector is wide-open on `0-239`.

## What the IOMMU output means

The line below does **not** identify a queue DMA buffer address:

```text
Device 0000:64:00.0 @0x113fb4000
```

That address is the Intel IOMMU page-table root pointer for the device domain. It is metadata for DMA translation, not an mlx5 RX/TX queue buffer.

The `dmar_translation_struct` output is also IOMMU metadata:

```text
64:00.0  root_entry  context_entry  PASID  PASID_table_entry
```

Those entries describe VT-d tables for the PCI function. They do not directly expose mlx5 queue memory or packet-buffer DMA addresses.

## Where actual mlx5 queue DMA addresses live

From the kernel source in `/home/mz/kernel/net6p8`:

- Queue doorbell DMA addresses are stored in `struct mlx5_db dma`.
- Queue work-queue buffers are allocated by `mlx5_frag_buf_alloc_node()` with `dma_alloc_coherent()`, and each page DMA address is stored in `struct mlx5_buf_list.map`.
- RX packet DMA addresses are taken from `page_pool_get_dma_addr(...)` and written into RX WQEs in `mlx5e_alloc_rx_wqe()`.
- TX packet DMA addresses are produced by `dma_map_single()` or `skb_frag_dma_map()` and then stored in `sq->db.dma_fifo[]` through `mlx5e_dma_push()`.

## Host constraints that matter

- `bpftool`, `perf`, and `trace-cmd` are installed.
- `bpftrace` is missing.
- `clang` is missing, so a small CO-RE eBPF tracer cannot be built directly on this host without adding packages.
- `/sys/kernel/btf/mlx5_core` exists, so live mlx5 struct layouts can still be derived from module BTF.
- Tracefs kprobe events are writable.

## What the saved scripts do

### `extract_mlx5_btf_offsets.sh`

- Reads live module BTF from `/sys/kernel/btf/mlx5_core`.
- Extracts byte offsets for the mlx5 queue objects and nested DMA-bearing fields.
- Exports offsets for `mlx5e_rq`, `mlx5e_txqsq`, `mlx5e_cq`, `mlx5_wq_ctrl`, `mlx5_db`, `mlx5_frag_buf`, and `mlx5_buf_list`.

### `trace_mlx5_dma_addresses.sh`

- Installs kprobes on queue creation functions:
  - `mlx5e_create_rq`
  - `mlx5e_open_txqsq`
  - `mlx5e_open_cq`
- Captures queue metadata that includes:
  - queue index fields
  - queue doorbell DMA addresses
  - queue buffer fragment pointer arrays
  - number of queue buffer pages
- Records built-in trace events at the same time:
  - `iommu:map`
  - `page_pool:page_pool_state_hold`
  - `page_pool:page_pool_state_release`
  - `page_pool:page_pool_release`

This gives two useful data sets:

- persistent queue object DMA state when queues are created during the trace window
- actual DMA mapping addresses seen by the IOMMU during the trace window

## Important limitation

Without a stateful kprobe/kretprobe tracer such as a CO-RE eBPF program or `bpftrace`, this host cannot yet do a perfect live join of:

- queue index
- exact RX/TX packet-buffer DMA address
- every hot-path mapping event

The missing pieces are mostly caused by the absence of `clang` and `bpftrace`, not by a kernel limitation.

## Practical next step on this host

Run the saved script during a controlled workload window:

```bash
cd /home/mz/gnr_nic_perf/260408
./trace_mlx5_dma_addresses.sh
```

If the NIC queues are reopened during the trace window, the kprobe events will record the queue doorbell DMA and queue buffer metadata. Even without a reopen, `iommu:map` will still capture live DMA mappings that occur during traffic.

## Practical next step for full queue-to-buffer attribution

If you want exact per-queue RX/TX packet-buffer DMA attribution, the cleanest next step is to install one of the following without rebooting or rebuilding the kernel:

- `clang` and libbpf development headers, then use a small CO-RE eBPF tracer
- `bpftrace`, then use kprobe/kretprobe scripts with temporary state maps

Either option would let us correlate function entry arguments with return values and read the precise DMA addresses that mlx5 writes into queue state at runtime.

## Update: exact capture with bpftrace

`bpftrace` and `clang` are now available on this host, and an exact capture was executed with:

- `trace_mlx5_exact_dma_bpftrace.sh`
- output directory: `mlx5_exact_dma_forced2`

Captured evidence includes non-zero queue ring and raw DMA addresses:

- SQ ring examples:
  - `sqn=1197 db_dma=0x2830b2ac0 map0=0x28094f000 map1=0x180942000 map2=0x114643000 map3=0x250a7a000`
  - `sqn=1203 db_dma=0x2830b2d40 map0=0x1f71c7000 map1=0x141d2e000 map2=0x26b590000 map3=0x147658000`
- RQ ring examples:
  - `rqn=1198 db_dma=0x2830b2b00 map0=0x207a0f000`
  - `rqn=1204 db_dma=0x2830b2d80 map0=0x21f5fe000`
- Raw data DMA mapping examples:
  - `size=4096 dma=0x436d7f5000`
  - `size=4096 dma=0x436d7f4000`
  - `size=4096 dma=0x4371c53000`

All three record types share the same mlx5 device pointer in this run:

- `pdev=0xff3b117251aa20d0`

This provides exact queue-ring addresses and raw DMA mapping addresses from the running system without rebooting or rebuilding the kernel.


## Why use this kprobe function and structure
I’ll map each probe choice to the exact mlx5 kernel paths and show the code points that make those hooks reliable for queue ring addresses and raw DMA addresses. I’m collecting the precise function snippets and struct definitions first, then I’ll walk through the tracing logic step by step.

Read [](file:///home/mz/kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#1240-1240), lines 1240 to 1335

Read [](file:///home/mz/kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#1745-1745), lines 1745 to 1825

Read [](file:///home/mz/kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#2090-2090), lines 2090 to 2165

Read [](file:///home/mz/kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_tx.c#170-170), lines 170 to 225

Read [](file:///home/mz/kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_rx.c#332-332), lines 332 to 385

Read [](file:///home/mz/kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_rx.c#880-880), lines 880 to 940

Read [](file:///home/mz/kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en.h#345-345), lines 345 to 470

Read [](file:///home/mz/kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en.h#650-650), lines 650 to 760

Read [](file:///home/mz/kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/wq.h#40-40), lines 40 to 80

Read [](file:///home/mz/kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/alloc.c#60-60), lines 60 to 190

Searched for regex `kprobe:mlx5e_open_rq|kretprobe:mlx5e_open_rq|kprobe:mlx5e_open_txqsq|kretprobe:mlx5e_open_txqsq|kprobe:mlx5e_open_cq|kretprobe:mlx5e_open_cq|kprobe:mlx5e_post_rx_wqes|kprobe:mlx5e_sq_xmit_prepare.isra.0|kprobe:dma_map_page_attrs|kretprobe:dma_map_page_attrs` (`**/gnr_nic_perf/260408/trace_mlx5_exact_dma_bpftrace.sh`), 10 results

Searched for regex `int mlx5e_open_rq|int mlx5e_open_txqsq|int mlx5e_open_cq|MLX5_SET64\(wq, wq, dbr_addr|mlx5e_alloc_rq\(|mlx5e_create_sq_rdy` (`**/kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c`), 10 results

Searched for regex `static int mlx5e_alloc_rx_wqe|page_pool_get_dma_addr\(|INDIRECT_CALLABLE_SCOPE bool mlx5e_post_rx_wqes` (`**/kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_rx.c`), 12 results

Searched for regex `mlx5e_txwqe_build_dsegs|dma_map_single\(|skb_frag_dma_map\(|mlx5e_dma_push` (`**/kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_tx.c`), 9 results

Searched for regex `struct mlx5e_cq \{|struct mlx5e_txqsq \{|struct mlx5e_rq \{|struct mlx5e_sq_dma \{` (`**/kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en.h`), 4 results

Searched for regex `struct mlx5_wq_ctrl \{|struct mlx5_wq_cyc \{|struct mlx5_wq_ll \{` (`**/kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/wq.h`), 3 results

Searched for regex `mlx5_frag_buf_alloc_node|frag->map|db->dma` (`**/kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/alloc.c`), 6 results

Exactly. Here is the detailed reasoning for each kprobe and structure choice, tied to kernel code.

Why these probe functions were selected

1. Queue object probes for ring memory addresses
- Selected probes:
  - trace_mlx5_exact_dma_bpftrace.sh
  - trace_mlx5_exact_dma_bpftrace.sh
  - trace_mlx5_exact_dma_bpftrace.sh
  - trace_mlx5_exact_dma_bpftrace.sh
  - trace_mlx5_exact_dma_bpftrace.sh
  - trace_mlx5_exact_dma_bpftrace.sh

- Why:
  - These are the queue open paths where mlx5 queue control objects are allocated and populated.
  - We use kretprobe (not only kprobe entry) because ring fields are fully valid after the open path returns success.
  - This is why we changed from early entry reads (which showed zeros) to return-time reads.

- Kernel evidence:
  - RQ open flow: en_main.c
    - It calls alloc and create before returning.
  - SQ open flow: en_main.c
  - CQ open flow: en_main.c

2. Hot-path probes for current active queues without reopen
- Selected probes:
  - trace_mlx5_exact_dma_bpftrace.sh
  - trace_mlx5_exact_dma_bpftrace.sh

- Why:
  - Queue-open probes only trigger during open/reopen.
  - These two functions run during normal RX/TX traffic, so they let us discover active queue objects even if you do not reconfigure channels.

- Kernel evidence:
  - RX posting path: en_rx.c
  - TX prepare path exists and is used in TX flow; tx building path uses the same queue object.

3. Raw DMA address probes
- Selected probes:
  - trace_mlx5_exact_dma_bpftrace.sh
  - trace_mlx5_exact_dma_bpftrace.sh

- Why:
  - We need return value of DMA mapping call, because DMA address is returned from mapper.
  - So we pair entry and return probes and track per-thread state.
  - We filter by pdev learned from queue probes to focus on mlx5 device traffic.

- Why dma_map_page_attrs instead of dma_map_single_attrs:
  - On this kernel, dma_map_single_attrs was not reliably traceable; dma_map_page_attrs is traceable and captures the dominant RX raw mappings.
  - TX side in mlx5 may use both single and page mapping paths, but page mapping gave stable capture on this host.

- Kernel evidence:
  - RX uses page pool DMA addresses: en_rx.c
  - TX builds data segments from dma_map_single and skb_frag_dma_map: en_tx.c, en_tx.c, en_tx.c

Why these structures were selected

1. Queue structs
- en.h for mlx5e_rq
- en.h for mlx5e_txqsq
- en.h for mlx5e_cq

Reason:
- These hold queue identity and control path object mlx5_wq_ctrl.

2. Queue control and ring backing structs
- wq.h for mlx5_wq_ctrl
- wq.h for mlx5_wq_cyc
- wq.h for mlx5_wq_ll

Reason:
- mlx5_wq_ctrl contains:
  - buf: ring backing pages
  - db: doorbell record (DMA visible)

3. Ring page DMA and doorbell DMA source
- alloc.c
- alloc.c
- alloc.c

Reason:
- frag.map is the DMA address of each ring backing page.
- db.dma is the DMA address of the doorbell record.

Core logic used in the tracer

1. Queue ring capture logic
- On queue-open return success, read:
  - queue id fields (rqn or sqn)
  - db_dma from wq_ctrl.db.dma
  - ring page addresses from wq_ctrl.buf.frags[i].map
- This gives exact queue ring buffer DMA addresses.

2. Hot-path queue discovery logic
- On RX/TX hot-path probes, snapshot queue once per queue id.
- This avoids requiring channel reconfiguration every run.

3. Raw DMA capture logic
- On dma_map_page_attrs entry:
  - store pdev and size in thread-local depth-indexed map
- On return:
  - read returned DMA address
  - output pdev, size, dma
- Depth tracking avoids corruption under nested calls.

Kernel code snippets that drove the selection

From RQ open path:
- en_main.c
  int mlx5e_open_rq(...)
  {
      err = mlx5e_alloc_rq(..., rq);
      err = mlx5e_create_rq(rq, param);
      err = mlx5e_modify_rq_state(...);
  }

From SQ open path:
- en_main.c
  int mlx5e_open_txqsq(...)
  {
      err = mlx5e_alloc_txqsq(..., sq, ...);
      err = mlx5e_create_sq_rdy(..., &sq->sqn);
  }

From RX raw DMA write into WQE:
- en_rx.c
  static int mlx5e_alloc_rx_wqe(...)
  {
      addr = page_pool_get_dma_addr(...);
      wqe->data[i].addr = cpu_to_be64(addr + ...);
  }

From TX DMA mapping path:
- en_tx.c
  static inline int mlx5e_txwqe_build_dsegs(...)
  {
      dma_addr = dma_map_single(...);
      ...
      dma_addr = skb_frag_dma_map(...);
  }

What this achieved in your run

- Captured non-zero SQ and RQ ring DMA addresses and page maps from:
  - mlx5_exact_dma_forced2/mlx5_exact_dma_filtered.log
- Captured RAW_DMA_MAP events in the same run and summarized by parser:
  - mlx5_exact_dma_forced2/summary_pdev_dma.txt
  - mlx5_exact_dma_forced2/summary_queue_ring.csv

If you want next, I can add one more refinement: a strict mode in the tracer/parser that discards pdev 0x0 at source so all outputs are only your target mlx5 device.