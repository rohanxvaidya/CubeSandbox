# Template & deployment config used for the CWF create-delete sweeps

This directory captures the exact template and platform configuration used for the
CubeSandbox create-delete concurrency sweeps documented in
[`../docs/runbook.md`](../docs/runbook.md).

## Template — `tpl-cea9`

| Field | Value |
|---|---|
| template_id | `tpl-cea9de24f21d4d4fac319a15` |
| instance_type | `cubebox` |
| spec version | `v2` |
| per-sandbox CPU | **2000m (2 vCPU)** |
| per-sandbox memory | **2000Mi (~2 GiB)** |
| rootfs | ext4, 1 GiB writable layer |
| egress | cube-egress CA baked in (mTLS, 2 targets), fingerprint `5f10304372a78eac` |
| source OCI image | `cube-sandbox-cn.tencentcloudcr.com/cube-sandbox/sandbox-code:latest` |
| source image digest | `sha256:743d264fad8c9dc9a49f07e931166d24d025363360ae770ca4b70e3f19540944` |

The template is **not** a static file — it is materialized on the node from the OCI
image above. To recreate it:

```bash
# Build the ext4 rootfs from the OCI image and register the template
cubemastercli -a 127.0.0.1 tpl create-from-image \
  --image cube-sandbox-cn.tencentcloudcr.com/cube-sandbox/sandbox-code:latest \
  --cpu 2000m --mem 2000Mi --wait

# Rebuild (redo) the template after switching the active guest kernel
cubemastercli -a 127.0.0.1 tpl redo --template-id <TID> --wait --interval 3s --json
```

`cubemastercli` must use `-a 127.0.0.1` (the default `0.0.0.0` returns HTTP 403).

## Config files (as deployed on the CWF node)

Copied verbatim from `/usr/local/services/cubetoolbox/` with **DB/Redis passwords
redacted** (`__REDACTED__`):

| File in repo | Source on node |
|---|---|
| `cubelet.config.toml` | `Cubelet/config/config.toml` |
| `cubelet.dynamicconf.conf.yaml` | `Cubelet/dynamicconf/conf.yaml` |
| `cubemaster.conf.yaml` | `CubeMaster/conf.yaml` |

### Key tunings (the BKM — see the runbook §5 for the full table)
- CubeMaster: `create_concurrent_limit=500`, `destroy_concurent_limit=500`
- Cubelet: `tap_init_num=500`, workflow `create/destroy.concurrent=500`,
  `pool_size=3000`, `pool_workers=4`, `pool_trigger_interval_in_ms=500`
- Cubelet dynamic quotas all `0` = unlimited
- MySQL server `max_connections=500` (tuned; not a config file — set on the
  `cube-sandbox-mysql` container)
- App DB pools: `max_open_conns=100`, `max_idle_conns=25`
- Redis pools: `max_active=32`, `max_idle=8`

> The four independent `500` ceilings (CubeMaster limit, Cubelet workflow
> concurrent, `tap_init_num`, MySQL `max_connections`) are the key concurrency BKM.
