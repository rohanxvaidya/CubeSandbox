# CubeSandbox create-delete Concurrency Sweep — Runbook (CWF / Xeon 6990E)

This runbook documents the exact methodology, environment, and every tuning used
for the CubeSandbox v0.4.0 sandbox **create-delete** concurrency sweeps on the
Clearwater Forest (CWF) node, including the guest-kernel toolchain matrix and the
200 ms knee measurements.

> All numbers are environment- and workload-dependent. This run targets a single
> Intel Xeon 6990E node; results will differ on other hardware/kernels.

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

## 3. Guest-kernel builds (toolchain matrix)

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

### 3.1 Critical build settings
- **`CONFIG_ASYNC_FORK` DISABLED** — required for the 4-level-paging build
  (`mm/async_fork.c` exports `__p4d_alloc`, a static inline under 4-level paging →
  modpost error otherwise). `make olddefconfig` re-enables it, so re-disable after:
  ```bash
  make olddefconfig && ./scripts/config --file .config --disable ASYNC_FORK
  ```
- BTF enabled (`CONFIG_DEBUG_INFO_BTF`) → build host needs `pahole`/`dwarves`.
- Confirm the PVH note post-build: `readelf -n vmlinux | grep 0x00000012`.

### 3.2 Building with the exact Ubuntu gcc 13.3.0 toolchain (Tencent match)
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

### 3.3 Fetching the source behind the lab proxy
The Intel proxy (`proxy-dmz.intel.com:912`) blocks large clones. Use a blobless
clone then batch-fetch blobs by SHA:
```bash
git clone --filter=blob:none --no-checkout <repo>
# then: git fetch origin <up-to-1000 SHAs per batch>
```

### 3.4 Installing / activating a kernel
```bash
strip -s vmlinux -o $KDIR/vmlinux-<name>            # ~51.5 MB
ln -sfn vmlinux-<name> $KDIR/vmlinux                # activate
cubemastercli -a 127.0.0.1 tpl redo --template-id <TID> --wait --interval 3s --json
```
`cubemastercli` requires `-a 127.0.0.1` (default `0.0.0.0` returns 403).

---

## 4. Template & per-sandbox spec

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

## 5. Tuning parameters (the BKM)

### 5.1 CubeMaster — orchestrator (`CubeMaster/conf.yaml`)
| Parameter | Value |
|---|---|
| `create_concurrent_limit` | **500** |
| `destroy_concurent_limit` | **500** |
| `common_timeout_insec` | 30 |
| `create_image_timeout_insec` | 300 |
| `http_readtimeout` / `writetimeout` / `idletimeout` | 120 / 360 / 360 s |
| `http_port` / `grpc_port` | 8089 / 9999 |
| scheduler filters | cpu, mem, template_locality, realtime_create_num |

### 5.2 Cubelet — compute agent (`Cubelet/config/config.toml`)
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

### 5.3 Cubelet dynamic (`Cubelet/dynamicconf/conf.yaml`)
Per-node caps all **0 = unlimited**: `creation_concurrent_num=0`, `mcpu_limit=0`,
`mvm_limit=0`, `mem_limit=""`. `disable_host_cgroup=true`,
`disable_host_netfile=true`, default DNS `119.29.29.29`.

### 5.4 Database / cache pools
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

## 6. Benchmark methodology

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

### 6.1 Orchestration layouts
- **`1orch-allNUMA`**: a single `cube-bench` stream spanning all 288 threads.
- **`1orch-perNUMA`**: 3 `cube-bench` streams, one `taskset`-pinned per NUMA node
  (0-95 / 96-191 / 192-287), each running `C/3`. NOTE: the CubeMaster scheduler
  itself is a **single** process (affinity 0-287); only the load driver is split.

Scripts: `e2e-repo-latency-sweep.sh` (1orch-allNUMA),
`run_3orch_per_numa_sweep.sh` (1orch-perNUMA). Each records a `meta.txt` capturing
the active kernel and template, and (per-NUMA) an `uptime.log` verifying the 6
support containers never drop.

---

## 7. Results — 200 ms knee (all tpl-cea9, 100 % success)

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

## 8. Post-run artifacts & conventions

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

## 9. End-to-end reproduction

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
