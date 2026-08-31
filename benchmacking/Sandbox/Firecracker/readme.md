## Firecracker introduction

Firecracker is an open source virtualization technology that is purpose-built
for creating and managing secure, multi-tenant container and function-based
services that provide serverless operational models. Firecracker runs workloads
in lightweight virtual machines, called microVMs, which combine the security and
isolation properties provided by hardware virtualization technology with the
speed and flexibility of containers.


The main component of Firecracker is a virtual machine monitor (VMM) that uses
the Linux Kernel Virtual Machine (KVM) to create and run microVMs. Firecracker
has a minimalist design. It excludes unnecessary devices and guest-facing
functionality to reduce the memory footprint and attack surface area of each
microVM. 

To read more about Firecracker, check out  
- [Source code in github](https://github.com/firecracker-microvm/firecracker/tree/main)  
- [firecracker-microvm.io](https://firecracker-microvm.github.io).

## How to install and deploy
To get started with Firecracker, download the latest
[release](https://github.com/firecracker-microvm/firecracker/releases) binaries
or build it from source.

You can build Firecracker on any Unix/Linux system that has Docker running (we
use a development container) and `bash` installed, as follows:

```bash
git clone https://github.com/firecracker-microvm/firecracker
cd firecracker
tools/devtool build
toolchain="$(uname -m)-unknown-linux-musl"
```

The Firecracker binary will be placed at
`build/cargo_target/${toolchain}/debug/firecracker`. For more information on
building, testing, and running Firecracker, go to the
[quickstart guide](https://github.com/firecracker-microvm/firecracker/blob/main/docs/getting-started.md).

### Qiuckly deploy firecracker:
Use tool to deploy firecracker for benchmark: [firecracker_deploy](./tools/firecracker_deploy.sh)
```
# Only check the environemnt
sudo ./firecracker_deploy.sh --check-only

# install specified firecracker version
sudo ./firecracker_deploy.sh --firecracker-version v1.16.1

# force build rootfs, size is 2GiB
sudo ./firecracker_deploy.sh --force-rootfs-rebuild --rootfs-size-mib 2048
```
Tips: You can leverage AI tool to check the environment and deploy the firecracker refer the the MD files.

## How to benchmark
Refer to the benchmark tool Use the [`fc_jailer_startup_benchmark`](tools/run_fc_jailer_startup_bench.sh) tool to measure sandbox creation latency at different concurrency levels. it supports 2 benchmark mode: create-delete | create-only (default "create-delete") 
In this benchmark, there are two kinds of mode to judge the creation is completed, this tools support two mode;
- bootitmer mode: the time point for first time transist to userspace from kernel space;
- network mode: the network is ready in userspace after all of the services are ready;

```bash
# # 50-concurrent, 500 total, create-delete (default mode), and completion flag for creat is boottimer mode.
./run_fc_jailer_startup_bench.sh -n 500 -c 50 --timeout 30  --ready-criteria boottimer -p 1 -m 128 --network off --boot-args "reboot=k panic=1 nomodule 8250.nr_uarts=0 i8042.nomux  i8042.dumbkbd swiotlb=noforce cryptomgr.notests" --official-init-path /usr/local/bin/init --serial-console off

# --kernel specify the kernel image path
# --rootfs specify the ext4 image path

```


## Check the firecracker sandbox status or cleanup the sandboxes
Use the [`fc_sandbox_manager`](tools/fc_sandbox_manager.sh) tool to manage the firecracker sandbox status and cleanup the orphan sandbox.
```bash
sudo ./fc_sandbox_manager.sh [status|cleanup] [--dry-run] [--verbose]
```


## Sannity check the firecracker perforamnce
Run this command in the firecracker source code root path, it will take 20~30 minutes.
```
tools/devtool -y test --performance -- integration_tests/performance/test_boottime.py -m nonci
```


## Performance data reference:
Please refer to the inital data on CWF [Initial Perf Data](../Data/Firecracker_E2B_initial_exp.md)