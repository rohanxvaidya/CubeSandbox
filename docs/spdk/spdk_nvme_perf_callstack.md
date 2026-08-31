# SPDK PCIe NVMe I/O Submit + Poll Completion Callstack (perf 示例)

本文以 `examples/nvme/perf/perf.c` 为入口，梳理 SPDK 在 PCIe NVMe 场景下的：

- I/O 提交路径（submit）
- completion 轮询路径（polling completion）
- transport 分发与 PCIe 绑定点
- `nvme_pcie_qpair_submit_request()` 内部 PRP/SGL 构建细节

---

## 1. 为什么会走到 PCIe transport

### 1.1 PCIe transport 注册

- `pcie_ops` 定义：`lib/nvme/nvme_pcie.c#L1062`
- 注册动作：`lib/nvme/nvme_pcie.c#L1110` (`SPDK_NVME_TRANSPORT_REGISTER(pcie, &pcie_ops)`)

`pcie_ops` 里挂载了关键函数指针，包括：

- `ctrlr_construct = nvme_pcie_ctrlr_construct`
- `ctrlr_create_io_qpair = nvme_pcie_ctrlr_create_io_qpair`
- `qpair_submit_request = nvme_pcie_qpair_submit_request`
- `qpair_process_completions = nvme_pcie_qpair_process_completions`
- `poll_group_process_completions = nvme_pcie_poll_group_process_completions`

### 1.2 控制器构造分发

- 通用入口：`lib/nvme/nvme_transport.c#L99` (`nvme_transport_ctrlr_construct`)
- PCIe 构造：`lib/nvme/nvme_pcie.c#L875` (`nvme_pcie_ctrlr_construct`)
- Admin qpair 构造：`lib/nvme/nvme_pcie_common.c#L237` (`nvme_pcie_ctrlr_construct_admin_qpair`)

### 1.3 IO qpair 创建与连接

- perf 侧创建 qpair：`examples/nvme/perf/perf.c#L971` (`nvme_init_ns_worker_ctx`)
- 通用 alloc：`lib/nvme/nvme_ctrlr.c#L449` (`spdk_nvme_ctrlr_alloc_io_qpair`)
- 通用 create：`lib/nvme/nvme_ctrlr.c#L361` (`nvme_ctrlr_create_io_qpair`)
- transport create 分发：`lib/nvme/nvme_transport.c#L415` (`nvme_transport_ctrlr_create_io_qpair`)
- PCIe create：`lib/nvme/nvme_pcie_common.c#L1047` (`nvme_pcie_ctrlr_create_io_qpair`)
- connect：`lib/nvme/nvme_ctrlr.c#L419` (`spdk_nvme_ctrlr_connect_io_qpair`)
- PCIe connect：`lib/nvme/nvme_pcie_common.c#L568` (`nvme_pcie_ctrlr_connect_qpair`)

> perf 默认将 qpair `create_only=true` 且 `delay_cmd_submit=true`（见 `examples/nvme/perf/perf.c` 内 qpair opts 配置）。

---

## 2. I/O submit 完整调用链（以 read/write 为例）

### 2.1 perf 层

1. `examples/nvme/perf/perf.c#L1554` `submit_io`
2. `examples/nvme/perf/perf.c#L1421` `submit_single_io`
3. `examples/nvme/perf/perf.c#L824` `nvme_submit_io`

`nvme_submit_io` 中根据请求类型调用：

- `spdk_nvme_ns_cmd_read_with_md` (`lib/nvme/nvme_ns_cmd.c#L617`)
- `spdk_nvme_ns_cmd_write_with_md` (`lib/nvme/nvme_ns_cmd.c#L914`)
- 或 readv/writev 带 md 版本

### 2.2 namespace 命令封装层

4. `lib/nvme/nvme_ns_cmd.c#L384` `_nvme_ns_cmd_rw`

职责：

- 分配 `nvme_request`
- 必要时做 split（跨 stripe、超过 max io、SGL/PRP 约束）
- 设置 NVMe cmd 字段（`_nvme_ns_cmd_setup_request`，`lib/nvme/nvme_ns_cmd.c#L143`）

### 2.3 通用 qpair 层

5. `lib/nvme/nvme_qpair.c#L1063` `nvme_qpair_submit_request`
6. `lib/nvme/nvme_qpair.c#L921` `_nvme_qpair_submit_request`

职责：

- qpair state 检查
- 队列化/重提交流程（`-EAGAIN` 时进入 queued_req）
- 进入 transport 分发

### 2.4 transport 分发到 PCIe

7. `lib/nvme/nvme_transport.c#L591` `nvme_transport_qpair_submit_request`
8. `lib/nvme/nvme_pcie_common.c#L1633` `nvme_pcie_qpair_submit_request`

### 2.5 PCIe 侧提交到 SQ + doorbell

9. `lib/nvme/nvme_pcie_common.c#L630` `nvme_pcie_qpair_submit_tracker`
10. `lib/nvme/nvme_pcie_internal.h#L246` `nvme_pcie_qpair_ring_sq_doorbell`

最终 doorbell 通过 `spdk_mmio_write_4` 写 SQ tail。

---

## 3. Completion polling 完整调用链（perf + poll group）

### 3.1 perf 主循环

1. `examples/nvme/perf/perf.c#L926` `nvme_check_io`
2. `lib/nvme/nvme_poll_group.c#L118` `spdk_nvme_poll_group_process_completions`

### 3.2 poll group 分发

3. `lib/nvme/nvme_transport.c#L710` `nvme_transport_poll_group_process_completions`
4. `lib/nvme/nvme_pcie_common.c#L1756` `nvme_pcie_poll_group_process_completions`
5. 对每个 connected qpair 调 `spdk_nvme_qpair_process_completions`

### 3.3 qpair completion 通用层 + PCIe 层

6. `lib/nvme/nvme_qpair.c#L749` `spdk_nvme_qpair_process_completions`
7. `lib/nvme/nvme_transport.c#L605` `nvme_transport_qpair_process_completions`
8. `lib/nvme/nvme_pcie_common.c#L840` `nvme_pcie_qpair_process_completions`
9. `lib/nvme/nvme_pcie_common.c#L675` `nvme_pcie_qpair_complete_tracker`
10. `lib/nvme/nvme_pcie_internal.h#L275` `nvme_pcie_qpair_ring_cq_doorbell`

### 3.4 回调到 perf 并补提下一条

11. `examples/nvme/perf/perf.c#L1513` `io_complete`
12. `examples/nvme/perf/perf.c#L1469` `task_complete`
13. `examples/nvme/perf/perf.c#L1421` `submit_single_io`（非 draining 时）

形成 steady-state 闭环：完成一条 -> 回调 -> 立即补一条。

---

## 4. `nvme_pcie_qpair_submit_request()` 内部 PRP/SGL 构建细节

### 4.1 主函数框架

入口：`lib/nvme/nvme_pcie_common.c#L1633`

关键步骤：

1. 从 `free_tr` 取 tracker；没有则 `-EAGAIN`
2. 绑定 `tr->req/cb/cid`，放入 `outstanding_tr`
3. 根据控制器能力决定 `sgl_supported`
4. 根据 payload 类型 + `sgl_supported` 从函数表选构建器
5. 构建 metadata（如果有）
6. 调 `nvme_pcie_qpair_submit_tracker` 写 SQ

### 4.2 分支选择逻辑（核心）

函数表：`lib/nvme/nvme_pcie_common.c#L1574`

- `NVME_PAYLOAD_TYPE_CONTIG + PRP` -> `nvme_pcie_qpair_build_contig_request`
- `NVME_PAYLOAD_TYPE_CONTIG + SGL` -> `nvme_pcie_qpair_build_contig_hw_sgl_request`
- `NVME_PAYLOAD_TYPE_SGL + PRP` -> `nvme_pcie_qpair_build_prps_sgl_request`
- `NVME_PAYLOAD_TYPE_SGL + SGL` -> `nvme_pcie_qpair_build_hw_sgl_request`

payload 类型判定：`lib/nvme/nvme_internal.h#L259`（`reset_sgl_fn` 存在则视为 SGL）。

### 4.3 PRP 构建细节

#### 4.3.1 通用 PRP append 例程

`nvme_pcie_prp_list_append`：`lib/nvme/nvme_pcie_common.c#L1200`

行为要点：

- 首个条目写 `cmd->dptr.prp.prp1`
- 后续页地址写入 `tr->u.prp[]`
- 每个后续 PRP 必须页对齐
- `cmd->psdt = SPDK_NVME_PSDT_PRP`
- `prp2` 规则：
  - 只有 1 个 PRP：`prp2 = 0`
  - 2 个 PRP：`prp2 = tr->u.prp[0]`
  - 大于 2：`prp2 = tr->prp_sgl_bus_addr`（指向 PRP list）

失败条件示例：

- 虚拟地址非 dword 对齐
- `vtophys` 失败
- PRP 数量超限
- 后续 PRP 非页对齐

#### 4.3.2 contiguous payload + PRP

`nvme_pcie_qpair_build_contig_request`：`lib/nvme/nvme_pcie_common.c#L1288`

- 直接一次 `nvme_pcie_prp_list_append`
- 输入地址是 `payload_base + payload_offset`

#### 4.3.3 SGL payload + PRP

`nvme_pcie_qpair_build_prps_sgl_request`：`lib/nvme/nvme_pcie_common.c#L1523`

- 通过 `reset_sgl_fn/next_sge_fn` 逐段取用户 SGE
- 每个 SGE 片段再 append 到 PRP list
- 对非最后一个 SGE，断言必须页边界结束（split 阶段应已保障）

### 4.4 SGL 构建细节

#### 4.4.1 contiguous payload + HW SGL

`nvme_pcie_qpair_build_contig_hw_sgl_request`：`lib/nvme/nvme_pcie_common.c#L1311`

行为：

- `cmd.psdt = SPDK_NVME_PSDT_SGL_MPTR_CONTIG`
- 按 `vtophys` 返回的映射长度切段，生成 `DATA_BLOCK` 描述符
- 若最终 `nseg == 1`：直接把唯一描述符写入 `cmd.dptr.sgl1`（不依赖 tracker SGL 数组）
- 若 `nseg > 1`：`sgl1.type = LAST_SEGMENT`，`sgl1.address = tr->prp_sgl_bus_addr`

#### 4.4.2 SGL payload + HW SGL

`nvme_pcie_qpair_build_hw_sgl_request`：`lib/nvme/nvme_pcie_common.c#L1389`

行为：

- 遍历用户 SGE
- 支持 READ 的 Bit Bucket descriptor（`virt_addr == UINT64_MAX`）
- 对连续物理地址进行 descriptor 合并，减少 SGL 数量
- 同样按 `nseg == 1` 与 `nseg > 1` 两种方式写 `sgl1`

### 4.5 metadata 构建细节

`nvme_pcie_qpair_build_metadata`：`lib/nvme/nvme_pcie_common.c#L1590`

- 有 metadata 时检查 dword 对齐（按控制器能力）
- `sgl_supported && dword_aligned`：
  - `cmd.psdt` 从 `SGL_MPTR_CONTIG` 改成 `SGL_MPTR_SGL`
  - 构建 `tr->meta_sgl`
  - `cmd.mptr` 指向 tracker 中 metadata SGL descriptor 位置
- 否则：`cmd.mptr` 直接填 metadata 物理地址（PRP 风格）

### 4.6 失败处理路径

- 任意构建失败会走 `nvme_pcie_fail_request_bad_vtophys`：`lib/nvme/nvme_pcie_common.c#L1174`
- 在 completion context 外：标记 pending failure，延后完成
- 在 completion context 内：手工以 `INVALID_FIELD` 完成该请求

---

## 5. 与 perf 选项相关的行为补充

### 5.1 delay_cmd_submit

- 当 qpair 设置 `delay_cmd_submit=true` 时，`nvme_pcie_qpair_submit_tracker` 不立即敲 SQ doorbell。
- 在 `nvme_pcie_qpair_process_completions` 尾部检测 `last_sq_tail != sq_tail` 时批量 doorbell。

### 5.2 create_only

- `spdk_nvme_ctrlr_alloc_io_qpair` 仅创建 qpair 对象，不自动 connect。
- perf 先 `spdk_nvme_poll_group_add` 再 `spdk_nvme_ctrlr_connect_io_qpair`，便于按 poll group 管理。

---

## 6. 一图式总结（文本）

Submit:

`perf submit_single_io`
-> `nvme_submit_io`
-> `spdk_nvme_ns_cmd_*`
-> `_nvme_ns_cmd_rw`
-> `nvme_qpair_submit_request`
-> `nvme_transport_qpair_submit_request`
-> `nvme_pcie_qpair_submit_request`
-> `build PRP/SGL + metadata`
-> `nvme_pcie_qpair_submit_tracker`
-> `ring SQ doorbell`

Completion:

`perf nvme_check_io`
-> `spdk_nvme_poll_group_process_completions`
-> `nvme_pcie_poll_group_process_completions`
-> `spdk_nvme_qpair_process_completions`
-> `nvme_pcie_qpair_process_completions`
-> `nvme_pcie_qpair_complete_tracker`
-> `io_complete/task_complete`
-> `submit_single_io` (补提)

