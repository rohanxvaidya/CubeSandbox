# CubeSandbox create-delete Concurrency Sweep — Runbook (CWF / Xeon 6990E)

This runbook documents the exact methodology, environment, and every tuning used
for the CubeSandbox v0.4.0 sandbox **create-delete** concurrency sweeps on the
Clearwater Forest (CWF) node, including the guest-kernel toolchain matrix and the
200 ms knee measurements.

> All numbers are environment- and workload-dependent. This run targets a single
> Intel Xeon 6990E node; results will differ on other hardware/kernels.

---
## 0. Quick Start (newcomer TL;DR)

Goal: run the CubeSandbox create-delete concurrency sweep and get a 200 ms-knee
number. This is the 5-minute path; the detailed sections (§3–§10) explain the
why and the tuning.

**Assumes:** CubeSandbox v0.4.0 is already deployed (6 control-plane containers
up), a template is `READY`, and `cube-bench` is built. If not, do §3 (deploy)
and §5 (template) first.

```bash
# 1. Sanity check the platform is up
docker ps --format '{{.Names}}'            # expect 6: mysql, redis, proxy,
                                           # proxy-coredns, egress, webui
curl -s -o /dev/null -w '%{http_code}\n' \
  -H 'X-API-Key: e2b_000000' http://127.0.0.1:3000/sandboxes   # expect 200

# 2. Set the run environment
export E2B_API_URL="http://127.0.0.1:3000"
export E2B_API_KEY="e2b_000000"
export CUBE_TEMPLATE_ID="tpl-cea9de24f21d4d4fac319a15"     # any READY template
BENCH=/root/cube-src/CubeSandbox/examples/cube-bench/bin/cube-bench

# 3. Smoke test — one tiny point (should print create/delete latency, 100% ok)
$BENCH --no-tui -m create-delete -c 10 -n 100 -w 3 \
  -t "$CUBE_TEMPLATE_ID" --api-url "$E2B_API_URL" --api-key "$E2B_API_KEY" \
  -o /data/smoke.json && echo OK

# 4. One real point at your target concurrency (e.g. c=200)
cpupower -c all frequency-set -g performance      # match run conditions
$BENCH --no-tui -m create-delete -c 200 -n 2000 -w 3 \
  -t "$CUBE_TEMPLATE_ID" --api-url "$E2B_API_URL" --api-key "$E2B_API_KEY" \
  -o /data/c200.json

# 5. Full sweep c=100..350 (writes results + chart into a /data run dir)
bash run_3orch_per_numa_sweep.sh          # 1orch-perNUMA (NUMA-pinned streams)
# or: bash e2e-repo-latency-sweep.sh      # 1orch-allNUMA (single stream)
```

**What you get:** a `/data/cube_createdelete_..._knee-c<NNN>_<date>/` directory
with per-point JSON, `sweep.csv`, `meta.txt`, and a create-latency-vs-concurrency
chart. The headline number is the **200 ms knee** — the concurrency at which mean
create latency crosses 200 ms at 100% success.

**Key flags:** `-c` = concurrency, `-n = c*10` = total ops, `-w 3` = warmup rounds
(excluded), `-m create-delete` = create then delete each sandbox.

**Golden rules (see §6, §7):** keep all 6 control-plane containers up for the
whole sweep; set the CPU governor to `performance`; drop caches (`sync; echo 3 >
/proc/sys/vm/drop_caches`) between points; require 100% success at every point.

---

## 1. Objective

Measure sandbox **create latency vs concurrency** for CubeSandbox v0.4.0 and find
the **200 ms knee** = the concurrency at which mean create latency crosses 200 ms
at 100 % success. Compare guest-kernel builds/toolchains and two orchestration
layouts.

---

## 2. Platform / hardware

| Item | Value |
|---|---|
| Node | `smcgnrcwfsrfap1s` (CWF) |
| CPU | Intel Xeon 6990E "Clearwater Forest", 1 socket, **288 threads** |
| NUMA | **3 nodes**: node0 = CPU 0-95, node1 = 96-191, node2 = 192-287 |
| Host OS | CentOS Stream 9 (el9) |
| Host kernel | 7.1.0 |
| Platform | CubeSandbox v0.4.0 (single node: 1 CubeMaster + 1 Cubelet) |
| VMM | Cloud Hypervisor fork, PVH direct-boot (Xen PVH ELF note type 0x12) |
| CPU governor | `performance` (set before each sweep) |

---

## 3. Deploy CubeSandbox (Docker + one-click)

The single-node platform (1 CubeMaster + 1 Cubelet) and its 6 support containers
are stood up by the `cube-sandbox-one-click` bundle — they are **not** created by
hand. Docker must be installed first.

### 3.1 Prerequisites
- **`/data` disk (XFS + reflink).** Sandbox rootfs uses CoW reflink clones under
  `/data`, so back it with a dedicated disk formatted **XFS with `reflink=1`** and
  mount it before running `install.sh`:
  ```bash
  wipefs -a /dev/<disk>
  mkfs.xfs -m reflink=1 -L cubedata -f /dev/<disk>
  mkdir -p /data && mount /dev/<disk> /data
  # persist across reboots (replace any existing /data line)
  echo "UUID=$(blkid -s UUID -o value /dev/<disk>)  /data  xfs  defaults,noatime  0  0" >> /etc/fstab
  systemctl daemon-reload
  xfs_info /data | grep -q 'reflink=1' && echo "reflink OK"
  ```
- **Host eBPF/BTF enabled.** Cube networking needs BPF + BTF in the host kernel:
  ```bash
  ls -l /sys/kernel/btf/vmlinux
  grep -E 'CONFIG_DEBUG_INFO_BTF|CONFIG_BPF_SYSCALL|CONFIG_BPF_JIT' /boot/config-$(uname -r)
  ```
  If BTF is absent (no `/sys/kernel/btf/vmlinux`, or the config file is missing
  because the host runs a self-built kernel), build a BTF-enabled 7.1.0 host
  kernel per **§3.1.1**.

### 3.1.1 Build the 7.1.0 host kernel (BTF-enabled)

The host kernel for these runs is a **self-built `7.1.0`** (not a distro package),
so `/boot/config-$(uname -r)` and `/sys/kernel/btf/vmlinux` are absent until you
build it with the options below. Source tree: `/root/linux-7.1` (from
`linux-7.1.tar.xz`).

> **Ordering gotcha (root cause of missing BTF):** `CONFIG_DEBUG_INFO_BTF`
> depends on `PAHOLE_VERSION >= 122` (`lib/Kconfig.debug`). If `pahole`/`dwarves`
> is not installed **before** you run `make *config`, the option is silently
> absent from `.config` (it won't even show as `# ... is not set`) and the built
> `vmlinux` has no `.BTF` section. **Install `dwarves` first.**

```bash
# 1. Toolchain + BTF generator (pahole). dwarves MUST be present before configuring.
dnf install -y gcc make ncurses-devel flex bison openssl openssl-devel \
  elfutils-libelf-devel bc perl dwarves        # CentOS Stream 9 / el9
pahole --version                                # need >= v1.22 (el9 ships 1.31)

# 2. Seed .config from a known-good base for this platform, then adapt to 7.1.
cd /root/linux-7.1
cp .config .config.bak.$(date +%s) 2>/dev/null || true
cp /boot/config-<baseline>  .config            # e.g. the installed CWF BKC config,
                                               # or the sandbox kernel-build template
                                               # stack/kernel-build/config/config-6.11.5-1.el9.elrepo.x86_64
yes '' | make oldconfig                        # answer NEW symbols with defaults

# 3. Enable the required BPF + BTF options (idempotent).
#    Also clear BTF's blockers: DEBUG_INFO_BTF `depends on !DEBUG_INFO_REDUCED &&
#    !DEBUG_INFO_SPLIT && !GCC_PLUGIN_RANDSTRUCT` — if the baseline set any of
#    them, `make olddefconfig` (step 4) would silently drop BTF again.
./scripts/config --file .config \
  --enable  BPF --enable BPF_SYSCALL --enable BPF_JIT --enable BPF_JIT_ALWAYS_ON \
  --enable  DEBUG_INFO --enable DEBUG_INFO_BTF --enable DEBUG_INFO_BTF_MODULES \
  --disable DEBUG_INFO_REDUCED --disable DEBUG_INFO_SPLIT \
  --disable GCC_PLUGIN_RANDSTRUCT

# 4. Sandbox build has no signing keys — clear them or `make install` fails.
./scripts/config --file .config \
  --disable SYSTEM_TRUSTED_KEYS --disable SYSTEM_REVOCATION_KEYS
make olddefconfig

# 5. Verify the options actually landed before building.
grep -E '^(CONFIG_DEBUG_INFO_BTF|CONFIG_DEBUG_INFO_BTF_MODULES|CONFIG_BPF_SYSCALL|CONFIG_BPF_JIT)=' .config

# 6. Build, install modules + image.
make -j"$(nproc)"
readelf -S vmlinux | grep -q '\.BTF' && echo "vmlinux has .BTF OK"
make modules_install install

# 7. `make install` does NOT copy .config for a custom build — do it so the
#    §3.1 config check (and tools that read /boot/config-$(uname -r)) work.
cp .config /boot/config-7.1.0

# 8. Point grub at the new kernel and reboot into it.
grubby --set-default /boot/vmlinuz-7.1.0
grubby --default-kernel                        # expect /boot/vmlinuz-7.1.0
reboot
```

After reboot, both §3.1 checks must pass:
```bash
ls -l /sys/kernel/btf/vmlinux                                        # exists
grep -E 'CONFIG_DEBUG_INFO_BTF|CONFIG_BPF_SYSCALL|CONFIG_BPF_JIT' /boot/config-$(uname -r)
```

> Note: this is the **host** kernel. The **guest** kernels the sandboxes boot
> (`6.6.119-49.6` builds / `vmlinux-bm`) are separate — see §4.

### 3.2 Install Docker
CubeSandbox needs Docker (with the compose plugin); the control-plane services run
as containers. On CentOS Stream 9 / el9:
```bash
dnf -y install dnf-plugins-core
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker
docker version                     # verify the daemon is up
```
Behind the Intel lab proxy, point the Docker daemon at it so image pulls/builds
work:
```bash
mkdir -p /etc/systemd/system/docker.service.d
cat >/etc/systemd/system/docker.service.d/http-proxy.conf <<'EOF'
[Service]
Environment="HTTP_PROXY=http://<proxy-host>:<port>"
Environment="HTTPS_PROXY=http://<proxy-host>:<port>"
Environment="NO_PROXY=localhost,127.0.0.1"
EOF
systemctl daemon-reload && systemctl restart docker
```

### 3.3 Run the one-click installer
**Obtain the bundle first.** `cube-sandbox-one-click-v0.4.0.tar.gz` is ~229 MB
(mostly `assets/package/sandbox-package.tar.gz` 178 MB + the guest-kernel
artifacts 54 MB), so it is **not** committed to this repo — GitHub rejects files
over 100 MB, and binary payloads don't belong in git history. Download it from the
official CubeSandbox PVM deploy guide: <https://cubesandbox.com/guide/pvm-deploy.html>
(source repo: <https://github.com/TencentCloud/CubeSandbox>). On the benchmark
host it is kept at `/root/cube-sandbox-one-click-v0.4.0.tar.gz`.

```bash
tar xzf cube-sandbox-one-click-v0.4.0.tar.gz
cd cube-sandbox-one-click-v0.4.0
cp env.example .env                # configure deploy options (e.g. CUBE_PVM_ENABLE) in .env
bash install.sh
```
This deploys CubeMaster + Cubelet and brings up the 6 support containers as
systemd services under `cube-sandbox-control.target` (so they persist across
reboot):

| Container | Role |
|---|---|
| `cube-sandbox-mysql` | Template & sandbox metadata (mysql:8.0) |
| `cube-sandbox-redis` | Caching layer (redis:7-alpine) |
| `cube-proxy` | Front proxy for CubeAPI |
| `cube-proxy-coredns` | Internal DNS for sandboxes (coredns) |
| `cube-egress` | Egress MITM / TLS-intercept policy plane (CA baked into sandboxes) |
| `cube-webui` | Web UI (openresty) — not needed for benchmarking |

### 3.4 Verify the deployment
```bash
docker ps                                   # 6 control-plane containers up
systemctl status cube-sandbox-control.target
ss -ltn '( sport = :3000 )'                 # CubeAPI listening on :3000
```
Once these are green, continue to guest-kernel selection and template creation
below.

---

## 4. Guest-kernel builds (toolchain matrix)

All guest kernels live at `/usr/local/services/cubetoolbox/cube-kernel-scf/`; the
active kernel is the `vmlinux` symlink. Source: `OpenCloudOS-Kernel` branch
`linux-6.6/released/6.6.119-49.6` (commit `fef2cec13d6e`), config `pvm_guest`.

| Binary | Version string | Toolchain |
|---|---|---|
| `vmlinux-6.6.119-pvm` | 6.6.119-49.6 | gcc 11.5.0 (Red Hat el9) |
| `vmlinux-6.6.119-gcc13-pvm` | 6.6.119-49.6 | gcc 13.3.1 (Red Hat el9, gcc-toolset-13) |
| `vmlinux-6.6.119-gcc13.3.0-ubuntu-pvm` | 6.6.119-49.6 | **gcc 13.3.0 (Ubuntu 24.04)** — matches Tencent original |
| `vmlinux-bm` | build `6.6.1199-0009-03_2.0.1` (labelled 6.6.119-49.6) | gcc 13.3.0 (Ubuntu), Tencent CI binary |
| `vmlinux-pvm` | 6.6.69 | gcc 13.3.0 (Ubuntu), Tencent original |

### 4.1 Critical build settings
- **`CONFIG_ASYNC_FORK` DISABLED** — required for the 4-level-paging build
  (`mm/async_fork.c` exports `__p4d_alloc`, a static inline under 4-level paging →
  modpost error otherwise). `make olddefconfig` re-enables it, so re-disable after:
  ```bash
  make olddefconfig && ./scripts/config --file .config --disable ASYNC_FORK
  ```
- BTF enabled (`CONFIG_DEBUG_INFO_BTF`) → build host needs `pahole`/`dwarves`.
- Confirm the PVH note post-build: `readelf -n vmlinux | grep 0x00000012`.

### 4.2 Building with the exact Ubuntu gcc 13.3.0 toolchain (Tencent match)
Red Hat el9 only ships gcc `11.5.0` and gcc-toolset-13 `13.3.1` — there is **no
Red Hat 13.3.0** (Red Hat's build of upstream 13.3 is always labelled `13.3.1`).
The only toolchain that self-reports `13.3.0` is Ubuntu 24.04. Build in a
container:
```bash
docker run --rm -e http_proxy -e https_proxy -e no_proxy \
  -v /home/mz/pvm-guest-6.6.119/linux:/build ubuntu:24.04 bash -lc '
  apt-get update && apt-get install -y build-essential gcc-13 g++-13 flex bison \
    libssl-dev libelf-dev bc kmod cpio rsync dwarves python3 zlib1g-dev \
    libcap-dev pkg-config
  cd /build && make clean
  make CC=gcc-13 HOSTCC=gcc-13 olddefconfig
  ./scripts/config --file .config --disable ASYNC_FORK
  make -j"$(nproc)" CC=gcc-13 HOSTCC=gcc-13 vmlinux'
```
`python3` + `zlib1g-dev` are required or the libbpf `resolve_btfids` host tool
fails. Result: `gcc-13 (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0`, ld 2.42.

### 4.3 Fetching the source behind the lab proxy
The Intel proxy (`proxy-dmz.intel.com:912`) blocks large clones. Use a blobless
clone then batch-fetch blobs by SHA:
```bash
git clone --filter=blob:none --no-checkout <repo>
# then: git fetch origin <up-to-1000 SHAs per batch>
```

### 4.4 Installing / activating a kernel
```bash
strip -s vmlinux -o $KDIR/vmlinux-<name>            # ~51.5 MB
ln -sfn vmlinux-<name> $KDIR/vmlinux                # activate
cubemastercli -a 127.0.0.1 tpl redo --template-id <TID> --wait --interval 3s --json
```
`cubemastercli` requires `-a 127.0.0.1` (default `0.0.0.0` returns 403).

---

## 5. Template & per-sandbox spec

| Item | Value |
|---|---|
| Template | `tpl-cea9de24f21d4d4fac319a15` (tpl-cea9) |
| instance_type | `cubebox`, template `version v2` |
| Per-sandbox CPU | **2000m (2 vCPU)** |
| Per-sandbox memory | **2000Mi (~2 GiB)** |
| Rootfs | ext4, 1 GiB writable layer |
| OCI source image | `cube-sandbox-cn.tencentcloudcr.com/cube-sandbox/sandbox-code:latest` |
| Egress | cube-egress CA baked in — **egress in-path (mTLS)** |

Support stack (6 Docker containers, kept up throughout every run):
`cube-webui`, `cube-proxy`, `cube-egress`, `cube-sandbox-redis`,
`cube-sandbox-mysql`, `cube-proxy-coredns`.

---

## 6. Tuning parameters (the BKM)

### 6.1 CubeMaster — orchestrator (`CubeMaster/conf.yaml`)
| Parameter | Value |
|---|---|
| `create_concurrent_limit` | **500** |
| `destroy_concurent_limit` | **500** |
| `common_timeout_insec` | 30 |
| `create_image_timeout_insec` | 300 |
| `http_readtimeout` / `writetimeout` / `idletimeout` | 120 / 360 / 360 s |
| `http_port` / `grpc_port` | 8089 / 9999 |
| scheduler filters | cpu, mem, template_locality, realtime_create_num |

### 6.2 Cubelet — compute agent (`Cubelet/config/config.toml`)
| Parameter | Value |
|---|---|
| `tap_init_num` | **500** (pre-created TAP devices — the key BKM) |
| `flows.create.concurrent` / `flows.destroy.concurrent` | **500** / **500** |
| `pool_size` | 3000 |
| `pool_workers` | 4 |
| `pool_trigger_interval_in_ms` | 500 |
| `max_concurrent_downloads` | 10 |
| `network_agent_init_timeout` / `tap_fd_timeout` | 120 s / 2 s |
| vm cpu / mem overhead | 0 / base 42Mi, coeff 64 |
| host cpu / mem overhead | 0.3 / 20Mi |
| storage backend | `cubecow` |
| NIC / MAC | `ens4055f1` / `20:90:6f:fc:fc:fc`, gw `20:90:6f:cf:cf:cf`, MTU 1500 |
| CIDR | `192.168.0.0/18` |

### 6.3 Cubelet dynamic (`Cubelet/dynamicconf/conf.yaml`)
Per-node caps all **0 = unlimited**: `creation_concurrent_num=0`, `mcpu_limit=0`,
`mvm_limit=0`, `mem_limit=""`. `disable_host_cgroup=true`,
`disable_host_netfile=true`, default DNS `119.29.29.29`.

### 6.4 Database / cache pools
App-side pools (`ossdb_config` = `instance_db_config`): `max_open_conns=100`,
`max_idle_conns=25`, `max_conn_life_time_seconds=300`,
`conn_timeout/read/write=5/5/5 s`, `db_name=cube_mvp`.

MySQL server (`cube-sandbox-mysql`): `max_connections=500` (tuned).

Redis (`redis` / `redis_read` / `redis_write`): `max_active=32`, `max_idle=8`,
`idle_timeout=30`, `max_retry=2`.

> Four independent **500** ceilings align: CubeMaster create/destroy limit,
> Cubelet workflow create/destroy concurrent, `tap_init_num`, MySQL
> `max_connections`. Host quotas are 0 (unlimited), so concurrency is bounded by
> the 500 pools, not by per-node throttles.

---

## 7. Benchmark methodology

Driver: `cube-bench` (compiled binary) at
`/root/cube-src/CubeSandbox/examples/cube-bench/bin/cube-bench`.
API: E2B-compatible at `http://127.0.0.1:3000` (key `e2b_000000`, auth disabled).

Per concurrency point (per stream):
```bash
cube-bench --no-tui -m create-delete -c <c> -n <c*10> -w 3 -t <TID> \
  --api-url http://127.0.0.1:3000 --api-key e2b_000000 -o <out>.json
```
- `-m create-delete`: create sandbox → delete, measure create latency.
- `-w 3`: **3 warmup rounds** before measurement (not counted).
- `-n = c*10`: total ops per point.
- Between points: delete all sandboxes, `sync`, `echo 3 > /proc/sys/vm/drop_caches`.
- Aggregate concurrency **C swept 100 → 350 in steps of 10** (26 points).
- **Success criterion: 100 %** (0 errors) at every point.
- **Knee**: linear-interpolated C where mean create latency crosses 200 ms.

### 7.1 Orchestration layouts
- **`1orch-allNUMA`**: a single `cube-bench` stream spanning all 288 threads.
- **`1orch-perNUMA`**: 3 `cube-bench` streams, one `taskset`-pinned per NUMA node
  (0-95 / 96-191 / 192-287), each running `C/3`. NOTE: the CubeMaster scheduler
  itself is a **single** process (affinity 0-287); only the load driver is split.

Scripts: `e2e-repo-latency-sweep.sh` (1orch-allNUMA),
`run_3orch_per_numa_sweep.sh` (1orch-perNUMA). Each records a `meta.txt` capturing
the active kernel and template, and (per-NUMA) an `uptime.log` verifying the 6
support containers never drop.

---

## 8. Results — 200 ms knee (all tpl-cea9, 100 % success)

| Guest kernel build | Toolchain | 1orch-allNUMA | 1orch-perNUMA |
|---|---|---|---|
| 6.6.119-49.6 rebuild | gcc 11.5 (Red Hat) | c304 | c315-318 |
| 6.6.119-49.6 rebuild | gcc 13.3.1 (Red Hat) | c≈309 | c≈308 |
| 6.6.119-49.6 rebuild | gcc 13.3.0 (Ubuntu) | — | c≈310 |
| bm 6.6.1199 (Tencent CI) | gcc 13.3.0 (Ubuntu) | — | **c≈313** |
| Tencent original 6.6.69 | gcc 13.3.0 (Ubuntu) | (reference) | — |

Key findings:
- The gcc 13.3 builds recover the original ~c309-318 knee; the gcc 11.5 build
  kneed earlier at c304 (1orch-allNUMA) — the delta was purely toolchain.
- gcc 13.3.0 (Ubuntu) vs 13.3.1 (Red Hat) differ within noise (c≈310 vs c≈308).
- The Tencent CI `vmlinux-bm` (gcc 13.3.0) is marginally best at c≈313.

---

## 9. Post-run artifacts & conventions

After every sweep, a Turin-style chart is generated **inside** the run's `/data`
result dir: dark-blue avg + light-blue dashed p95 + red 200 ms line + annotated
knee ("avg crosses 200 ms @ c≈N").

Result directories are kept in `/data` and named:
```
cube_createdelete_<config>_<kernel>_<toolchain>_tpl-<id>_knee-c<NNN>_<YYYYMMDD>
```
- `<config>`: `1orch-allNUMA` | `1orch-perNUMA`
- `<kernel>`: `k6.6.119-49.6` (+ `-build6.6.1199` when the binary build string differs, e.g. vmlinux-bm)
- `<toolchain>`: `gcc11.5-rh` | `gcc13.3.1-rh` | `gcc13.3.0-ubuntu`

Each dir contains: `sweep.csv`, per-point JSON/logs, `meta.txt`, `uptime.log`
(per-NUMA), and the chart PNG.

---

## 10. End-to-end reproduction

```bash
# 1. Activate the desired guest kernel
KDIR=/usr/local/services/cubetoolbox/cube-kernel-scf
ln -sfn vmlinux-bm $KDIR/vmlinux                 # example: Tencent CI gcc13.3.0
cubemastercli -a 127.0.0.1 tpl redo --template-id tpl-cea9de24f21d4d4fac319a15 \
  --wait --interval 3s --json

# 2. Verify a sandbox boots
curl -s -X POST http://127.0.0.1:3000/sandboxes -H 'X-API-Key: e2b_000000' \
  -H 'Content-Type: application/json' \
  -d '{"templateID":"tpl-cea9de24f21d4d4fac319a15","timeout":60}'
# expect a sandboxID; DELETE returns HTTP 204

# 3. Confirm the 6 support containers are up
for c in cube-webui cube-proxy cube-egress cube-sandbox-redis \
         cube-sandbox-mysql cube-proxy-coredns; do
  docker inspect -f '{{.Name}} {{.State.Running}}' $c; done

# 4. Run the sweep (governor -> performance is set by the script)
bash run_3orch_per_numa_sweep.sh      # 1orch-perNUMA
# or: bash e2e-repo-latency-sweep.sh   # 1orch-allNUMA

# 5. Generate the chart into the result dir, then rename per the convention.
```

---

## 11. Granite Rapids port (Intel Xeon 6980P, GNR-AP)

Reproduced on a second Intel node — this documents only the **deltas** from the CWF
sections above; methodology (§7), tuning (§6), template (§5) are identical.

| Item | Value |
|---|---|
| Node | `avc15` |
| CPU | Intel **Xeon 6980P** (Granite Rapids-AP), 1 socket, **128 cores / 256 threads** |
| NUMA | **SNC3 → 3 nodes**: node0 `0-42,128-170`, node1 `43-85,171-213`, node2 `86-127,214-255` |
| Host kernel | **7.1.0**, built from the **GNR BKC** config (`stack/kernel-build/config/config-6.6.0-gnr.bkc…` → `make olddefconfig`) |
| Guest kernel | `vmlinux-bm` (6.6.1199-0009-03_2.0.1) — same as CWF |
| Template | `cubebox` v2, 2000m / 2000Mi, ext4 1 GiB, **egress CA baked** (`--with-cube-ca=true`) |

### 11.1 REQUIRED: `ibt=off` with CET compiled **in** (Intel-only gotcha)
GNR exposes CET/IBT to the guest; without the workaround the `vmlinux-bm` guest
**triple-faults** at boot (`exc_control_protection` → `Kernel panic`; the VMM shows
`VmShutdown` instead of `VsockServerReady`, and template create returns FAILED).

- Set **`ibt=off`** on the host boot line (per `readme.md`). This is **Intel-only** —
  AMD (Turin) does not need it.
- **Keep CET compiled in** (`CONFIG_X86_KERNEL_IBT=y`; the GNR BKC config already does).
  Disabling CET removes the `ibt=off` handler (`arch/x86/kernel/cet.c`) and the flag
  silently no-ops.
- **Verify** `ibt` is **absent from `/proc/cpuinfo`** (not just `dmesg`/cmdline) — only
  then does `setup_clear_cpu_cap` drop IBT from `boot_cpu_data`, so KVM stops
  advertising it to the guest (`kvm_cpu_cap_init` ANDs guest caps against `boot_cpu_data`).
- **Persist** it in `/etc/default/grub` + `/etc/kernel/cmdline` — `make install`
  regenerates the BLS entry and strips one-off `grubby --args`.

### 11.2 Sweep scripts (SNC3 = 3 NUMA nodes)
Two per-NUMA layouts, both `seq 100 10 350`, `-w 3`, per-point cleanup + drop_caches,
6 control-plane containers monitored throughout (`uptime.log`):

- **`run_1orch_per_numa_sweep_gnr.sh`** — 1 shared CubeMaster + `cube-bench` driver
  split into **3 NUMA-pinned streams** (mirrors CWF `run_3orch_per_numa_sweep.sh`).
- **`run_3orch_per_numa_gnr.sh`** — **3 CubeMaster orchestrators**, one `numactl`-pinned
  per NUMA node (ports 8089/8090/8091, sharing the single Cubelet); reversible teardown
  restores the systemd master (mirrors Turin `run_sweep_1orch_per_numa.sh`).

### 11.3 Results — 200 ms knee (tuned BKM=500, `ibt=off`, 100 % success)
| Layout | Knee | Notes |
|---|---|---|
| 1 CubeMaster + 3 NUMA-pinned drivers | **~c284** | flat ~85–115 ms to c180 |
| 3 CubeMasters (1 orch / NUMA) | **~c277** | |
| *(untuned, defaults=100)* | ~c176 | spikes at c180 — shows tuning is essential |
| CWF reference (Xeon 6990E) | ~c313 | for comparison |

Both GNR per-NUMA layouts land ~c277–284 at 100 % success, below CWF's ~c313.
**The BKM tuning (§6, limits 100→500) is essential** — the untuned box knees at ~c176.
