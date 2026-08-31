# NIC Workload Guide

## Scope

This document defines only workload setup and execution.
It does not include emon parsing details or driver code details.

## Topology

- Server node: current node runs redis server instances.
- Client node: `10.239.23.34` runs redis-benchmark.
- Service IP: `10.10.10.100`.

## Redis Server Setup

Server startup script:

- `/home/mz/redis/redis_bench.sh`

Run redis server on SNC NUMA node 1, bind from core 40, with 20 instances:

```bash
cd /home/mz/redis
base_core=40 SNC=1 bash redis_bench.sh server
```

## NIC Reconfiguration After Driver Reload

If mlx5 driver is rebuilt and reloaded, rerun NIC configuration before benchmark.

NIC reconfiguration script:

- `/home/mz/redis/reconfig_nic.sh`

This script is expected to:

- Configure NIC IP.
- Set `sw_numa_node=1`.
- Toggle interface link down/up.
- Bind NIC IRQs to NUMA1 cores.

## Client Benchmark Control

Connect to client:

```bash
ssh -l root 10.239.23.34
```

Start benchmark from client:

```bash
IP=10.10.10.100 bash /home/mz/redis/redis_bench.sh
```

Stop benchmark from client:

```bash
pkill -9 redis-benchmark
```

## Run Checklist

1. Confirm server redis instances are up.
2. Confirm NIC is reconfigured after driver reload.
3. Start client benchmark.
4. After reload or NIC reconfiguration, wait 15 seconds before starting emon capture.
5. Keep workload stable during emon capture window.

## Related Docs

- EMON analysis: [NIC_emon_analysis.md](NIC_emon_analysis.md)
- Driver changes and optimization: [NIC_driver_optimization.md](NIC_driver_optimization.md)
