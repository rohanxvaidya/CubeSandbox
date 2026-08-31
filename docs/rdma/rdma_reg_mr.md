# RDMA MR Registration Deep Dive

This note consolidates the earlier questions and answers about `ibv_reg_mr`, the kernel call path, mlx5 MR registration, address mapping, PAS/XLT, and where to add debug prints.

## 1. Where is `ibv_reg_mr` defined?

`ibv_reg_mr` is a userspace `libibverbs` API.

### Public declaration and macro wrapper
Path:
- `/home/mz/rdma/rdma-core/libibverbs/verbs.h`

Relevant code:
```c
struct ibv_mr *ibv_reg_mr(struct ibv_pd *pd, void *addr, size_t length,
			  int access);

__attribute__((__always_inline__)) static inline struct ibv_mr *
__ibv_reg_mr(struct ibv_pd *pd, void *addr, size_t length, unsigned int access,
	     int is_access_const)
{
	if (is_access_const && (access & IBV_ACCESS_OPTIONAL_RANGE) == 0)
		return ibv_reg_mr(pd, addr, length, (int)access);
	else
		return ibv_reg_mr_iova2(pd, addr, length, (uintptr_t)addr,
					access);
}

#define ibv_reg_mr(pd, addr, length, access)                                   \
	__ibv_reg_mr(pd, addr, length, access,                                 \
		     __builtin_constant_p(                                       \
			     ((int)(access) & IBV_ACCESS_OPTIONAL_RANGE) == 0))
```

### Exported symbol implementation
Path:
- `/home/mz/rdma/rdma-core/libibverbs/verbs.c`

Relevant code:
```c
LATEST_SYMVER_FUNC(ibv_reg_mr, 1_1, "IBVERBS_1.1",
		   struct ibv_mr *,
		   struct ibv_pd *pd, void *addr,
		   size_t length, int access)
{
	return ibv_reg_mr_iova2(pd, addr, length, (uintptr_t)addr, access);
}
```

## 2. Does `ibv_reg_mr` enter the kernel?

Yes.

The userspace library issues an `ioctl()` on the uverbs file descriptor.

### Userspace command builder
Path:
- `/home/mz/rdma/rdma-core/libibverbs/cmd.c`

Relevant code:
```c
int ibv_cmd_reg_mr(struct ibv_pd *pd, void *addr, size_t length,
		   uint64_t hca_va, int access,
		   struct verbs_mr *vmr, struct ibv_reg_mr *cmd,
		   size_t cmd_size,
		   struct ib_uverbs_reg_mr_resp *resp, size_t resp_size)
{
	...
	cmd->hca_va       = hca_va;
	cmd->pd_handle    = pd->handle;
	cmd->access_flags = access;

	ret = execute_cmd_write(pd->context, IB_USER_VERBS_CMD_REG_MR, cmd,
				cmd_size, resp, resp_size);
	...
}
```

### Actual ioctl boundary
Path:
- `/home/mz/rdma/rdma-core/libibverbs/cmd_ioctl.c`

Relevant code:
```c
if (ioctl(context->cmd_fd, RDMA_VERBS_IOCTL, &cmd->hdr))
	return errno;
```

So the path crosses into the kernel through `RDMA_VERBS_IOCTL`.

## 3. Kernel entry point for MR registration

### Kernel uverbs handler
Path:
- `/home/mz/linux/linux/drivers/infiniband/core/uverbs_cmd.c`

Relevant code:
```c
static int ib_uverbs_reg_mr(struct uverbs_attr_bundle *attrs)
{
	struct ib_uverbs_reg_mr_resp resp = {};
	struct ib_uverbs_reg_mr      cmd;
	struct ib_uobject           *uobj;
	struct ib_pd                *pd;
	struct ib_mr                *mr;
	int                          ret;
	struct ib_device *ib_dev;

	ret = uverbs_request(attrs, &cmd, sizeof(cmd));
	if (ret)
		return ret;

	...
	mr = pd->device->ops.reg_user_mr(pd, cmd.start, cmd.length, cmd.hca_va,
					 cmd.access_flags, NULL,
					 &attrs->driver_udata);
	...
	resp.lkey = mr->lkey;
	resp.rkey = mr->rkey;
	resp.mr_handle = uobj->id;
	return uverbs_response(attrs, &resp, sizeof(resp));
}
```

### Command table binding
Path:
- `/home/mz/linux/linux/drivers/infiniband/core/uverbs_cmd.c`

Relevant code:
```c
DECLARE_UVERBS_WRITE(
	IB_USER_VERBS_CMD_REG_MR,
	ib_uverbs_reg_mr,
	UAPI_DEF_WRITE_UDATA_IO(struct ib_uverbs_reg_mr,
				struct ib_uverbs_reg_mr_resp),
	UAPI_DEF_METHOD_NEEDS_FN(reg_user_mr)),
```

## 4. mlx5 kernel callback for `reg_mr`

### Device ops hookup
Path:
- `/home/mz/linux/linux/drivers/infiniband/hw/mlx5/main.c`

Relevant code:
```c
.reg_user_mr = mlx5_ib_reg_user_mr,
.reg_user_mr_dmabuf = mlx5_ib_reg_user_mr_dmabuf,
```

### mlx5 MR registration function
Path:
- `/home/mz/linux/linux/drivers/infiniband/hw/mlx5/mr.c`

Relevant code:
```c
struct ib_mr *mlx5_ib_reg_user_mr(struct ib_pd *pd, u64 start, u64 length,
				  u64 iova, int access_flags,
				  struct ib_dmah *dmah,
				  struct ib_udata *udata)
{
	struct mlx5_ib_dev *dev = to_mdev(pd->device);
	struct ib_umem *umem;
	int err;

	if (!IS_ENABLED(CONFIG_INFINIBAND_USER_MEM) ||
	    ((access_flags & IB_ACCESS_ON_DEMAND) && dmah))
		return ERR_PTR(-EOPNOTSUPP);

	mlx5_ib_dbg(dev, "start 0x%llx, iova 0x%llx, length 0x%llx, access_flags 0x%x\n",
		    start, iova, length, access_flags);

	err = mlx5r_umr_resource_init(dev);
	if (err)
		return ERR_PTR(err);

	if (access_flags & IB_ACCESS_ON_DEMAND)
		return create_user_odp_mr(pd, start, length, iova, access_flags,
					  udata);
	umem = ib_umem_get(&dev->ib_dev, start, length, access_flags);
	if (IS_ERR(umem))
		return ERR_CAST(umem);
	return create_real_mr(pd, umem, iova, access_flags, dmah);
}
```

## 5. Where does the mapping happen?

The important sequence is:
1. Pin user pages
2. Build an sg table from those pages
3. DMA-map the sg table for the RDMA device
4. Program those DMA addresses into mlx5 PAS or XLT entries

### Pin and DMA-map userspace memory
Path:
- `/home/mz/linux/linux/drivers/infiniband/core/umem.c`

Relevant code:
```c
while (npages) {
	cond_resched();
	pinned = pin_user_pages_fast(cur_base,
				  min_t(unsigned long, npages,
					PAGE_SIZE /
					sizeof(struct page *)),
				  gup_flags, page_list);
	if (pinned < 0) {
		ret = pinned;
		goto umem_release;
	}

	cur_base += pinned * PAGE_SIZE;
	npages -= pinned;
	ret = sg_alloc_append_table_from_pages(
		&umem->sgt_append, page_list, pinned, 0,
		pinned << PAGE_SHIFT, ib_dma_max_seg_size(device),
		npages, GFP_KERNEL);
	if (ret) {
		unpin_user_pages_dirty_lock(page_list, pinned, 0);
		goto umem_release;
	}
}

...

ret = ib_dma_map_sgtable_attrs(device, &umem->sgt_append.sgt,
			       DMA_BIDIRECTIONAL, dma_attr);
```

This is where the kernel obtains the backing pages and maps them into DMA addresses for the device.

### DMA map helper
Path:
- `/home/mz/linux/linux/include/rdma/ib_verbs.h`

Relevant code:
```c
static inline int ib_dma_map_sgtable_attrs(struct ib_device *dev,
					   struct sg_table *sgt,
					   enum dma_data_direction direction,
					   unsigned long dma_attrs)
{
	int nents;

	if (ib_uses_virt_dma(dev)) {
		nents = ib_dma_virt_map_sg(dev, sgt->sgl, sgt->orig_nents);
		if (!nents)
			return -EIO;
		sgt->nents = nents;
		return 0;
	}
	return dma_map_sgtable(dev->dma_device, sgt, direction, dma_attrs);
}
```

So the hardware-visible addresses are DMA addresses, not necessarily raw CPU physical addresses.

## 6. Where are DMA addresses written into the MR translation?

There are two major paths.

### A. Direct PAS path
Path:
- `/home/mz/linux/linux/drivers/infiniband/hw/mlx5/mr.c`
- `/home/mz/linux/linux/drivers/infiniband/hw/mlx5/mem.c`

#### `reg_create()` fills PAS into create_mkey input
```c
pas = (__be64 *)MLX5_ADDR_OF(create_mkey_in, in, klm_pas_mtt);
if (populate) {
	...
	mlx5_ib_populate_pas(umem, 1UL << mr->page_shift, pas,
			     pg_cap ? MLX5_IB_MTT_PRESENT : 0);
}
```

#### PAS population function
```c
void mlx5_ib_populate_pas(struct ib_umem *umem, size_t page_size, __be64 *pas,
			  u64 access_flags)
{
	struct ib_block_iter biter;

	rdma_umem_for_each_dma_block (umem, &biter, page_size) {
		*pas = cpu_to_be64(rdma_block_iter_dma_address(&biter) |
				   access_flags);
		pas++;
	}
}
```

So PAS is the list of DMA-backed page addresses written directly into the create-mkey command.

### B. UMR/XLT path
Path:
- `/home/mz/linux/linux/drivers/infiniband/hw/mlx5/mr.c`
- `/home/mz/linux/linux/drivers/infiniband/hw/mlx5/umr.c`

#### MR creation path decides whether to use UMR
```c
xlt_with_umr = mlx5r_umr_can_load_pas(dev, umem->length);
if (xlt_with_umr) {
	mr = alloc_cacheable_mr(pd, umem, iova, access_flags,
				MLX5_MKC_ACCESS_MODE_MTT,
				st_index, ph);
} else {
	...
	mr = reg_create(pd, umem, iova, access_flags, page_size,
			true, MLX5_MKC_ACCESS_MODE_MTT,
			st_index, ph);
	...
}
...
if (xlt_with_umr) {
	err = mlx5r_umr_update_mr_pas(mr, MLX5_IB_UPD_XLT_ENABLE);
	...
}
```

#### UMR path fills XLT entries from DMA addresses
```c
rdma_umem_for_each_dma_block(mr->umem, &biter, BIT(mr->page_shift)) {
	...
	if (dd) {
		cur_ksm->va = cpu_to_be64(rdma_block_iter_dma_address(&biter));
		...
	} else {
		cur_mtt->ptag =
			cpu_to_be64(rdma_block_iter_dma_address(&biter) |
				    MLX5_IB_MTT_PRESENT);
		...
	}
}
```

So in the UMR path, the XLT is the translation table payload sent later using UMR work requests.

## 7. What are PAS and XLT?

### PAS
PAS means page address list.

It is the list of DMA addresses for the MR pages, usually packed directly into the create-mkey command buffer.

### XLT
XLT means translation table.

In mlx5 UMR code, XLT is the memory translation content loaded or updated after mkey creation. For a normal MR, these are usually MTT entries. For data-direct/KSM mode, they are KSM entries.

### Relationship
1. PAS is the initial page-address payload form.
2. XLT is the more general translation table update mechanism used by UMR.
3. Both ultimately carry DMA-backed MR page translations.

## 8. What is the difference between umem address, iova, and physical address?

They are not the same thing in general.

### umem address
This is the original userspace virtual address.

Stored in:
- `umem->address`

Relevant code:
```c
umem->address = addr;
```

### iova
This is the IO virtual address used by the MR from the RDMA/NIC point of view.

Stored in:
- `umem->iova`

Relevant code:
```c
umem->iova = addr;
```

For simple `ibv_reg_mr` use, `iova` is often equal to the original user address. But conceptually it is a separate field and can differ, especially in `ibv_reg_mr_iova` style flows.

### physical address
Strictly, the driver usually operates on DMA addresses, not raw host physical addresses.

1. Userspace VA is pinned into pages.
2. Those pages are DMA-mapped.
3. The DMA addresses are then programmed into PAS/XLT.

### Practical summary
1. `umem->address`: userspace virtual address
2. `iova`: MR-visible address used by RDMA hardware logic
3. `physical`/DMA address: backing page address used in PAS/XLT

They may sometimes numerically match in trivial cases, but they are not the same concept and should not be assumed equal.

## 9. Recommended call stack for `reg_mr`

### End-to-end stack
1. perftest calls `ibv_reg_mr`
2. `libibverbs` wrapper/macro in `verbs.h`
3. exported `ibv_reg_mr` symbol in `verbs.c`
4. provider registration function such as `mlx5_reg_mr`
5. `ibv_cmd_reg_mr`
6. `execute_cmd_write`
7. `ioctl(..., RDMA_VERBS_IOCTL, ...)`
8. kernel `ib_uverbs_reg_mr`
9. `pd->device->ops.reg_user_mr`
10. `mlx5_ib_reg_user_mr`
11. `ib_umem_get`
12. `create_real_mr`
13. either:
   - `reg_create` -> `mlx5_ib_populate_pas`
   - or `alloc_cacheable_mr` -> `mlx5r_umr_update_mr_pas`

## 10. Where to add debug prints

If you want to debug `reg_mr`, there are three useful print points.

### A. Print user start and IOVA at MR registration entry
Path:
- `/home/mz/linux/linux/drivers/infiniband/hw/mlx5/mr.c`

Insertion point: inside `mlx5_ib_reg_user_mr()`.

Example:
```c
mlx5_ib_warn(dev,
	     "REG_MR start=0x%llx iova=0x%llx len=0x%llx access=0x%x\n",
	     start, iova, length, access_flags);
```

### B. Print host physical pages right after `pin_user_pages_fast`
Path:
- `/home/mz/linux/linux/drivers/infiniband/core/umem.c`

Insertion point: immediately after `pin_user_pages_fast()` returns.

Example:
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

This prints host physical page addresses.

### C. Print DMA addresses programmed into PAS
Path:
- `/home/mz/linux/linux/drivers/infiniband/hw/mlx5/mem.c`

Insertion point: inside `mlx5_ib_populate_pas()`.

Example:
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

### D. Print DMA addresses programmed into XLT/UMR
Path:
- `/home/mz/linux/linux/drivers/infiniband/hw/mlx5/umr.c`

Insertion point: inside `_mlx5r_umr_update_mr_pas()`.

Example:
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

This is the best place if the MR goes through the cacheable UMR path.

## 11. Which print point should be used?

### If you want to print IOVA only
Use:
- `mlx5_ib_reg_user_mr()` in `/home/mz/linux/linux/drivers/infiniband/hw/mlx5/mr.c`

### If you want to print IOVA to DMA mapping
Use one of:
- `mlx5_ib_populate_pas()` in `/home/mz/linux/linux/drivers/infiniband/hw/mlx5/mem.c`
- `_mlx5r_umr_update_mr_pas()` in `/home/mz/linux/linux/drivers/infiniband/hw/mlx5/umr.c`

### If you want host physical page addresses
Use:
- `ib_umem_get()` in `/home/mz/linux/linux/drivers/infiniband/core/umem.c`

## 12. Bottom line

For mlx5 MR registration:
1. `ibv_reg_mr` is a userspace function in `libibverbs`
2. it enters the kernel through `RDMA_VERBS_IOCTL`
3. the kernel handler is `ib_uverbs_reg_mr`
4. mlx5 handles it in `mlx5_ib_reg_user_mr`
5. user pages are pinned and DMA-mapped in `ib_umem_get`
6. mlx5 writes DMA addresses into PAS or XLT
7. `umem->address`, `iova`, and physical/DMA addresses are different concepts and should not be assumed equal

If you want the most useful practical debug output:
1. print `start` and `iova` in `mlx5_ib_reg_user_mr`
2. print host physical pages in `ib_umem_get`
3. print DMA addresses in `mlx5_ib_populate_pas` or `_mlx5r_umr_update_mr_pas`
