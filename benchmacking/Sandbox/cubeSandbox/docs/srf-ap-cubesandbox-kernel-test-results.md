# SRF-AP CubeSandbox Kernel Patch Validation Results

Date: 2026-08-24

## Summary

This document summarizes all kernel versions and patch checkpoints tested on remote SRF/CWF machine `10.239.23.60` for CubeSandbox create latency.

The benchmark used throughout this validation was:

```bash
cd /home/mz/cubeSandbox
C=200 bash /home/mz/cubeSandbox/quick_bench_cube.sh tpl-3cbb2ac9d8054411af13cb74
```

The benchmark writes results to `/tmp/cube.json`. The main pass/fail metric is `create.avg`:

- Pass / fast: `create.avg < 200 ms`, with `summary.success_rate = 1` preferred.
- Fail / slow: `create.avg >= 200 ms`.

Final conclusion: the decisive candidate is:

```text
8394b32faecd irqbypass: Use xarray to track producers and consumers
```

This patch changes KVM irqbypass producer/consumer lookup from global list scanning to `xarray` lookup keyed by `eventfd`, removing an O(n) registration path that is hit heavily by CubeSandbox create under high concurrency.

## Tested kernel results

| Order | Commit / checkpoint | Kernel release / label | Area | create avg (ms) | success rate | Result | Notes |
|---:|---|---|---|---:|---:|---|---|
| 1 | `v6.16` | `6.16.0` | Baseline | 439.854 | 1 | Slow | Confirms 6.16 reproduces bad create latency at C=200. |
| 2 | `bf76f23aa1c1` | `6.16.0-schedcore-04142-gbf76f23aa1c1` | `sched-core-2025-07-28` | 471.822 | 1 | Slow | Scheduler merge alone is not sufficient. |
| 3 | `8be4d31cb8aa` | `6.16.0-netnext-06351-g8be4d31cb8aa` | `net-next-6.17` | 471.374 | 1 | Slow | Network merge alone is not sufficient. |
| 4 | `d9104cec3e8f` | `6.16.0-bpfnext-06574-gd9104cec3e8f` | `bpf-next-6.17` | 488.385 | 1 | Slow | BPF merge alone is not sufficient. |
| 5 | `v6.17` | `6.17.0` | Full 6.17 sanity | 136.975 | 1 | Fast | Confirms full 6.17 is good in the current environment. |
| 6 | `6aee5aed2edd` | `6.16.0-cgroup-10325-g6aee5aed2edd` | `cgroup-for-6.17` first-parent checkpoint | 127.110 | 1 | Fast | First coarse checkpoint after BPF that was fast. |
| 7 | `af5b2619a89d` | `6.16.0-wq-10308-gaf5b2619a89d` | `wq-for-6.17` first-parent checkpoint | 134.656 | 1 | Fast | Fast; used as another upper bound. |
| 8 | `beace86e61e4` | `6.16.0-mm-10300-gbeace86e61e4` | `mm-stable` first-parent checkpoint | 131.793 | 1 | Fast | Fast; confirms improvement is before or at this checkpoint. |
| 9 | `4522ae2def5a` | `mid20` | First-parent bisect checkpoint, `ubifs` area | 123.368 | 1 | Fast | Bisect between BPF and MM. |
| 10 | `d50b07d05ca5` | `mid10` | First-parent bisect checkpoint, trace-ringbuffer area | 486.029 | 1 | Slow | Still slow before KVM merge. |
| 11 | `260f6f4fda93` | `mid15` | First-parent bisect checkpoint, `drm-next` area | 133.180 | 1 | Fast | Fast, narrowed boundary earlier. |
| 12 | `2be6a7503d32` | `mid12` | First-parent bisect checkpoint, trace-unused area | 482.245 | 1 | Slow | Still slow. |
| 13 | `7d767a9528f6` | `mid13` | First-parent bisect checkpoint, `xen/tip` area | 455.886 | 1 | Slow | Last slow mainline-side anchor before KVM merge. |
| 14 | `63eb28bb1402` | `mid14` | `KVM for-linus` mainline merge | 130.317 | 1 | Fast | First fast mainline boundary; points to KVM merge. |
| 15 | `867347bb21e1` + `0d09582b3a60` on slow anchor | `6.16.0-waitqtest-06811-g6a21e338bad8` | waitqueue-only test | 483.186 | 1 | Slow | Waitqueue changes are not sufficient. |
| 16 | `196d9e72c4b0` | `6.16.0-kvmtree-00369-g196d9e72c4b0` | KVM tree tip / second parent of KVM merge | 125.594 | 1 | Fast | Confirms improvement is inside KVM tree. |
| 17 | `65164fd0f6b5` | `6.16.0-kvmriscv-00021-g65164fd0f6b5` | KVM tree first-parent #1, `kvm-riscv-6.17-2` | 417.979 | 1 | Slow | Slow KVM-tree lower bound. |
| 18 | `f02b1bcc73a1` | `6.16.0-kvmirq-00123-gf02b1bcc73a1` | KVM tree first-parent #2, `kvm-x86-irqs-6.17` | 142.015 | 1 | Fast | First fast KVM-tree boundary. |
| 19 | cumulative through `8394b32faecd` | `6.16.0-irqbpxa-00028-g94cbb952418d` | irqbypass xarray candidate series | 127.412 | 1 | Fast | Slow KVM parent plus xarray series is sufficient to recover performance. |
| 20 | `0707ddf4fc82` | `6.16.0-prexa-00027-g0707ddf4fc82` | pre-xarray cumulative point | 249.520 | 1 | Slow | Direct boundary test: still fails before `8394b32faecd`. |

For the last pre-xarray boundary test, additional percentiles were captured:

| Kernel | create p50 (ms) | create p95 (ms) | create p99 (ms) |
|---|---:|---:|---:|
| `6.16.0-prexa-00027-g0707ddf4fc82` | 241.247 | 465.899 | 557.448 |

## Narrowing path

1. The original suspected areas were scheduler, network, eBPF, cgroup, and KVM/irqfd.
2. `sched-core`, `net-next`, and `bpf-next` were each slow when tested on top of the 6.16 base.
3. A later coarse checkpoint, `cgroup-for-6.17`, was fast, so the search moved to first-parent checkpoints between `bpf-next` and that fast region.
4. First-parent bisect identified:
   - Last slow checkpoint: `7d767a9528f6` (`xen/tip` merge), create avg 455.886 ms.
   - First fast checkpoint: `63eb28bb1402` (`KVM for-linus` merge), create avg 130.317 ms.
5. KVM tree isolation then identified:
   - Slow KVM-tree lower bound: `65164fd0f6b5`, create avg 417.979 ms.
   - Fast KVM-tree boundary: `f02b1bcc73a1` (`kvm-x86-irqs-6.17`), create avg 142.015 ms.
6. Inside `kvm-x86-irqs-6.17`, the irqbypass xarray series was tested directly:
   - Pre-xarray cumulative point `0707ddf4fc82`: slow, create avg 249.520 ms.
   - Cumulative point including `8394b32faecd`: fast, create avg 127.412 ms.

This makes `8394b32faecd` the strongest tested patch candidate.

## Key patch analysis

### `8394b32faecd irqbypass: Use xarray to track producers and consumers`

The commit message states that irqbypass previously had O(2n) insertion time because it walked lists to:

- check for duplicate producer/consumer entries;
- search for a matching partner.

It replaces the list-based tracking with `xarray`. The important behavioral change is:

```c
index = (unsigned long)eventfd;
ret = xa_insert(&producers, index, producer, GFP_KERNEL);
consumer = xa_load(&consumers, index);
producer->eventfd = eventfd;
```

Compared with the old pattern:

```c
list_for_each_entry(tmp, &producers, node) ...
list_for_each_entry(consumer, &consumers, node) ...
list_add(&producer->node, &producers);
```

CubeSandbox create appears to create many KVM irqfd/eventfd/irqbypass objects under high concurrency. With list scanning, create latency grows badly as the number of producers/consumers increases. With xarray lookup, registration avoids the O(n) scan and the C=200 create latency falls back into the 6.17-level range.

## Related but less likely patches

These patches were analyzed as part of the `kvm-x86-irqs-6.17` area and are related, but the direct boundary test points most strongly to `8394b32faecd`:

- `283ed5001d68 KVM: Use a local struct to do the initial vfs_poll() on an irqfd`
- `140768a7bf03 KVM: Acquire SRCU lock outside of irqfds.lock during assignment`
- `5f8ca05ea991 KVM: Add irqfd to KVM's list via the vfs_poll() callback`
- `86e00cd162a7 KVM: Add irqfd to eventfd's waitqueue while holding irqfds.lock`
- `2cdd64cbf990 KVM: Disallow binding multiple irqfds to an eventfd with a priority waiter`
- `b599d44a71f1` irqfd/eventfd follow-up in the same area

The waitqueue-only test was slow, so waitqueue changes alone should not be considered the root cause.

## Machine state after validation

After the final boundary validation, the remote machine was restored to:

```text
6.17.0
```

No CubeSandbox workload files or service logic were modified.



## backup
##### major patch:
```
commit f02b1bcc73a17602903480562571069f0dff9f24
Merge: 65164fd0f6b5 81bf24f1ac77
Author: Paolo Bonzini <pbonzini@redhat.com>
Date:   Mon Jul 28 11:03:04 2025 -0400

    Merge tag 'kvm-x86-irqs-6.17' of https://github.com/kvm-x86/linux into HEAD

    KVM IRQ changes for 6.17

     - Rework irqbypass to track/match producers and consumers via an xarray
       instead of a linked list.  Using a linked list leads to O(n^2) insertion
       times, which is hugely problematic for use cases that create large numbers
       of VMs.  Such use cases typically don't actually use irqbypass, but
       eliminating the pointless registration is a future problem to solve as it
       likely requires new uAPI.

     - Track irqbypass's "token" as "struct eventfd_ctx *" instead of a "void *",
       to avoid making a simple concept unnecessarily difficult to understand.

     - Add CONFIG_KVM_IOAPIC for x86 to allow disabling support for I/O APIC, PIC,
       and PIT emulation at compile time.

     - Drop x86's irq_comm.c, and move a pile of IRQ related code into irq.c.

     - Fix a variety of flaws and bugs in the AVIC device posted IRQ code.

     - Inhibited AVIC if a vCPU's ID is too big (relative to what hardware
       supports) instead of rejecting vCPU creation.

     - Extend enable_ipiv module param support to SVM, by simply leaving IsRunning
       clear in the vCPU's physical ID table entry.

     - Disable IPI virtualization, via enable_ipiv, if the CPU is affected by
       erratum #1235, to allow (safely) enabling AVIC on such CPUs.

     - Dedup x86's device posted IRQ code, as the vast majority of functionality
       can be shared verbatime between SVM and VMX.

     - Harden the device posted IRQ code against bugs and runtime errors.

     - Use vcpu_idx, not vcpu_id, for GA log tag/metadata, to make lookups O(1)
       instead of O(n).

     - Generate GA Log interrupts if and only if the target vCPU is blocking, i.e.
       only if KVM needs a notification in order to wake the vCPU.

     - Decouple device posted IRQs from VFIO device assignment, as binding a VM to
       a VFIO group is not a requirement for enabling device posted IRQs.

     - Clean up and document/comment the irqfd assignment code.

     - Disallow binding multiple irqfds to an eventfd with a priority waiter, i.e.
       ensure an eventfd is bound to at most one irqfd through the entire host,
       and add a selftest to verify eventfd:irqfd bindings are globally unique.
```

###### patches in kvm-irqs-x86

git log --oneline 65164fd0f6b5..81bf24f1ac77
```
81bf24f1ac77 KVM: selftests: Add CONFIG_EVENTFD for irqfd selftest
7e9b231c402a KVM: selftests: Add a KVM_IRQFD test to verify uniqueness requirements
74e5e3fb0dd7 KVM: selftests: Add utilities to create eventfds and do KVM_IRQFD
033b76bc7f06 KVM: selftests: Assert that eventfd() succeeds in Xen shinfo test
b599d44a71f1 KVM: Drop sanity check that per-VM list of irqfds is unique
2cdd64cbf990 KVM: Disallow binding multiple irqfds to an eventfd with a priority waiter
0d09582b3a60 sched/wait: Add a waitqueue helper for fully exclusive priority waiters
a52664134a24 xen: privcmd: Don't mark eventfd waiter as EXCLUSIVE
867347bb21e1 sched/wait: Drop WQ_FLAG_EXCLUSIVE from add_wait_queue_priority()
86e00cd162a7 KVM: Add irqfd to eventfd's waitqueue while holding irqfds.lock
5f8ca05ea991 KVM: Add irqfd to KVM's list via the vfs_poll() callback
b5c543518ae9 KVM: Initialize irqfd waitqueue callback when adding to the queue
140768a7bf03 KVM: Acquire SCRU lock outside of irqfds.lock during assignment
283ed5001d68 KVM: Use a local struct to do the initial vfs_poll() on an irqfd
6f343724837b KVM: x86: Rename kvm_set_msi_irq() => kvm_msi_to_lapic_irq()
b03500f03ea0 KVM: SVM: Generate GA log IRQs only if the associated vCPUs is blocking
b9e53f9ff4a8 iommu/amd: KVM: SVM: Allow KVM to control need for GA log interrupts
5f3d06b1648e KVM: SVM: Consolidate IRTE update when toggling AVIC on/off
6eab2340f339 KVM: SVM: Don't check vCPU's blocking status when toggling AVIC on/off
f2bc961d383b KVM: SVM: Fold avic_set_pi_irte_mode() into its sole caller
a23480fe21de iommu/amd: WARN if KVM calls GA IRTE helpers without virtual APIC support
11a60455d4c9 KVM: SVM: Use vcpu_idx, not vcpu_id, for GA log tag/metadata
ce9d54f41be0 KVM: VMX: WARN if VT-d Posted IRQs aren't possible when starting IRQ bypass
77e1b8332d1d KVM: x86: Decouple device assignment from IRQ bypass
99836eb9c5dc KVM: SVM: WARN if ir_list is non-empty at vCPU free
25ef059e8bc5 KVM: x86: WARN if IRQ bypass routing is updated without in-kernel local APIC
d1bccaa1793d KVM: x86: WARN if IRQ bypass isn't supported in kvm_pi_update_irte()
04c4ca0ae479 KVM: x86: Drop superfluous "has assigned device" check in kvm_pi_update_irte()
cd86240fea26 KVM: SVM: WARN if updating IRTE GA fields in IOMMU fails
48f79c6c86b3 KVM: SVM: Process all IRTEs on affinity change even if one update fails
16562766f171 KVM: SVM: WARN if (de)activating guest mode in IOMMU fails
fe0213923dd9 KVM: SVM: Don't check for assigned device(s) when activating AVIC
f5998661ff73 KVM: SVM: Don't check for assigned device(s) when updating affinity
6df262f915ab iommu/amd: KVM: SVM: Add IRTE metadata to affined vCPU's list if AVIC is inhibited
f965255dc503 iommu/amd: KVM: SVM: Set pCPU info in IRTE when setting vCPU affinity
0b2b541fa3cd iommu/amd: Factor out helper for manipulating IRTE GA/CPU info
08d9ccdd1a5c iommu/amd: KVM: SVM: Infer IsRun from validity of pCPU destination
3be405e89f3d iommu/amd: Document which IRTE fields amd_iommu_update_ga() can modify
c3d591c91f9c KVM: SVM: Take and hold ir_list_lock across IRTE updates in IOMMU
71d6b3b8e69d KVM: SVM: Revert IRTE to legacy mode if IOMMU doesn't provide IR metadata
cc8b13105eac KVM: x86: Don't update IRTE entries when old and new routes were !MSI
dc6adb13046a KVM: x86: Skip IOMMU IRTE updates if there's no old or new vCPU being targeted
511754bc548b KVM: x86: Track irq_bypass_vcpu in common x86 code
77bb184ab880 KVM: Fold kvm_arch_irqfd_route_changed() into kvm_arch_update_irqfd_routing()
b33252b9d172 KVM: Don't WARN if updating IRQ bypass route fails
53527ea1b702 iommu: KVM: Split "struct vcpu_data" into separate AMD vs. Intel structs
803928483669 KVM: SVM: Clean up return handling in avic_pi_update_irte()
c5af31698d71 KVM: x86: Move posted interrupt tracepoint to common code
cf04ec393ed0 KVM: x86: Dedup AVIC vs. PI code for identifying target vCPU
9517aedecd0e KVM: x86: Nullify irqfd->producer after updating IRTEs
f5369619f7f8 KVM: x86: Move IRQ routing/delivery APIs from x86.c => irq.c
0a64c447f6f8 KVM: SVM: Extract SVM specific code out of get_pi_vcpu_info()
23ca102e6fb2 KVM: VMX: Stop walking list of routing table entries when updating IRTE
1e663ed23992 KVM: SVM: Stop walking list of routing table entries when updating IRTE
95d50ebe6df8 iommu/amd: KVM: SVM: Pass NULL @vcpu_info to indicate "not guest mode"
c4cdbaf9d81c iommu/amd: KVM: SVM: Use pi_desc_addr to derive ga_root_ptr
52d826c9e54c KVM: SVM: Add a comment to explain why avic_vcpu_blocking() ignores IRQ blocking
6737557442e5 KVM: VMX: Suppress PI notifications whenever the vCPU is put
8de4a1c8164e KVM: SVM: Disable (x2)AVIC IPI virtualization if CPU has erratum #1235
d921665e01ba KVM: SVM: Add enable_ipiv param, never set IsRunning if disabled
bafddc70001d KVM: VMX: Move enable_ipiv knob to common x86
d29433336a7b KVM: SVM: Drop superfluous "cache" of AVIC Physical ID entry pointer
26baab4eea4c KVM: SVM: Track AVIC tables as natively sized pointers, not "struct pages"
c24ed209c474 KVM: SVM: Drop redundant check in AVIC code on ID during vCPU creation
1aa6e256e46f KVM: SVM: Inhibit AVIC if ID is too big instead of rejecting vCPU creation
d8527f133c0a KVM: SVM: Drop vcpu_svm's pointless avic_backing_page field
3338c639da15 KVM: SVM: Add helper to deduplicate code for getting AVIC backing page
2e002ddc8966 KVM: SVM: Drop pointless masking of kernel page pa's with AVIC HPA masks
430579577892 KVM: SVM: Drop pointless masking of default APIC base when setting V_APIC_BAR
a0ca34bb1aad KVM: SVM: Delete IRTE link from previous vCPU irrespective of new routing
1da19c5ce053 iommu/amd: KVM: SVM: Delete now-unused cached/previous GA tag fields
0a917e9d4b70 KVM: SVM: Delete IRTE link from previous vCPU before setting new IRTE
05c5e23657e1 KVM: SVM: Track per-vCPU IRTEs using kvm_kernel_irqfd structure
cb210737675e KVM: Pass new routing entries and irqfd when updating IRTEs
e76c274513f2 KVM: x86: Fold irq_comm.c into irq.c
37b1761fe895 KVM: x86: Move IRQ mask notifier infrastructure to I/O APIC emulation
8fd2a6d43a10 KVM: selftests: Fall back to split IRQ chip if full in-kernel chip is unsupported
141db6cd79e2 KVM: Squash two CONFIG_HAVE_KVM_IRQCHIP #ifdefs into one
628a27731e3f KVM: x86: Add CONFIG_KVM_IOAPIC to allow disabling in-kernel I/O APIC
2c938850d9d1 KVM: Move x86-only tracepoints to x86's trace.h
cd9140ad8312 KVM: x86: Explicitly check for in-kernel PIC when getting ExtINT
2c31aa747d78 KVM: x86: Don't clear PIT's IRQ line status when destroying PIT
61423c413a74 KVM: x86: Hardcode the PIT IRQ source ID to '2'
77a74b8ff41a KVM: x86: Move kvm_{request,free}_irq_source_id() to i8254.c (PIT)
df35135680fa KVM: x86: Move kvm_setup_default_irq_routing() into irq.c
c5a701955e2d KVM: x86: Rename irqchip_kernel() to irqchip_full()
b771b1616ff8 KVM: x86: Move KVM_{GET,SET}_IRQCHIP ioctl helpers to irq.c
00b5ebf8db7c KVM: x86: Move PIT ioctl helpers to i8254.c
20218e69e85b KVM: x86: Drop superfluous kvm_hv_set_sint() => kvm_hv_synic_set_irq() wrapper
05dc9eab3f00 KVM: x86: Drop superfluous kvm_set_ioapic_irq() => kvm_ioapic_set_irq() wrapper
8a33b1f246ce KVM: x86: Drop superfluous kvm_set_pic_irq() => kvm_pic_set_irq() wrapper
e295d2e7fbe6 KVM: x86: Trigger I/O APIC route rescan in kvm_arch_irq_routing_update()
23b54381cee2 irqbypass: Require producers to pass in Linux IRQ number during registration
8394b32faecd irqbypass: Use xarray to track producers and consumers
46a4bfd0ae48 irqbypass: Use guard(mutex) in lieu of manual lock+unlock
5d7dbdce388b irqbypass: Use paired consumer/producer to disconnect during unregister
add57f493e08 irqbypass: Explicitly track producer and consumer bindings
2b521d86ee80 irqbypass: Take ownership of producer/consumer token tracking
07fbc83c0152 irqbypass: Drop superfluous might_sleep() annotations
fa079a0616ed irqbypass: Drop pointless and misleading THIS_MODULE get/put
cd4178d19420 KVM: arm64: WARN if unmapping a vLPI fails in any path
```