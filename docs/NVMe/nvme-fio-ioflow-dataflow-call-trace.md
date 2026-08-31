我来追踪完整的 IO 路径。先找到关键的内核 AIO 提交和完成路径代码。  

Searched for regex `SYSCALL_DEFINE|io_submit|aio_complete|aio_read_events` (`**/linux/fs/aio.c`), 30 results

Searched for regex `blk_mq_end_request\b|blk_mq_end_request_batch\b` (`**/linux/block/blk-mq.c`), 12 results

Read [](file:///root/mz/linux/kernel/linux/block/blk-mq.c#1155-1155), lines 1155 to 1200

Read [](file:///root/mz/linux/kernel/linux/fs/aio.c#1117-1117), lines 1117 to 1210

Read [](file:///root/mz/linux/kernel/linux/fs/aio.c#1488-1488), lines 1488 to 1525

Read [](file:///root/mz/linux/kernel/linux/fs/aio.c#1294-1294), lines 1294 to 1360

Searched for regex `nvme_try_complete_req\(` (`**/linux/drivers/nvme/host/**`), 7 results

Read [](file:///root/mz/linux/kernel/linux/drivers/nvme/host/pci.c#1531-1531), lines 1531 to 1560

Read [](file:///root/mz/linux/kernel/linux/drivers/nvme/host/nvme.h#789-789), lines 789 to 825

现在所有关键节点都已确认。下面是完整的 IO 生命周期描述。

---

## fio + libaio 读写 NVMe 盘：完整 IO 生命周期

---

### 第一阶段：提交路径 (fio thread 上下文)

```
┌─────────────────────────────────────────────────────────────────────────┐
│ fio thread (用户态)                                                      │
│                                                                         │
│ 1. fio engine: td_io_queue() → libaio engine → io_prep_pread/write()    │
│    填充 struct iocb (fd, buf, len, offset)                              │
│                                                                         │
│ 2. io_submit(ctx, nr, &iocbs[])  ← libaio 库封装的 syscall              │
└──────────────────────────────────┬──────────────────────────────────────┘
                                   │ syscall 进入内核
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 内核 AIO 层 (fs/aio.c)                                                  │
│                                                                         │
│ 3. SYSCALL_DEFINE3(io_submit) → io_submit_one()                         │
│    分配 struct aio_kiocb                                                │
│    设置 kiocb->ki_complete = aio_complete_rw  ← 完成回调!               │
│                                                                         │
│ 4. 对于 O_DIRECT 块设备:                                                │
│    → aio_read/aio_write → blkdev_read_iter/blkdev_write_iter            │
│    → blkdev_direct_IO → blkdev_bio_end_io 设为 end callback             │
│    → submit_bio()                                                       │
└──────────────────────────────────┬──────────────────────────────────────┘
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Block Layer (block/)                                                     │
│                                                                         │
│ 5. submit_bio() → blk_mq_submit_bio()                                   │
│    → blk_mq_get_request() 分配 struct request (从 tag 池)               │
│    → 设 rq->end_io (bio→rq 的完成链)                                    │
│    → blk_mq_run_hw_queue() → __blk_mq_issue_directly()                 │
│    → nvme_mq_ops.queue_rq = nvme_queue_rq()                            │
└──────────────────────────────────┬──────────────────────────────────────┘
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ NVMe PCI Driver (drivers/nvme/host/pci.c)                               │
│                                                                         │
│ 6. nvme_queue_rq()                                                      │
│    → nvme_prep_rq(): 构造 NVMe command (SQE), DMA map                  │
│    → nvme_sq_copy_cmd(): 复制 SQE 到 SQ ring buffer                    │
│    → nvme_write_sq_db(): writel() 写 SQ doorbell → 通知 NVMe 控制器    │
│                                                                         │
│ 7. io_submit() syscall 返回 → fio thread 回到用户态                     │
└─────────────────────────────────────────────────────────────────────────┘
```

---

### 第二阶段：fio thread 在 submit 之后的状态

```
fio thread 回到用户态后:

1. 继续 submit 更多 IO (iodepth 未满时)
2. 当 iodepth 满 或 需要等 completion 时，调用:
   io_getevents(ctx, min_nr, max_nr, events[], timeout)
   
3. 内核侧 → read_events() (fs/aio.c:1313)
   → prepare_to_wait_event(&ctx->wait, TASK_INTERRUPTIBLE)
   → aio_read_events(): 检查 AIO ring buffer 的 tail vs head
   → 如果没有完成事件: schedule() ← fio thread 进入 SLEEP!
   
4. 此时 fio thread 状态:
   - 进程状态: TASK_INTERRUPTIBLE
   - 被挂在 ctx->wait 等待队列上
   - 不消耗 CPU，等待被唤醒
```

---

### 第三阶段：硬件完成 + 中断响应

```
┌─────────────────────────────────────────────────────────────────────────┐
│ NVMe Controller (硬件)                                                   │
│                                                                         │
│ 1. 控制器处理完 command                                                  │
│ 2. DMA write CQE 到 host memory 的 CQ ring                             │
│ 3. 发送 MSI-X interrupt 到对应 CPU                                      │
└──────────────────────────────────┬──────────────────────────────────────┘
                                   ▼ (硬中断)
┌─────────────────────────────────────────────────────────────────────────┐
│ NVMe IRQ Handler (pci.c:1599, 在中断上下文)                              │
│                                                                         │
│ nvme_irq(irq, data)                                                     │
│  └→ nvme_poll_cq(nvmeq, &iob)                                          │
│      └→ while (nvme_cqe_pending()):   ← 检查 CQE phase bit             │
│          └→ nvme_handle_cqe(nvmeq, &iob, cq_head)                      │
│              ├→ req = nvme_find_rq(tags, command_id) 找到原 request      │
│              ├→ nvme_try_complete_req(req, status, result)               │
│              │   └→ blk_mq_complete_request_remote(req)                  │
│              │       └→ cpus_share_cache() 判断是否需要 IPI              │
│              │       └→ 通常返回 false (本地完成)                         │
│              └→ blk_mq_add_to_batch(req, iob, ...) 加入 batch           │
│                                                                         │
│  └→ nvme_pci_complete_batch(&iob)                                       │
│      └→ nvme_complete_batch(iob, nvme_pci_unmap_rq)                     │
│          └→ 对每个 req: nvme_pci_unmap_rq() + nvme_complete_batch_req() │
│          └→ blk_mq_end_request_batch(iob)                               │
└──────────────────────────────────┬──────────────────────────────────────┘
                                   ▼
```

---

### 第四阶段：从 block layer 回到 AIO 层，唤醒 fio

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Block Layer 完成路径 (仍在中断上下文)                                     │
│                                                                         │
│ blk_mq_end_request_batch() / blk_mq_end_request()                       │
│  └→ blk_update_request() → 更新 bio 已完成字节                          │
│  └→ __blk_mq_end_request()                                             │
│      └→ rq->end_io(rq, error) ← 调 bio 层设置的回调                    │
│          └→ bio->bi_end_io(bio) = blkdev_bio_end_io()                   │
└──────────────────────────────────┬──────────────────────────────────────┘
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 文件系统/块设备 Direct IO 完成                                           │
│                                                                         │
│ blkdev_bio_end_io()                                                     │
│  └→ kiocb->ki_complete(kiocb, result)                                   │
│      = aio_complete_rw()        ← 在 aio_prep_rw() 时注册的回调!        │
└──────────────────────────────────┬──────────────────────────────────────┘
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ AIO 完成路径 (fs/aio.c, 仍可能在中断上下文)                              │
│                                                                         │
│ aio_complete_rw()                                                       │
│  └→ iocb->ki_res.res = result   (记录结果)                              │
│  └→ iocb_put(iocb)                                                     │
│      └→ aio_complete(iocb)                                              │
│          ├→ spin_lock_irqsave(&ctx->completion_lock)                    │
│          ├→ 写 io_event 到 AIO ring buffer (mmap 共享内存)              │
│          │   event->obj = iocb 地址                                     │
│          │   event->data = 用户 data                                    │
│          │   event->res = 字节数 或 错误码                               │
│          ├→ ring->tail = new_tail  ← 用户态可见!                        │
│          ├→ smp_wmb()                                                   │
│          ├→ eventfd_signal() (如果设了 IOCB_FLAG_RESFD)                  │
│          └→ wake_up_process(waiter)  ← 唤醒 fio thread!                 │
│             (检查 ctx->wait 队列，找到等待的 fio thread)                  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

### 第五阶段：fio thread 被唤醒，收割完成事件

```
┌─────────────────────────────────────────────────────────────────────────┐
│ fio thread 被唤醒 (回到 TASK_RUNNING)                                    │
│                                                                         │
│ read_events() 中的 schedule() 返回                                      │
│  └→ aio_read_events_ring()                                              │
│      └→ 从 AIO ring buffer 读取 io_event (head..tail 之间)              │
│      └→ copy_to_user() 复制到 fio 用户态 events[] 数组                  │
│                                                                         │
│ io_getevents() syscall 返回                                             │
│  └→ fio 收到完成的 event 数量和结果                                      │
│  └→ fio engine: fio_libaio_event() 处理每个 completion                  │
│  └→ 更新统计(latency/IOPS/BW) → 可以 submit 新 IO                      │
└─────────────────────────────────────────────────────────────────────────┘
```

---

### 核心问答：IRQ 如何与 fio thread 对接

**fio thread 在 submit 之后是什么状态？**  
- 如果 iodepth 未满：继续提交更多 IO，处于 TASK_RUNNING
- 如果调用了 `io_getevents(min_nr>0)` 等待完成：进入 `TASK_INTERRUPTIBLE`，挂在 `ctx->wait` 等待队列上

**NVMe IRQ 如何找到 fio thread？**  
不是直接找的。链路是：
```
IRQ → CQE → request → bio → kiocb → aio_kiocb → kioctx → ctx->wait → fio thread
```

对接机制是 **AIO ring buffer + 等待队列**：
1. IRQ handler 把完成事件写入 AIO ring buffer（`ring->tail++`）
2. 检查 `ctx->wait` 等待队列是否有 waiter
3. 如果有且满足 `min_nr` 条件 → `wake_up_process(fio_thread)`
4. fio thread 被调度器恢复运行，从 `schedule()` 处继续
5. fio thread 从 ring buffer 读取已完成的 events

**关键点：** fio thread 和 IRQ handler 之间的同步媒介是 **mmap 的 AIO ring buffer**（lock-free 的生产者-消费者模型）。IRQ 是生产者写 tail，fio thread 是消费者读 head→tail。唤醒操作 `wake_up_process()` 只是通知 fio "有新数据了"，实际数据传递通过共享内存完成。