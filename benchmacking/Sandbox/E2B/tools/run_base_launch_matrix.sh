#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${1:-$ROOT_DIR/benchmark_reports/e2b_base_$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT_DIR/logs"

CSV="$OUT_DIR/base_launch_matrix.csv"
cat > "$CSV" <<'EOF'
method,hugepages,cache_mode,vcpu,ram_mb,disk_mb,status,success_rate,fail_rate,avg_ms,p50_ms,p95_ms,p99_ms,total_ms,sandboxes_total,ok_count,fail_count,error_signature,log_file
EOF

host_nameserver=$(awk '/^nameserver /{print $2; exit}' /etc/resolv.conf)
proxy_url="${E2B_SANDBOX_HTTP_PROXY:-${http_proxy:-${HTTP_PROXY:-}}}"
https_proxy_url="${E2B_SANDBOX_HTTPS_PROXY:-${https_proxy:-${HTTPS_PROXY:-$proxy_url}}}"
no_proxy_url="${E2B_SANDBOX_NO_PROXY:-${no_proxy:-${NO_PROXY:-}}}"
allow_cidrs=()

if [[ -n "$host_nameserver" ]]; then
  allow_cidrs+=("${host_nameserver}/32")
fi

if [[ -n "$proxy_url" ]]; then
  proxy_host=$(python3 - <<'PY'
import os, urllib.parse
u = urllib.parse.urlparse(os.environ['PROXY_URL'])
print(u.hostname or '')
PY
PROXY_URL="$proxy_url")
  if [[ -n "$proxy_host" ]]; then
    proxy_ip=$(getent ahostsv4 "$proxy_host" | awk 'NR==1{print $1}')
    if [[ -n "$proxy_ip" ]]; then
      allow_cidrs+=("${proxy_ip}/32")
    fi
  fi
fi

allow_cidrs_csv=$(IFS=,; echo "${allow_cidrs[*]}")

HUGEPAGES_SET=(on off)
CACHE_MODES=(cold warm)
VM_SPECS=("1:512" "2:1024" "4:2048")

block_reason=""

extract_field() {
  local key="$1" file="$2"
  awk -v k="$key" '{for(i=1;i<=NF;i++){if($i==k){print $(i-1); exit}}}' "$file"
}

for hp in "${HUGEPAGES_SET[@]}"; do
  for cache_mode in "${CACHE_MODES[@]}"; do
    for spec in "${VM_SPECS[@]}"; do
      vcpu="${spec%%:*}"
      ram="${spec##*:}"
      disk=$((ram * 4))
      case_id="hp-${hp}_cache-${cache_mode}_v${vcpu}_r${ram}"
      log_file="$OUT_DIR/logs/base_${case_id}.log"

      if [[ -n "$block_reason" ]]; then
        printf 'base,%s,%s,%s,%s,%s,blocked,0,100,,,,,0,1,0,1,%s,%s\n' \
          "$hp" "$cache_mode" "$vcpu" "$ram" "$disk" "$block_reason" "$log_file" >> "$CSV"
        continue
      fi

      if [[ "$cache_mode" == "cold" ]]; then
        rm -rf "$HOME/.cache/e2b-orchestrator-benchmark"
      fi

      start_ms=$(date +%s%3N)
      set +e
      (
        cd "$ROOT_DIR/packages/orchestrator/benchmarks"
        sudo env \
          GOTOOLCHAIN=auto \
          E2B_SANDBOX_NAMESERVER="$host_nameserver" \
          E2B_SANDBOX_HTTP_PROXY="$proxy_url" \
          E2B_SANDBOX_HTTPS_PROXY="$https_proxy_url" \
          E2B_SANDBOX_NO_PROXY="$no_proxy_url" \
          ALLOW_SANDBOX_INTERNAL_CIDRS="$allow_cidrs_csv" \
          BENCH_HUGEPAGES="$hp" \
          BENCH_VCPU="$vcpu" \
          BENCH_RAM_MB="$ram" \
          BENCH_DISK_MB="$disk" \
          go test -run='^$' -bench=BenchmarkBaseImageLaunch -benchtime=1x -timeout=25m -v
      ) >"$log_file" 2>&1
      rc=$?
      set -e
      end_ms=$(date +%s%3N)
      total_ms=$((end_ms - start_ms))

      if [[ $rc -eq 0 ]]; then
        avg_ms_raw=$(extract_field "ns/op" "$log_file" || true)
        avg_ms=$(awk -v ns="${avg_ms_raw:-0}" 'BEGIN{printf "%.3f", ns/1000000.0}')
        printf 'base,%s,%s,%s,%s,%s,passed,100,0,%s,%s,%s,%s,%s,1,1,0,,%s\n' \
          "$hp" "$cache_mode" "$vcpu" "$ram" "$disk" "$avg_ms" "$avg_ms" "$avg_ms" "$avg_ms" "$total_ms" "$log_file" >> "$CSV"
      else
        err=$(grep -m1 -E "Temporary failure resolving|Unable to locate package|toomanyrequests|error provisioning sandbox|panic:" "$log_file" | sed 's/,/;/g' || true)
        if [[ -z "$err" ]]; then
          err="benchmark_failed"
        fi
        printf 'base,%s,%s,%s,%s,%s,failed,0,100,,,,,%s,1,0,1,%s,%s\n' \
          "$hp" "$cache_mode" "$vcpu" "$ram" "$disk" "$total_ms" "$err" "$log_file" >> "$CSV"

        if grep -q "Temporary failure resolving 'deb.debian.org'" "$log_file"; then
          block_reason="dns_resolution_failure_in_guest"
        fi
      fi
    done
  done
done

echo "$CSV"
