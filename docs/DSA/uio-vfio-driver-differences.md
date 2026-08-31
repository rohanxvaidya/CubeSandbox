# UIO vs VFIO-PCI in dsa_perf_micros

## Summary

In this project, both UIO and VFIO-PCI are handled under USER mode, but they differ in isolation model, DMA mapping behavior, address translation, and initialization path.

- UIO path: treated as IOMMU disabled by app logic.
- VFIO-PCI path: IOMMU-managed with explicit VFIO DMA map/unmap.

## Driver Selection Flow

1. USER mode is enabled via `-u` in option parsing: [src/options.c](src/options.c#L693).
2. Global driver init dispatch: [src/device.c](src/device.c#L98).
3. USER init entry: [src/user_device.c](src/user_device.c#L1047).
4. Driver binding counts:
   - VFIO count: [src/user_device.c](src/user_device.c#L948)
   - UIO count: [src/user_device.c](src/user_device.c#L954)
5. Mixed mode (both non-zero) is rejected: [src/user_device.c](src/user_device.c#L1047).

## Side-by-Side Sequence

| Phase | UIO | VFIO-PCI |
|---|---|---|
| Per-device init | [uio_init](src/user_device.c#L653) | [vfio_init](src/user_device.c#L682) |
| Resource mapping | sysfs resource mmap via [uio_map](src/user_device.c#L580) | VFIO region query + mmap in [vfio_init](src/user_device.c#L682) |
| Bus memory/master setup | [uio_setup_device](src/user_device.c#L264), [pci_uio_set_bus_master](src/user_device.c#L196) | [vfio_setup_device](src/user_device.c#L368), [pci_vfio_enable_bus_memory](src/user_device.c#L230), [pci_vfio_set_bus_master](src/user_device.c#L336) |
| Device reset | sysfs reset command in [uio_setup_device](src/user_device.c#L264) | `VFIO_DEVICE_RESET` in [vfio_setup_device](src/user_device.c#L382) |
| DMA map fd | `dmap_fd = -1` in [uio_init](src/user_device.c#L653) | `dmap_fd = container` in [vfio_init](src/user_device.c#L682) |
| dmap behavior | no-op in [dmap](src/device.c#L76) when fd is `-1` | [dmap](src/device.c#L76) -> [ud_dmap](src/user_device.c#L876) |
| Address translation | VA -> physical via pagemap in [rte_mem_virt2phy](src/user_device.c#L1299) | returns VA as IOVA in [user_virt2iova](src/user_device.c#L1350) |
| IOMMU flag to app | true in [ud_iommu_disabled](src/user_device.c#L1356) | false in [ud_iommu_disabled](src/user_device.c#L1356) |

## Code-Level Config Differences

1. UIO path enables DPDK EAL init when UIO devices exist: [dpdk_init](src/user_device.c#L979).
2. UIO path sets custom allocator hook: [user_driver_init](src/user_device.c#L1047).
3. VFIO path requires viable VFIO group/container and sets `VFIO_TYPE1_IOMMU`: [vfio_init](src/user_device.c#L682).
4. VFIO path uses explicit map/unmap ioctls:
   - map: [ud_dmap](src/user_device.c#L876)
   - unmap: [ud_dunmap](src/user_device.c#L900)
5. Both paths share common DSA queue/device programming once BARs are mapped: [init_pci_device](src/user_device.c#L396).

## Runtime Impact in This App

1. IOTLB invalidation logic depends on driver path via:
   - [iommu_disabled](src/device.c#L92)
   - check site in [src/main.c](src/main.c#L534)
2. UIO skips the IOMMU map/unmap route in this app.
3. VFIO executes the IOMMU map/unmap route and uses container FD for mappings.

## Note on the Reset Comment in Current Selection

The selected VFIO reset comment corresponds to this path:
- reset section in [src/user_device.c](src/user_device.c#L382)
- behavior: ignore reset failure only when `errno == EINVAL` (device not reset-capable), otherwise fail.
