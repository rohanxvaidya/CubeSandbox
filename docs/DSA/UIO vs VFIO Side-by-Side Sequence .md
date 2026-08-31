**UIO vs VFIO Side-by-Side Sequence (From This Code)**

| Phase | UIO path | VFIO path |
|---|---|---|
| Driver detection | user_device.c counts uio devices | user_device.c counts vfio devices |
| USER init entry | user_device.c | user_device.c |
| Per-device init selection | user_device.c calls user_device.c | user_device.c calls user_device.c |
| PCI resource access | sysfs mmap of resource0/resource2 in user_device.c | VFIO region query + mmap in user_device.c |
| Bus enable / reset | writes PCI config via sysfs config file and reset command in user_device.c | VFIO config-space access + VFIO_DEVICE_RESET in user_device.c |
| DMA mapping model | no VFIO map fd, set in user_device.c as dmap_fd = -1 | container fd stored as dmap_fd in user_device.c |
| Runtime dmap behavior | device.c returns immediately when fd == -1 | device.c calls user_device.c using VFIO_IOMMU_MAP_DMA |
| IOVA translation | user_device.c uses pagemap phys address via user_device.c | user_device.c returns VA as IOVA (identity mapping model in this app) |
| IOMMU status in app logic | user_device.c true | user_device.c false |
| Effect in test loop | skips IOTLB invalidation branch (checked via device.c) | runs IOTLB invalidation branch in main.c |

**Different Config/Constraints Implemented in Code**
1. Mixed binding is rejected: if both uio and vfio device counts are non-zero, init fails in user_device.c.
2. UIO requires DPDK EAL initialization path in user_device.c; VFIO does not.
3. UIO uses custom allocator hook for physically backed memory when available in user_device.c.
4. VFIO requires viable IOMMU group/container setup and VFIO_TYPE1_IOMMU in user_device.c.
5. Both paths share the same DSA device programming logic once BARs are mapped: user_device.c.

**Practical takeaway**
- UIO path is simpler and relies on physical address translation from userspace.
- VFIO path is stricter and safer from an IOMMU isolation perspective, with explicit DMA map/unmap and group/container ownership.
- Performance behavior can differ because VFIO takes mapping + IOMMU path, while UIO is treated as iommu disabled by this app.

If you want, I can produce the same comparison specifically for your exact command path (-k 6 -u -o3 -w 0), with only the functions actually hit in your run log.