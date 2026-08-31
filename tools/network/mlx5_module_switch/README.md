# mlx5 module switch (minimal rollback-safe plan)

This plan keeps the original stock module untouched and installs your custom module as an override.

## Files
- Script: /home/mz/mlx5_module_switch/mlx5_switch.sh
- Stock backup: /var/lib/mlx5-switch/<kernel>/mlx5_core.stock.ko
- Override path: /lib/modules/<kernel>/updates/mlx5-switch/mlx5_core.ko

## Why this is rollback-safe
- The stock module remains at:
  /lib/modules/<kernel>/kernel/drivers/net/ethernet/mellanox/mlx5/core/mlx5_core.ko
- The custom module is only placed in updates/ override path.
- Disable operation removes only the override and reloads the stock module.

## Commands
- Check status:
  /home/mz/mlx5_module_switch/mlx5_switch.sh status

- Enable custom module (install override + depmod + reload):
  /home/mz/mlx5_module_switch/mlx5_switch.sh enable

- Disable custom module (remove override + depmod + reload stock):
  /home/mz/mlx5_module_switch/mlx5_switch.sh disable

- Reload only (using current modprobe resolution):
  /home/mz/mlx5_module_switch/mlx5_switch.sh reload

## Optional environment overrides
- Use another built module path:
  CUSTOM_KO=/path/to/mlx5_core.ko /home/mz/mlx5_module_switch/mlx5_switch.sh enable

- Use another NUMA node for reload operations:
  NUMA_NODE=1 /home/mz/mlx5_module_switch/mlx5_switch.sh enable

## Notes
- The script uses numactl for reload when available.
- If numactl is missing, it falls back to normal modprobe.
- Root privileges are required for enable/disable/reload.
