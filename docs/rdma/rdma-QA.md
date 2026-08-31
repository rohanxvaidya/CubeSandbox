# RDMA Session Q&A

This file captures the main user questions and the corresponding answers from this session.

---

## Q1. In this server, it can access remote server `192.168.0.3`, and please use `ibping` to have a quick test to verify the RDMA network is OK.

### Answer
I checked the local RDMA state and found:
- `ibping` is installed
- the RDMA port is active
- the NIC is running RoCE over Ethernet, not native InfiniBand

I then tested connectivity:
1. `ping -c 3 192.168.0.3`
   - Passed
2. `ibping -c 3 192.168.0.3`
   - Failed
   - Error showed LID-based routing problems
3. I tried a proper `ibping` client/server flow using remote GUID
   - Still failed because this environment is RoCE and `ibping` only supports IB-style LID/GUID routing
4. I used `rping` instead, which is appropriate for RoCE
   - Started `rping -s -a 192.168.0.3 -v` on the remote side
   - Ran `rping -c -a 192.168.0.3 -C 3 -v` locally
   - Data exchange succeeded

### Conclusion
The RDMA network path between this server and `192.168.0.3` is working.

`ibping` is not a valid verifier for this RoCE setup. `rping` is the correct quick test here, and it passed.

---

## Q2. Tell me the steps to test it.

### Answer
Recommended quick test flow:

1. Confirm IP connectivity
```bash
ping -c 3 192.168.0.3
```

2. Confirm RDMA device/link is up on both sides
```bash
ibstat
ssh 192.168.0.3 "ibstat"
```

3. Try `ibping` only if the fabric is native InfiniBand with LID/SM routing
```bash
ssh 192.168.0.3 "ibping -S"
ibping -c 3 <remote_lid_or_guid>
```

4. For RoCE, use `rping`
```bash
ssh 192.168.0.3 "nohup rping -s -a 192.168.0.3 -v > /tmp/rping_server.log 2>&1 &"
rping -c -a 192.168.0.3 -C 3 -v
```

5. Verify and clean up
```bash
ssh 192.168.0.3 "tail -n 50 /tmp/rping_server.log"
ssh 192.168.0.3 "pkill -f 'rping -s -a 192.168.0.3'"
```

---

## Q3. Refine `capture_core_flamegraph.sh`, the svg file name should be a specific name, use a parameter to specify a folder/name, if no, then you can use the pid directly.

### Answer
I updated the script to add a new option:
- `-n <name>`

Behavior:
1. If `-n` is provided:
   - output directory becomes `$WORKDIR/<name>`
   - SVG file name becomes `basename(<name>).svg`
2. If `-n` is not provided:
   - fallback uses the PID
   - output directory becomes `$WORKDIR/<pid>`
   - SVG file becomes `<pid>.svg`

I also updated the help text and examples, then verified the script with:
```bash
bash -n /home/mz/rdma/rdma_test/capture_core_flamegraph.sh
```

---

## Q4. Linux kernel source code directory: `/home/mz/linux/linux/drivers`. For Linux RDMA module layering, from the user space verbs lib to kernel driver module, please describe all of the modules and functions, and find all of the mlx5 RDMA related modules below, show usage and source code path, and sort out a layer table.

Requested modules:
- `mlx5_ib`
- `ib_uverbs`
- `ib_core`
- `mlx5_core`
- `mlxfw`
- `pci_hyperv_intf`

### Answer
I used the compiled `.ko` artifacts and the source tree to build a verified layer map.

### Verified compiled modules
Found in the built tree:
- `/home/mz/linux/linux/drivers/infiniband/hw/mlx5/mlx5_ib.ko`
- `/home/mz/linux/linux/drivers/infiniband/core/ib_uverbs.ko`
- `/home/mz/linux/linux/drivers/infiniband/core/ib_core.ko`
- `/home/mz/linux/linux/drivers/net/ethernet/mellanox/mlx5/core/mlx5_core.ko`
- `/home/mz/linux/linux/drivers/net/ethernet/mellanox/mlxfw/mlxfw.ko`

`pci_hyperv_intf` source/build rule exists, and runtime module metadata exists, but the `.ko` artifact was not found under the scanned build output path.

### Layered stack
1. User app + `libibverbs` / `librdmacm`
2. `ib_uverbs`
3. `ib_core`
4. `mlx5_ib`
5. `mlx5_core`
6. `mlxfw`
7. `pci_hyperv_intf`

### Important note
This kernel uses the newer auxiliary-bus model for mlx5 RDMA binding:
- `mlx5_core` publishes auxiliary devices such as `mlx5_core.rdma`
- `mlx5_ib` registers auxiliary drivers that bind to them

I then saved the detailed module path and layer table into:
- `/home/mz/rdma/mlx5_rdma_module_path.md`

---

## Q5. Please create a `mlx5_rdma_module_path.md` in `/home/mz/rdma/` and put the output in this md file.

### Answer
Created:
- `/home/mz/rdma/mlx5_rdma_module_path.md`

The file includes:
1. verified module `.ko` paths
2. layer table from userspace to kernel mlx5 modules
3. each requested module’s role, functions, and source file path
4. build Makefile references
5. note about the auxiliary-device architecture in current mlx5 RDMA binding

---

## Q6. Please find out where the function `ibv_dereg_mr` is defined, does this function trap into kernel, and show me the code.

### Answer
I traced `ibv_dereg_mr` across userspace and kernel.

### Userspace definition
Found in the local `rdma-core` tree under `libibverbs`.

### Kernel crossing
Yes, it goes into kernel through the same uverbs ioctl path used by other verbs commands.

The flow is:
1. userspace calls `ibv_dereg_mr`
2. `libibverbs` builds the command
3. ioctl is issued on the uverbs fd
4. kernel receives the command in `ib_uverbs`
5. the provider-specific driver handles the deregistration

I also noted that the local tree contains the command declaration for dereg MR in the kernel ABI headers and the libibverbs command implementation.

---

## Q7. Please find out where the function `ibv_reg_mr` is defined, does this function trap into kernel, and show me the code.

### Answer
I traced `ibv_reg_mr` end-to-end.

### Userspace side
Public declaration and macro wrapper are in:
- `/home/mz/rdma/rdma-core/libibverbs/verbs.h`

Exported symbol is in:
- `/home/mz/rdma/rdma-core/libibverbs/verbs.c`

For mlx5 provider userspace path, registration is handled in:
- `/home/mz/rdma/rdma-core/providers/mlx5/verbs.c`

### Kernel crossing
Yes. It enters kernel through:
- `ioctl(context->cmd_fd, RDMA_VERBS_IOCTL, &cmd->hdr)`

### Kernel handler
Main handler is:
- `/home/mz/linux/linux/drivers/infiniband/core/uverbs_cmd.c`
  - `ib_uverbs_reg_mr`

### mlx5 kernel callback
The provider callback is:
- `/home/mz/linux/linux/drivers/infiniband/hw/mlx5/main.c`
  - `.reg_user_mr = mlx5_ib_reg_user_mr`

The actual function is:
- `/home/mz/linux/linux/drivers/infiniband/hw/mlx5/mr.c`
  - `mlx5_ib_reg_user_mr`

### Summary
Yes, `ibv_reg_mr` goes into the kernel.

---

## Q8. Then continue the deep dive, where to mapping to physical address for MR? show me the code and callstack.

### Answer
The deeper answer is:

MR registration does not directly map user virtual memory to a single CPU physical address. It:
1. pins the user pages
2. builds an sg table
3. DMA-maps those pages for the device
4. writes DMA addresses into the mlx5 MR translation structure

### Core mapping point
The main mapping step is in:
- `/home/mz/linux/linux/drivers/infiniband/core/umem.c`

Relevant operations:
1. `pin_user_pages_fast(...)`
2. `sg_alloc_append_table_from_pages(...)`
3. `ib_dma_map_sgtable_attrs(...)`

### PAS path
For direct mkey creation, the DMA block addresses are copied into PAS in:
- `/home/mz/linux/linux/drivers/infiniband/hw/mlx5/mem.c`

### UMR/XLT path
For cached/UMR-loaded MRs, DMA addresses are written into the XLT entries in:
- `/home/mz/linux/linux/drivers/infiniband/hw/mlx5/umr.c`

### Important nuance
The hardware uses DMA addresses, not necessarily raw CPU physical addresses.

If IOMMU is enabled, the NIC sees DMA/IOMMU addresses, not host physical addresses.

### Call stack summary
1. `ibv_reg_mr`
2. `ibv_cmd_reg_mr`
3. ioctl `RDMA_VERBS_IOCTL`
4. `ib_uverbs_reg_mr`
5. `mlx5_ib_reg_user_mr`
6. `ib_umem_get`
7. `create_real_mr`
8. either:
   - `reg_create` -> `mlx5_ib_populate_pas`
   - or `alloc_cacheable_mr` -> `mlx5r_umr_update_mr_pas`

---

## Q9. What’s the PAS/XLT in the mlx5 kernel UMR files?

### Answer
### PAS
PAS means page address list.

It is the list of DMA-backed page addresses that are packed into the create-mkey command when the driver builds the MR translation directly.

Main function:
- `/home/mz/linux/linux/drivers/infiniband/hw/mlx5/mem.c`
  - `mlx5_ib_populate_pas`

### XLT
XLT means translation table.

In mlx5 UMR code, XLT is the translation-table payload that is updated after mkey creation using UMR work requests.

Main functions:
- `/home/mz/linux/linux/drivers/infiniband/hw/mlx5/umr.c`
  - `mlx5r_umr_update_mr_pas`
  - `mlx5r_umr_update_xlt`

### Relationship
1. PAS is the initial page-address payload form
2. XLT is the general translation-table update mechanism
3. both carry DMA-backed memory translations for the MR

---

## Q10. In this mlx5 kernel module for `reg_mr` function, where can I print the physical call for iova, show me the code, or where we can add the code to print.

### Answer
I recommended four useful debug insertion points.

### A. Print `start` and `iova`
Path:
- `/home/mz/linux/linux/drivers/infiniband/hw/mlx5/mr.c`

Inside `mlx5_ib_reg_user_mr()`:
```c
mlx5_ib_warn(dev,
	     "REG_MR start=0x%llx iova=0x%llx len=0x%llx access=0x%x\n",
	     start, iova, length, access_flags);
```

### B. Print host physical pages after pinning
Path:
- `/home/mz/linux/linux/drivers/infiniband/core/umem.c`

Right after `pin_user_pages_fast()`:
```c
{
	int j;

	for (j = 0; j < pinned; j++) {
		pr_info("umem pin: user_va=0x%lx phys=0x%llx page=%p\n",
			cur_base + (unsigned long)j * PAGE_SIZE,
			(unsigned long long)page_to_phys(page_list[j]),
			page_list[j]);
	}
}
```

### C. Print DMA addresses written into PAS
Path:
- `/home/mz/linux/linux/drivers/infiniband/hw/mlx5/mem.c`

Inside `mlx5_ib_populate_pas()`:
```c
size_t idx = 0;

rdma_umem_for_each_dma_block(umem, &biter, page_size) {
	dma_addr_t dma = rdma_block_iter_dma_address(&biter);

	pr_info("PAS[%zu]: iova=0x%llx dma=0x%llx page_size=0x%zx flags=0x%llx\n",
		idx,
		(unsigned long long)(umem->iova + idx * page_size),
		(unsigned long long)dma,
		page_size,
		(unsigned long long)access_flags);

	*pas = cpu_to_be64(dma | access_flags);
	pas++;
	idx++;
}
```

### D. Print DMA addresses written into UMR/XLT
Path:
- `/home/mz/linux/linux/drivers/infiniband/hw/mlx5/umr.c`

Inside `_mlx5r_umr_update_mr_pas()`:
```c
dma_addr_t dma = rdma_block_iter_dma_address(&biter);
u64 xlt_iova = mr->ibmr.iova + (u64)cur_block_idx * BIT(mr->page_shift);

pr_info("UMR XLT block=%zu iova=0x%llx dma=0x%llx page_shift=%u flags=0x%x\n",
	cur_block_idx,
	(unsigned long long)xlt_iova,
	(unsigned long long)dma,
	mr->page_shift,
	flags);
```

### Recommendation
If you only want one practical debug point, use:
- `mlx5_ib_reg_user_mr()` for start/iova
- `mlx5_ib_populate_pas()` or `_mlx5r_umr_update_mr_pas()` for DMA-backed translation entries

---

## Q11. So in this case, what’s the difference for umem address and iova and physical address? are they the same, or do they have the same value?

### Answer
They are not the same concept.

### `umem->address`
This is the original userspace virtual address.

### `iova`
This is the IO virtual address that the MR exposes to the RDMA/NIC side.

In simple `ibv_reg_mr` cases, `iova` is often numerically equal to the user virtual address. But it is logically separate and can differ in other registration flows.

### physical / DMA address
The pages backing the MR are pinned and then DMA-mapped. The values programmed into PAS/XLT are DMA addresses.

### Bottom line
1. `umem->address`: userspace VA
2. `iova`: MR-visible IO virtual base
3. physical/DMA address: backing memory translation entries used by hardware

These may sometimes happen to match numerically in trivial cases, but they are different address spaces and should not be treated as equivalent.

---

## Q12. Please put all above question and answers to a md file, save it in `/home/mz/rdma_reg_mr.md`.

### Answer
Created:
- `/home/mz/rdma_reg_mr.md`

This file contains the consolidated MR registration deep dive and the related Q&A.

---

## Q13. Please save all of questions and output in this session, save to `/home/mz/rdma-QA.md`.

### Answer
Created:
- `/home/mz/rdma-QA.md`

This file is the current document and captures the major questions and answers from the session.
