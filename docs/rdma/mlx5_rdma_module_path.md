# mlx5 RDMA Module Layering and Source Paths

## Scope
This document maps Linux RDMA module layering from user-space verbs to kernel mlx5 modules, and lists the requested modules with usage and source code paths.

Kernel source root used:
- `/home/mz/linux/linux`

## Verified module artifacts (.ko) in compiled tree
- `/home/mz/linux/linux/drivers/infiniband/hw/mlx5/mlx5_ib.ko`
- `/home/mz/linux/linux/drivers/infiniband/core/ib_uverbs.ko`
- `/home/mz/linux/linux/drivers/infiniband/core/ib_core.ko`
- `/home/mz/linux/linux/drivers/net/ethernet/mellanox/mlx5/core/mlx5_core.ko`
- `/home/mz/linux/linux/drivers/net/ethernet/mellanox/mlxfw/mlxfw.ko`

Note:
- `pci_hyperv_intf` source/build rule exists in this tree, and module is present in runtime (`lsmod/modinfo`), but `.ko` was not found under the current build output path scan.

## Runtime modules (your list)
- `mlx5_ib               495616  0`
- `ib_uverbs             208896  2 rdma_ucm,mlx5_ib`
- `ib_core               552960  12 rdma_cm,ib_ipoib,rpcrdma,ib_srpt,iw_cm,ib_iser,ib_umad,ib_isert,rdma_ucm,ib_uverbs,mlx5_ib,ib_cm`
- `mlx5_core            1974272  1 mlx5_ib`
- `mlxfw                  36864  1 mlx5_core`
- `pci_hyperv_intf        12288  1 mlx5_core`

## RDMA layering (user space to kernel)

| Layer | Component | Key functions | Usage | Source path |
|---|---|---|---|---|
| L7 | User app + libibverbs/librdmacm | `ibv_open_device`, `ibv_create_qp`, `ibv_post_send`, `rdma_create_id` | Userspace verbs/CM API entry | Outside kernel tree (rdma-core) |
| L6 | `ib_uverbs` | `ib_uverbs_init`, `ib_uverbs_ioctl` | `/dev/infiniband/uverbsX` ioctl gateway for verbs objects/methods | `/home/mz/linux/linux/drivers/infiniband/core/uverbs_main.c`, `/home/mz/linux/linux/drivers/infiniband/core/uverbs_ioctl.c` |
| L5 | `ib_core` | `ib_core_init`, `ib_register_device`, `ib_unregister_device` | Core RDMA framework, device/object lifecycle and client notifications | `/home/mz/linux/linux/drivers/infiniband/core/device.c` |
| L4 | `mlx5_ib` | `mlx5_ib_init`, `mlx5r_probe`, `__mlx5_ib_add`, `ib_alloc_device_with_net`, `ib_set_device_ops`, `ib_register_device` | ConnectX RDMA provider; binds mlx5 RDMA auxiliary device to IB core | `/home/mz/linux/linux/drivers/infiniband/hw/mlx5/main.c` |
| L3 | `mlx5_core` | `mlx5_init`, `pci_register_driver`, `mlx5_cmd_init`, `mlx5_cmd_init_hca`, `mlx5_rdma_enable_roce` | Core PCI/HCA driver, command interface, RoCE capability/control, base services | `/home/mz/linux/linux/drivers/net/ethernet/mellanox/mlx5/core/main.c`, `/home/mz/linux/linux/drivers/net/ethernet/mellanox/mlx5/core/cmd.c`, `/home/mz/linux/linux/drivers/net/ethernet/mellanox/mlx5/core/rdma.c` |
| L2 | `mlxfw` | `mlxfw_firmware_flash` | Firmware flashing FSM library used by mlx5 core firmware path | `/home/mz/linux/linux/drivers/net/ethernet/mellanox/mlxfw/mlxfw_fsm.c` |
| L1 | `pci_hyperv_intf` | `init_hv_pci_intf`, `exit_hv_pci_intf` | Hyper-V PCI interface helper dependency used by mlx5_core on this runtime | `/home/mz/linux/linux/drivers/pci/controller/pci-hyperv-intf.c` |

## Requested mlx5-related modules: usage and source path

| Module | Runtime purpose | Key functions / integration points | Source path |
|---|---|---|---|
| `mlx5_ib` | RDMA provider for mlx5 | `mlx5_ib_init`, auxiliary probe (`mlx5r_probe`), `__mlx5_ib_add`, `ib_register_device` | `/home/mz/linux/linux/drivers/infiniband/hw/mlx5/main.c` |
| `ib_uverbs` | Userspace verbs kernel interface | `ib_uverbs_init`, file ops `.unlocked_ioctl = ib_uverbs_ioctl`, `ib_uverbs_ioctl` | `/home/mz/linux/linux/drivers/infiniband/core/uverbs_main.c`, `/home/mz/linux/linux/drivers/infiniband/core/uverbs_ioctl.c` |
| `ib_core` | RDMA core framework | `ib_core_init`, `ib_register_device`, `ib_unregister_device` | `/home/mz/linux/linux/drivers/infiniband/core/device.c` |
| `mlx5_core` | ConnectX base PCI/core driver | `mlx5_init`, `pci_register_driver`, `mlx5_cmd_init`, `mlx5_cmd_init_hca`, `mlx5_rdma_enable_roce` | `/home/mz/linux/linux/drivers/net/ethernet/mellanox/mlx5/core/main.c`, `/home/mz/linux/linux/drivers/net/ethernet/mellanox/mlx5/core/cmd.c`, `/home/mz/linux/linux/drivers/net/ethernet/mellanox/mlx5/core/rdma.c` |
| `mlxfw` | Mellanox firmware flash library | `mlxfw_firmware_flash` (exported symbol), consumed by mlx5 core firmware code | `/home/mz/linux/linux/drivers/net/ethernet/mellanox/mlxfw/mlxfw_fsm.c`; consumer: `/home/mz/linux/linux/drivers/net/ethernet/mellanox/mlx5/core/fw.c` |
| `pci_hyperv_intf` | Hyper-V PCI interface helper | `init_hv_pci_intf`, `exit_hv_pci_intf` | `/home/mz/linux/linux/drivers/pci/controller/pci-hyperv-intf.c` |

## Build composition references (module Makefiles)
- `ib_core`/`ib_uverbs`: `/home/mz/linux/linux/drivers/infiniband/core/Makefile`
- `mlx5_ib`: `/home/mz/linux/linux/drivers/infiniband/hw/mlx5/Makefile`
- `mlx5_core`: `/home/mz/linux/linux/drivers/net/ethernet/mellanox/mlx5/core/Makefile`
- `mlxfw`: `/home/mz/linux/linux/drivers/net/ethernet/mellanox/mlxfw/Makefile`
- `pci_hyperv_intf`: `/home/mz/linux/linux/drivers/pci/controller/Makefile`

## Architecture note (important)
This kernel generation uses mlx5 auxiliary devices for RDMA binding:
- `mlx5_ib` registers auxiliary drivers for names like `mlx5_core.rdma` and `mlx5_core.multiport`.
- So the modern bind path is auxiliary-bus probe/remove flow, not the older direct `mlx5_register_interface` model.
