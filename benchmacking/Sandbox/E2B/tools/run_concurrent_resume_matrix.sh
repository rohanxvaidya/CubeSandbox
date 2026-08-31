#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${1:-$ROOT_DIR/benchmark_reports/e2b_concurrent_$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT_DIR/logs"

CSV="$OUT_DIR/concurrent_resume_matrix.csv"
cat > "$CSV" <<'EOF'
method,hugepages,cache_mode,vcpu,ram_mb,disk_mb,concurrency,status,success_rate,fail_rate,avg_ms,p50_ms,p95_ms,p99_ms,total_ms,sandboxes_total,ok_count,fail_count,wall_clock_ms,error_signature,log_file
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
CONCURRENCY_LEVELS=(1 2 4 8 16)

block_reason=""

metric_from_line() {
  local line="$1" key="$2"
  awk -v k="$key" '{for(i=1;i<=NF;i++){if($i==k){print $(i-1); exit}}}' <<<"$line"
}

for hp in "${HUGEPAGES_SET[@]}"; do
  for cache_mode in "${CACHE_MODES[@]}"; do
    for spec in "${VM_SPECS[@]}"; do
      vcpu="${spec%%:*}"
      ram="${spec##*:}"
      disk=$((ram * 4))
      for conc in "${CONCURRENCY_LEVELS[@]}"; do
        case_id="hp-${hp}_cache-${cache_mode}_v${vcpu}_r${ram}_c${conc}"
        log_file="$OUT_DIR/logs/concurrent_${case_id}.log"

        if [[ -n "$block_reason" ]]; then
          printf 'concurrent,%s,%s,%s,%s,%s,%s,blocked,0,100,,,,,0,%s,0,0,0,0,%s,%s\n' \
            "$hp" "$cache_mode" "$vcpu" "$ram" "$disk" "$conc" "$conc" "$block_reason" "$log_file" >> "$CSV"
          continue
        fi

        if [[ "$cache_mode" == "cold" ]]; then
          rm -rf "$HOME/.cache/e2b-orchestrator-benchmark"
        fi

        if [[ "$hp" == "on" ]]; then
          disable_hp=false
        else
          disable_hp=true
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
            DISABLE_HUGE_PAGES="$disable_hp" \
            CONCURRENCY_LEVELS="$conc" \
            BENCH_VCPU="$vcpu" \
            BENCH_RAM_MB="$ram" \
            BENCH_DISK_MB="$disk" \
            go test -run='^$' -bench="BenchmarkConcurrentResume/concurrency-${conc}" -benchtime=1x -timeout=30m -v
        ) >"$log_file" 2>&1
        rc=$?
        set -e
        end_ms=$(date +%s%3N)
        total_ms=$((end_ms - start_ms))

        if [[ $rc -eq 0 ]]; then
          line=$(grep -E "^BenchmarkConcurrentResume/concurrency-${conc}" "$log_file" | tail -n1 || true)
          ok_line=$(grep -E "concurrency=${conc}:" "$log_file" | tail -n1 || true)

          avg_ms=$(metric_from_line "$line" "avg-ms")
          p50_ms=$(metric_from_line "$line" "p50-ms")
          p95_ms=$(metric_from_line "$line" "p95-ms")
          p99_ms=$(metric_from_line "$line" "p99-ms")
          wall_ms=$(metric_from_line "$line" "wall-clock-ms")

          ok_count=$(sed -nE "s/.*concurrency=${conc}: ([0-9]+) ok, ([0-9]+) fail.*/\1/p" <<<"$ok_line")
          fail_count=$(sed -nE "s/.*concurrency=${conc}: ([0-9]+) ok, ([0-9]+) fail.*/\2/p" <<<"$ok_line")
          ok_count=${ok_count:-$conc}
          fail_count=${fail_count:-0}
          total=$((ok_count + fail_count))
          if [[ $total -gt 0 ]]; then
            success_rate=$(awk -v o="$ok_count" -v t="$total" 'BEGIN{printf "%.2f", (o*100.0)/t}')
            fail_rate=$(awk -v f="$fail_count" -v t="$total" 'BEGIN{printf "%.2f", (f*100.0)/t}')
          else
            success_rate=0
            fail_rate=0
          fi

          printf 'concurrent,%s,%s,%s,%s,%s,%s,passed,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,,%s\n' \
            "$hp" "$cache_mode" "$vcpu" "$ram" "$disk" "$conc" "$success_rate" "$fail_rate" \
            "${avg_ms:-}" "${p50_ms:-}" "${p95_ms:-}" "${p99_ms:-}" "$total_ms" "$total" "$ok_count" "$fail_count" "${wall_ms:-}" "$log_file" >> "$CSV"
        else
          err=$(grep -m1 -E "Temporary failure resolving|Unable to locate package|toomanyrequests|error provisioning sandbox|panic:" "$log_file" | sed 's/,/;/g' || true)
          if [[ -z "$err" ]]; then
            err="benchmark_failed"
          fi
          printf 'concurrent,%s,%s,%s,%s,%s,%s,failed,0,100,,,,,%s,%s,0,%s,,%s,%s\n' \
            "$hp" "$cache_mode" "$vcpu" "$ram" "$disk" "$conc" "$total_ms" "$conc" "$conc" "$err" "$log_file" >> "$CSV"

          if grep -q "Temporary failure resolving 'deb.debian.org'" "$log_file"; then
            block_reason="dns_resolution_failure_in_guest"
          fi
        fi
      done
    done
  done
done

echo "$CSV"
