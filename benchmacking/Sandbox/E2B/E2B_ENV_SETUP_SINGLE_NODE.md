# E2B Single-Node Environment Setup

This guide is the single-node version of E2B deployment.

It is intended for one Linux host that will be used for one or more of the following:

- local E2B development
- local orchestrator testing
- local template build
- local benchmark execution
- Firecracker / NBD / hugepages debugging

This guide does not cover Terraform-based cloud self-hosting.

## 1. Target Host Requirements

### Minimum requirements

- Linux host
- root or sudo access
- `/dev/kvm` available
- nested virtualization enabled if the host is itself a VM

### Recommended hardware

- 4+ CPU cores
- 8 GB RAM minimum
- 16 GB RAM recommended
- enough free disk for Docker images, templates, kernels, Firecracker binaries, and benchmark artifacts

## 2. Base Package Installation

Install the packages needed for local E2B runtime, template build, and benchmarking.

Ubuntu example:

```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential \
  curl git jq \
  docker.io docker-compose-v2 \
  nodejs npm \
  nbd-client nbd-server \
  squashfs-tools e2fsprogs \
  iproute2 iptables \
  openssh-client \
  util-linux coreutils
```

Also install:

- Go
- Google Cloud SDK / `gsutil`

Verify basic tools:

```bash
go version
docker compose version
node --version
gsutil version -l
```

## 3. Verify Virtualization Support

Check KVM:

```bash
ls -l /dev/kvm
```

If missing:

```bash
sudo modprobe kvm_intel
# or
sudo modprobe kvm_amd
```

If you are on a cloud VM, ensure nested virtualization is enabled.

## 4. Clone the Repository

```bash
git clone https://github.com/e2b-dev/infra.git
cd infra
```

## 5. Prepare the Host Kernel Features

The E2B orchestrator and benchmarks depend on NBD, hugepages, and unprivileged userfaultfd.

### 5.1 Enable NBD

```bash
sudo modprobe nbd nbds_max=256
```

Persist NBD across reboot:

```bash
echo "nbd" | sudo tee /etc/modules-load.d/e2b.conf
echo "options nbd nbds_max=256" | sudo tee /etc/modprobe.d/e2b-nbd.conf
```

### 5.2 Disable NBD inotify watching

```bash
cat <<'EOF' | sudo tee /etc/udev/rules.d/97-nbd-device.rules
ACTION=="add|change", KERNEL=="nbd*", OPTIONS:="nowatch"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger
```

### 5.3 Enable unprivileged userfaultfd

```bash
echo 1 | sudo tee /proc/sys/vm/unprivileged_userfaultfd
```

To persist it:

```bash
echo 'vm.unprivileged_userfaultfd=1' | sudo tee /etc/sysctl.d/99-e2b-local.conf
sudo sysctl --system
```

### 5.4 Enable hugepages

Development-sized example:

```bash
sudo mkdir -p /mnt/hugepages
sudo mount -t hugetlbfs none /mnt/hugepages 2>/dev/null || true
echo 2000 | sudo tee /proc/sys/vm/nr_hugepages
```

Persist it:

```bash
grep -qF 'hugetlbfs /mnt/hugepages' /etc/fstab || \
  echo 'hugetlbfs /mnt/hugepages hugetlbfs defaults 0 0' | sudo tee -a /etc/fstab

echo 'vm.nr_hugepages=2000' | sudo tee -a /etc/sysctl.d/99-e2b-local.conf
sudo sysctl --system
```

For heavy benchmark hosts, you may need more than 2000 hugepages.

### 5.5 Verify the host state

```bash
lsmod | grep nbd
grep HugePages_Total /proc/meminfo
cat /proc/sys/vm/unprivileged_userfaultfd
ls /dev/kvm
```

## 6. Download Prebuilt Kernels and Firecracker Binaries

The repository already provides public artifact download targets.

```bash
make download-public-kernels
make download-public-firecrackers
```

Verify:

```bash
ls packages/fc-kernels/
find packages/fc-versions/builds -name firecracker | head
```

## 7. Download Busybox for Template Build

The local orchestrator build path expects busybox.

```bash
make -C packages/orchestrator fetch-busybox
```

## 8. Start Local Infrastructure Dependencies

Run the local Docker-based dependency stack:

```bash
make local-infra
```

This brings up services such as:

- Postgres
- ClickHouse
- Redis
- optional observability stack

Check status:

```bash
docker compose -f packages/local-dev/docker-compose.yaml ps
```

## 9. Initialize Databases

```bash
make -C packages/db migrate-local
make -C packages/clickhouse migrate-local
```

## 10. Build envd

```bash
make -C packages/envd build
```

Verify:

```bash
ls packages/envd/bin/envd
```

## 11. Seed the Local Database

```bash
make -C packages/local-dev seed-database
```

This prepares the local development user/team and local API tokens.

## 12. Run the Core E2B Services

Use separate terminals.

### Terminal 1: API

```bash
make -C packages/api run-local
```

Verify:

```bash
curl -s http://localhost:3000/health
```

### Terminal 2: Orchestrator

```bash
make -C packages/orchestrator build-debug
sudo make -C packages/orchestrator run-local
```

Verify:

```bash
curl -s http://localhost:5008/health
```

### Terminal 3: Client proxy

```bash
make -C packages/client-proxy run-local
```

Verify:

```bash
curl -s http://localhost:3003/health
```

## 13. Build the Base Template

Before sandbox creation, build the local base template:

```bash
make -C packages/shared/scripts local-build-base-template
```

## 14. Verify End-to-End E2B Works

Minimal API test:

```bash
curl -s -X POST http://localhost:3000/sandboxes \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" \
  -H "Content-Type: application/json" \
  -d '{"templateID": "base"}'
```

If it succeeds, you should get a sandbox object with a sandbox ID.

## 15. Local Client Configuration

```dotenv
E2B_API_KEY=e2b_53ae1fed82754c17ad8077fbc8bcdd90
E2B_ACCESS_TOKEN=sk_e2b_89215020937a4c989cde33d7bc647715
E2B_API_URL=http://localhost:3000
E2B_SANDBOX_URL=http://localhost:3002
```

## 16. Single-Node Benchmark Use

Once the local orchestrator environment is healthy, you can run benchmark helpers in:

- `packages/orchestrator/benchmarks`

For example:

```bash
cd packages/orchestrator/benchmarks
./preflight_benchmark_env.sh --apply
./run_concurrency_bench.sh -c 8 -n 640
```

The benchmark environment depends on:

- working Firecracker binaries
- working kernels
- healthy NBD pool
- enough hugepages
- clean residual state before each run

## 17. Optional: Firecracker-Only Lab Setup

If you only need a Firecracker startup lab rather than full E2B local services, you can use:

```bash
cd /home/mz/firecracker-lab
sudo ./bootstrap_firecracker_lab.sh
```

That path is useful for standalone Firecracker experiments, but it is not the full E2B stack.

## 18. Quick Validation Checklist

Run these checks before deeper debugging:

```bash
ls /dev/kvm
lsmod | grep nbd
grep HugePages_Total /proc/meminfo
cat /proc/sys/vm/unprivileged_userfaultfd
docker compose -f packages/local-dev/docker-compose.yaml ps
curl -s http://localhost:3000/health
curl -s http://localhost:5008/health
```

## 19. Common Single-Node Failure Modes

### `/dev/kvm` missing

- load `kvm_intel` or `kvm_amd`
- if inside a VM, enable nested virtualization

### NBD failures or leaked devices

- reload NBD with enough slots
- ensure udev `nowatch` rule is present
- detach leaked `/dev/nbd*` mappings before rerunning benchmarks

### Hugepages too low

- increase `vm.nr_hugepages`
- benchmark-heavy runs may need significantly more than the local default

### Firecracker binaries missing

- rerun:

```bash
make download-public-firecrackers
```

### Kernel artifacts missing

- rerun:

```bash
make download-public-kernels
```

### Busybox missing

- rerun:

```bash
make -C packages/orchestrator fetch-busybox
```

## 20. Recommended Bring-Up Order

If you are starting from zero, this is the shortest reliable path:

1. install system packages
2. verify `/dev/kvm`
3. enable NBD + hugepages + userfaultfd
4. clone repo
5. download kernels + Firecracker + busybox
6. start local infra
7. migrate databases
8. build envd
9. seed DB
10. run API + orchestrator + client proxy
11. build base template
12. create a sandbox
13. only then run benchmarks