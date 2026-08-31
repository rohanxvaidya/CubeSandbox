# E2B Environment Setup From Scratch

This document summarizes how to build an E2B environment from zero based on the current repository scripts and docs.

It covers two practical paths:

1. Local single-node development / benchmark environment on one Linux host
2. Full self-hosted E2B environment on GCP or AWS

If your immediate goal is local benchmarking, validation, or orchestrator development, use the local single-node path first.

## 1. Choose the Deployment Mode

### Local single-node mode

Use this when you want to:

- run orchestrator locally
- build base templates locally
- run E2B benchmarks on one host
- debug Firecracker, NBD, hugepages, template build, or local API flow

This is the best fit for a bare-metal Linux host or a VM with nested virtualization.

### Full self-hosted E2B mode

Use this when you want:

- a real multi-service E2B cluster
- public domain access
- persistent cloud infrastructure
- Terraform-managed deployment

The repository currently documents official self-hosting for:

- GCP
- AWS

General one-click deployment to an arbitrary standalone Linux machine is not documented as an official production path in this repo.

## 2. Common Prerequisites

### Host requirements

- Linux host
- KVM available at `/dev/kvm`
- root or sudo access
- nested virtualization enabled if you are inside a VM

Recommended minimums for local work:

- 4+ CPU cores
- 8 GB RAM minimum
- 16 GB RAM recommended

### Base software

For local E2B development and benchmarking, install at least:

- Go
- Docker Engine + Docker Compose v2
- Node.js + npm
- git
- curl
- jq
- `gsutil` from Google Cloud SDK

Typical Ubuntu example:

```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential curl git jq \
  docker.io docker-compose-v2 \
  nodejs npm \
  nbd-client nbd-server \
  squashfs-tools e2fsprogs
```

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

## 3. Local Single-Node E2B Environment

This is the fastest way to get a working E2B environment on one machine.

### Step 1: Clone the repository

```bash
git clone https://github.com/e2b-dev/infra.git
cd infra
```

### Step 2: Prepare the host kernel features

E2B orchestrator requires NBD and hugepages.

Load NBD:

```bash
sudo modprobe nbd nbds_max=256
```

Disable inotify watching on NBD devices:

```bash
cat <<'EOF' | sudo tee /etc/udev/rules.d/97-nbd-device.rules
ACTION=="add|change", KERNEL=="nbd*", OPTIONS:="nowatch"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger
```

Enable unprivileged userfaultfd:

```bash
echo 1 | sudo tee /proc/sys/vm/unprivileged_userfaultfd
```

Enable hugepages:

```bash
sudo mkdir -p /mnt/hugepages
sudo mount -t hugetlbfs none /mnt/hugepages 2>/dev/null || true
echo 2000 | sudo tee /proc/sys/vm/nr_hugepages
```

For a benchmark-heavy host, you may want more hugepages than the minimal development example.

### Step 3: Download prebuilt kernels and Firecracker binaries

The repo already provides Make targets for pulling public artifacts.

```bash
make download-public-kernels
make download-public-firecrackers
```

Verify:

```bash
ls packages/fc-kernels/
ls packages/fc-versions/builds/
```

### Step 4: Download busybox for orchestrator template builds

```bash
make -C packages/orchestrator fetch-busybox
```

This is required by local template build paths.

### Step 5: Start the local infra services

This launches the local dependency stack, including Postgres, ClickHouse, and Redis.

```bash
make local-infra
```

Verify:

```bash
docker compose -f packages/local-dev/docker-compose.yaml ps
```

### Step 6: Initialize databases

```bash
make -C packages/db migrate-local
make -C packages/clickhouse migrate-local
```

### Step 7: Build envd

```bash
make -C packages/envd build
```

Verify:

```bash
ls packages/envd/bin/envd
```

### Step 8: Seed local dev data

```bash
make -C packages/local-dev seed-database
```

This prepares a local user, team, and API tokens.

### Step 9: Run the core services

Use separate terminals.

#### Terminal 1: API

```bash
make -C packages/api run-local
```

Check:

```bash
curl -s http://localhost:3000/health
```

#### Terminal 2: Orchestrator

```bash
make -C packages/orchestrator build-debug
sudo make -C packages/orchestrator run-local
```

Check:

```bash
curl -s http://localhost:5008/health
```

#### Terminal 3: Client proxy

```bash
make -C packages/client-proxy run-local
```

Check:

```bash
curl -s http://localhost:3003/health
```

### Step 10: Build the base template

```bash
make -C packages/shared/scripts local-build-base-template
```

This is required before sandbox creation.

### Step 11: Verify end-to-end sandbox creation

```bash
curl -s -X POST http://localhost:3000/sandboxes \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" \
  -H "Content-Type: application/json" \
  -d '{"templateID": "base"}'
```

If successful, you should receive a sandbox object with a sandbox ID.

### Local environment endpoints

- API: `http://localhost:3000`
- Client proxy: `http://localhost:3002`
- Orchestrator: `http://localhost:5008`
- Postgres: `127.0.0.1:5432`
- ClickHouse HTTP: `http://localhost:8123`
- Redis: `localhost:6379`

### Local environment variables for clients

```dotenv
E2B_API_KEY=e2b_53ae1fed82754c17ad8077fbc8bcdd90
E2B_ACCESS_TOKEN=sk_e2b_89215020937a4c989cde33d7bc647715
E2B_API_URL=http://localhost:3000
E2B_SANDBOX_URL=http://localhost:3002
```

## 4. Local Benchmark / Firecracker-Lab Setup

If you only need a local Firecracker benchmark lab rather than the full local E2B stack, the repo already contains a bootstrap script:

```bash
cd /home/mz/firecracker-lab
sudo ./bootstrap_firecracker_lab.sh
```

That script does the following:

- installs system packages
- installs `firecracker` and `jailer`
- downloads kernel and squashfs artifacts
- builds an ext4 rootfs
- generates an SSH key for guest login

This is useful for Firecracker-only startup studies, but it is not by itself a full E2B environment.

## 5. Full Self-Hosted E2B on GCP or AWS

For a real self-hosted platform, the repo documents Terraform-based deployment.

### Common prerequisites

- Packer
- Terraform 1.7.5
- Go
- Docker
- Docker Buildx
- npm
- Cloudflare account and domain
- PostgreSQL database

### GCP self-hosting flow

1. Create a GCP project.
2. Copy `.env.gcp.template` to your environment file.
3. Run:

```bash
make set-env ENV=dev
make provider-login
make init
make build-and-upload
make copy-public-builds
```

4. Populate required secrets in GCP Secret Manager.
5. Provision infra:

```bash
make plan-without-jobs
make apply
make plan
make apply
```

6. Seed cluster data:

```bash
make prep-cluster
```

### AWS self-hosting flow

1. Copy `.env.aws.template` to your environment file and fill it.
2. Run:

```bash
make set-env ENV=dev
make provider-login
make init
```

3. Update required AWS Secrets Manager secrets.
4. Build the cluster AMI:

```bash
cd iac/provider-aws/nomad-cluster-disk-image
make init
make build
```

5. Build and upload application artifacts:

```bash
cd /path/to/infra
make build-and-upload
make copy-public-builds
```

6. Provision infra and jobs:

```bash
make plan-without-jobs
make apply
make plan
make apply
```

7. Seed cluster data:

```bash
make prep-cluster
```

## 6. Quick Validation Checklist

Before debugging E2B itself, verify the host basics:

```bash
ls /dev/kvm
lsmod | grep nbd
grep HugePages_Total /proc/meminfo
docker compose version
go version
node --version
```

For the local stack, also verify:

```bash
curl -s http://localhost:3000/health
curl -s http://localhost:5008/health
docker compose -f packages/local-dev/docker-compose.yaml ps
```

## 7. Common Failure Modes

### `/dev/kvm` missing

- load `kvm_intel` or `kvm_amd`
- if on cloud, enable nested virtualization or use a host that supports it

### NBD not available

- run `sudo modprobe nbd nbds_max=256`
- ensure `/etc/udev/rules.d/97-nbd-device.rules` disables NBD inotify watching

### Hugepages too small

- increase `vm.nr_hugepages`
- benchmark-heavy setups may need more than development defaults

### Firecracker or kernels missing

- rerun:

```bash
make download-public-kernels
make download-public-firecrackers
```

### Busybox missing for orchestrator build path

- run:

```bash
make -C packages/orchestrator fetch-busybox
```

## 8. Recommended Starting Path

If you are starting from zero and want the fastest success path:

1. bring up the local single-node environment first
2. verify API + orchestrator + client proxy + base template
3. only then move to benchmark automation or full cloud self-hosting

This gives you a much tighter feedback loop than starting directly with Terraform.