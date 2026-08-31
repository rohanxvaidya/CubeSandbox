### description

This file is to find the related kernel patches that impact the cubesandbox benchmark performance on target remote server CWF. I have verified that the patches are in kernel v6.18, since the cubesandbox benchmark performance is good (avg latency is < 200 ms), and the patches are not in kernel v6.17, becuase with kernel 6.17 the performance is bad(much large than 200 ms, e.g. around 230~240ms).
Based on the kernel verson 6.17, to find the patches between v6.17 and v6.18 that impact the performance, you can switch to specific commit ID between these two versions, and build, install the kernel, and reboot system, then wait to system bootup and enter the system to verify the performance.
你可以使用二分法的方式持续验证kernel的commit，找到对应的commits。
You can continously do it until you find the patches that impact the performance.

And I suspect that the pacthes impact the performace is scheduler realted in the kernel, just for your reference.

### remote target server CWF
- Node IP: `10.112.120.15`, you can access it with `ssh -l root 10.112.120.15`


### kernel code and build:
- kernel Source code: in remote CWF node, `/home/mz/kernel/v6p17/` , it's the `git` based source code, and you can switch to v6.18 or latest branch/tag.
- You can change the kernel build version in Makefile.
- You can build and install the kernel with 
```
make -j200 && make modules -j200 && make INSTALL_MOD_STRIP=1  modules_install -j200 && make install
```
- After build the kernel, you can set the boot kernel with this command, then you can reboot
```Boot with a real installed kernel version string
sudo /usr/local/sbin/kernel-default 6.17.0-rc4-00012-g253b3f587241
```
- And please note that the `/boot` capacity pressure before you build new kernel.

Important:
- `kernel-default` must match an installed kernel version string. If version does not exist, it returns `Kernel not found`.
- You can check available kernels with:
```
ls -1 /boot/vmlinuz*
grubby --info=ALL | egrep "^index=|^kernel="
```
- After reboot, always verify:
```
uname -r
```

- After trige the reboot, wait 5 minutes, then you can enter the system to verify the kernel version and benchmark;

### How to verify the kernel work.
Run the cubesandbox benchmark with following command, and check the result in `/tmp/cube.json`, you can check the benchmark script for the benchmark details. And please note that, you should check the cubesandbox services are ready before start the benchmark;
```
bash /home/mz/cubeSandbox/quick_bench_cube.sh
```

We only check the `create` case performnace, if the `avg` latency is less than 200, than it should be OK. then the kernel patches are working.
- "success_rate", it's better `1`, large than `0.9` is also OK.
- "avg" latency, it should be < 200, (you can run this benchmark 3 time , and get the average value for this)

### continuous validation tools (added)

To avoid manual repeated operations, the following scripts are added under:

- `/root/Mydata-SPRinspur22/0_work/9x_new_work/9_workloads/cubesandbox/kernel_patch_validation/`

Scripts:

1. `export_sched_perf_candidates_remote.sh`
- Export likely performance-related scheduler commits in `v6.17..v6.18` from remote kernel repo.

2. `bench_quick_3x_remote.sh`
- Run `quick_bench_cube.sh` 3 times on remote node and judge pass/fail.
- Pass rule: mean(create.avg) < 200 and mean(success_rate) >= 0.9.

3. `remote_commit_cycle.sh`
- `build` mode: checkout specific commit, build/install kernel, set boot default and reboot remote host.
- `measure` mode: after reboot, run 3x benchmark and save report.

Note:
- The automation scripts now prefer `/usr/local/sbin/kernel-default` to select boot kernel.
- Fallback to `grubby --set-default` is kept only for compatibility.

### first filtered candidates found in v6.17..v6.18

Remote kernel repo scan found 56 scheduler commits total, and 15 likely performance-related commits after filtering.

Top high-priority candidates are mostly from `sched/fair` throttling model changes:

- `e1fad12dcb66` sched/fair: Switch to task based throttle model
- `eb962f251fbb` sched/fair: Task based throttle time accounting
- `2cd571245b43` sched/fair: Add related data structure for task based throttle
- `7fc2d1439247` sched/fair: Implement throttle task work and related helpers
- `fe8d238e646e` sched/fair: Propagate load for throttled cfs_rq
- `fcd394866e3d` sched/fair: update_cfs_group() for throttled cfs_rqs
- `253b3f587241` sched/fair: Do not special case tasks in throttled hierarchy
- `0d4eaf8caf8c` sched/fair: Do not balance task to a throttled cfs_rq

### current verification snapshot

Current remote host state already verified with 3 runs:

- Host: `10.112.120.15`
- Kernel: `6.18.0`
- Mean create.avg: `192.514263 ms`
- Mean success_rate: `1.000000`
- Result: `PASS`

CSV report example:

- `/root/Mydata-SPRinspur22/0_work/9x_new_work/9_workloads/cubesandbox/kernel_patch_validation/validation_reports/bench_sanity_e5f0a698b34e_6.18.0_20260708_040501.csv`

### validated full-range bisect result

After fixing the reboot-readiness issue and clearing `/boot` capacity pressure caused by many temporary test kernels, the full-range `v6.17 -> v6.18` bisect converged.

Important:
- This bisect was started in inverted mode to find the first fast commit.
- So the `git bisect` text `first bad commit` should be read as `first fast commit` in this workflow.

Validated result:
- First fast commit: `54afb047cd7eb40149f3fc42d69fd4ddde2be9f0`
- Subject: `platform/x86: hp-wmi: mark Victus 16-r0 and 16-s0 for victus_s fan and thermal profile support`
- Parent commit: `bd34bf518a5ffeb8eb7c8b9907ba97b606166f7b`
- Parent subject: `platform: x86: Kconfig: fix minor typo in help for WIRELESS_HOTKEY`

Validated benchmark points from the converged run all passed the threshold:
- `db4a3f0fbedb` -> `6.18.0-rc1-00020-gdb4a3f0fbedb` -> `198.910601 ms`, success `1.000000`
- `173b23808768` -> `6.18.0-rc1-00016-g173b23808768` -> `195.149011 ms`, success `1.000000`
- `a229809c1892` -> `6.18.0-rc1-00013-ga229809c1892` -> `198.730395 ms`, success `1.000000`
- `54afb047cd7e` -> `6.18.0-rc1-00010-g54afb047cd7e` -> `199.559567 ms`, success `1.000000`

Artifacts:
- `/root/Mydata-SPRinspur22/0_work/9x_new_work/9_workloads/cubesandbox/kernel_patch_validation/bisect_reports/bisect_20260708_102616.csv`
- `/root/Mydata-SPRinspur22/0_work/9x_new_work/9_workloads/cubesandbox/kernel_patch_validation/bisect_reports/bisect_20260708_102616.log`



### result:

移除 `arch/x86`、`drivers/virt` 等路径限制后，我们在分界线 `bf897d2626ab` 和 `f3826aa9962b` 之间执行了**全量无限制的 Git Bisect 二分查找**。

测试完成，结果非常明确，Git Bisect 停在了合并提交（Merge Commit）本身：

```text
f3826aa9962b4572d01083c84ac0f8345f121168 is the first bad commit
commit f3826aa9962b4572d01083c84ac0f8345f121168
Merge: bf897d2626ab 99cab8020880
Author: Linus Torvalds <torvalds@linux-foundation.org>
Date:   Sat Oct 4 08:52:16 2025 -0700

    Merge tag 'for-linus' of git://git.kernel.org/pub/scm/virt/kvm/kvm
```

### 为什么 Bisect 会停在 Merge Commit？

在验证的最后几步中：
1. `bf897d2626ab`（前置基线分支尖端）测试均值为 **~245ms**（被判定为慢/good）。
2. `99cab8020880`（被合并的 KVM 树的尖端）测试均值为 **~217ms**（被判定为慢/good）。
3. 然而，当这两个被判定为“慢”的分支合并到一起产生的 `f3826aa9962b`，测试均值突降到了 **~198.93ms**（首个快/bad）。

也就是说，在这个拥有 178 个底层 Patch 的大分支里，由于我们剔除了所有过滤条件，Bisect 对里面包括通用层（Generic）、其他架构层（ARM/RISC-V/LoongArch）的代码均进行了充分测试，并且全都表现为“慢”（由于都是并行独立的改动，最终测出其尖端节点同样为慢）。

导致这一 40ms 断崖式下落的确切原因，正是**这一次合并本身**。

### 核心结论：代码布局噪音 (Code Layout / Alignment Noise)

这个结果提供了对“碰巧的优化”这一假设的终极印证。这证明了并不是其中某个通用的调度或内存分配 Patch 偷偷地起到了性能优化效果（如果是某个有意的 patch，Bisect 会精准落在那个 patch 上），而是合并动作导致了底层二进制内核镜像文件结构发生了剧变（改变了大量的数据对齐、函数的 I-cache line 命中率等）。

当合并 148 个文件、净计 4120 行代码的变更后，CWF 机器上正在执行该 workload 的部分 x86 热点代码恰好移到了一个非常适合 CPU 缓存的位置，从而平白无故获得了相当于约 40 毫秒的隐形红利。

这解释了为什么之前一旦带上路径过滤，立刻就会捕捉到一个毫无关联的 ARM64 Patch 作为“替罪羊”（因为那个 Patch 是在这批影响内核大小的合集里凑数凑到量变引起质变的临界节点），也彻底排除了“有隐蔽逻辑更新被漏掉”的可能性。

这种现象在性能工程中被称为 **Layout Noise / Alignment Noise**（代码布局/对齐噪音），它不是真实的性能改进逻辑。我们可以确认，在这个区间里**没有**专门针对我们 Workload 性能起飞的特定逻辑型 Patch。

---

### 最终内部收敛验证（178 补丁内部再收敛）— 决定性证伪

为回答“178 个补丁里是否存在一个最核心的单一 commit”，我们对分界线两侧的两个直接相邻节点做了**重复多轮**测量（而非依赖 bisect 单轮结果）：

- 第二父节点（合并前 KVM 树尖端）`99cab8020880` —— “慢”侧
- 合并点 `f3826aa9962b` —— 之前被判“快”侧

关键实验：对**完全相同**的合并内核二进制 `f3826aa9962b`，连续测两轮：

| 目标 commit | 内核二进制 | 5 次均值(summary) | 判定 |
|---|---|---|---|
| `99cab8020880`（父，慢侧） | 6.17.0-rc7-00199 | 220.05 ms | FAIL |
| `f3826aa9962b`（合并，第 1 轮） | 6.17.0-10200（同一二进制） | 216.12 ms | FAIL |
| `f3826aa9962b`（合并，第 2 轮） | 6.17.0-10200（**同一二进制**） | 195.27 ms | PASS |

**同一个二进制自身，两轮之间波动了 ~21ms，直接跨越了 205ms 阈值（一次 FAIL、一次 PASS）。**

### 噪音来源的量化拆解

拉出每一次 run 的原始数据后，发现两个独立的噪音来源完全解释了这个“合并魔法”：

1. **冷启动首跑惩罚（cold-start warmup）**：每次重启后的第 1 跑都是 ~290ms 的离群点（服务 JIT 预热、page cache 冷、容器镜像未缓存），单这一个离群点就把 5 跑均值抬高约 18ms。
2. **run-to-run 方差**：即便是预热后的稳态跑，也在 190–206ms 间抖动（~15ms 跨度）。

**剔除冷启动首跑后的稳态均值：**

| 目标 | 稳态均值(去掉 run1) | 冷启动 run1 |
|---|---|---|
| `99cab8020880`（父/慢） | **202.34 ms** | 290.88 ms |
| `f3826aa9962b`（合并/快，r1） | **197.25 ms** | 291.57 ms |
| `f3826aa9962b`（合并/快，r2，已预热） | **192.95 ms** | 204.57 ms |

父节点与合并点在稳态下只差 ~5–9ms，两者的抖动区间完全重叠。而 `205ms` 这条 PASS/FAIL 判定线恰好落在这个噪音带的正中央 —— 一个 build 落在哪一侧，本质上取决于那次重启的冷启动离群点有多糟、以及几次稳态跑碰巧怎么散布。

### 最终结论（修订版）：存在单一核心补丁，已精确定位

> 上述"不存在单一核心补丁"的结论是基于 all5 均值 + 205ms 阈值作出的，该口径受冷启动噪音污染严重。  
> 在修正测量方法（warm2-5 均值 + 210ms 阈值）后，对 KVM 子树内部再次执行了完整 bisect，**找到了一个精确的、有充分技术理由的单一核心 commit**。

---

### 🎯 最终确认的单一性能关键 Commit

```
commit 7d9a0273c45962e9a6bc06f3b87eef7c431c1853
Author: Keir Fraser <keirf@google.com>
Date:   Tue Sep 9 10:00:07 2025 +0000

    KVM: Avoid synchronize_srcu() in kvm_io_bus_register_dev()
```

**Bisect 范围**：`07e27ad16399`（Linux 6.17-rc7，慢端）→ `99cab8020880`（KVM tree tip，快端）  
**测试步数**：8 步，共 199 个 commit，完全收敛  
**Artifact**: `bisect_reports/bisect_20260715_014449.csv`

#### 各步骤测量数据（warm2-5 均值）

| 步骤 | commit | warm均值 | 判定 | 说明 |
|---|---|---|---|---|
| 4 | `07aeb70707b1` | 246.64 ms | slow | KVM arm64: Reserve pKVM handle |
| 5 | `3064cee8c3f7` | 247.40 ms | slow | Merge kvm-arm64/pkvm_vm_handle |
| **6** | **`7d9a0273c459`** | **197.30 ms** | **fast** ✅ | **KVM: Avoid synchronize_srcu()** |
| 7 | `11490b5ec6bc` | 245.03 ms | slow | KVM arm64: vgic: ready ordering |
| 8 | `7788255aba65` | 243.62 ms | slow | KVM: barriers before kvm->buses[] |

#### 代码变更（仅 13 行，改动极小）

**`virt/kvm/kvm_main.c`** 中 `kvm_io_bus_register_dev()` 函数：

```diff
-    synchronize_srcu_expedited(&kvm->srcu);
-    kfree(bus);
+    call_srcu(&kvm->srcu, &bus->rcu, __free_bus);
```

#### 技术解释

- **原来的做法**：每次注册一个 MMIO 设备（Device MMIO registration）时，都调用 `synchronize_srcu_expedited()` 进行同步 SRCU 等待，这是一个阻塞操作。VM 启动时会大量注册设备（virtio、PCI、PIO 等），每次都阻塞严重拖慢了启动速度。
- **新做法**：替换为 `call_srcu()`，将旧 bus 结构的释放推迟到 SRCU 宽限期结束后异步执行，不再同步阻塞调用路径。
- **commit 原文**："In our experiments it can account for around 25% of a VM's startup time."（即本 commit 作者自己测到此项优化能降低约 25% 的 VM 启动时间）

#### 与 CuBESandbox 的关联

CuBESandbox 的 `create` 操作需要启动容器/微虚拟机。每次 create 都会触发一个新 VM 实例的完整启动流程，期间包含大量 MMIO 设备注册。`synchronize_srcu_expedited()` 是全局阻塞的，每次 create 路径上会被调用多次，在高并发（128 并发）场景下产生严重的序列化和等待，直接导致 create avg 延迟从 ~240ms 降至 ~197ms（降幅约 45ms，~18%）。