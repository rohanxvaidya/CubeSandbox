#!/usr/bin/env bash
set -euo pipefail

# CubeSandbox Benchmark Runner
# Based on cubesandbox_benchmark.md requirements

BENCH_DIR="/home/mz/cubeSandbox/CubeSandbox/examples/cube-bench"
BASE_REPORT_DIR="/home/mz/cubeSandbox/benchmark_reports/288c576g_sweep"
RUN_TS="$(date +%Y%m%d_%H%M%S)"
RUN_DIR="${BASE_REPORT_DIR}/${RUN_TS}"
REPORT_DIR="${RUN_DIR}/reports"
LOG_FILE="${RUN_DIR}/run_${RUN_TS}.log"
#TEMPLATE_ID="tpl-55bc1d6526f242bd850e5c4d"
#TEMPLATE_ID="tpl-c8cd0384d243446da5521dc0"
#TEMPLATE_ID="tpl-f540d53d04214ff78297fa64"
#TEMPLATE_ID="tpl-8f05caca166b40349732174a"
TEMPLATE_ID=${CUBE_TEMPLATE_ID:-"tpl-1ce0bcd8f32b40d595861553"}
API_URL="http://127.0.0.1:3000"
API_KEY="e2b_000000"
CLEANUP_SCRIPT="/home/mz/cleanup_sandboxes.sh"


cpupower -c all frequency-set -g performance

# Test cases definition: (concurrency, request1, request2, ...)
declare -a TEST_CASES=(
#  "1:1:10:20:50:100"
#  "5:50:100:200:400"
#  "10:100:200:300:400:500"
#  "20:100:200:400:600:800"
#  "50:500:1000:2000:3000:4000:5000"
#  "100:1000:2000:3000:4000:5000"
#  "120:1000:2000:3000:4000:5000"
#  "160:1000:2000:3000:4000:5000"
#  "200:1000:2000:3000:4000:5000:6000"
#  "250:1000:2000:3000:4000:5000:6000"
#  "400:4000:5000:6000:7000:8000:9000:10000"
#  "500:5000:6000:7000:8000:9000:10000"


 "100:1000:2000:3000:4000"
 "110:1100:2200:3300:4400"
 "120:1200:2400:3600:4800"
 "130:1300:2600:3900:5200"
 "140:1400:2800:4200:5600"
 "150:1500:3000:4500:6000"
 "160:1600:3200:4800:6400"
 "170:1700:3400:5100:6800"
 "180:1800:3600:5400:7200"
 "190:1900:3800:5700:7600"
 "200:2000:4000:6000:8000"
 "210:2100:4200:6300:8400"
 "220:2200:4400:6600:8800"
 "230:2300:4600:6900:9200"
 "240:2400:4800:7200:9600"
 "250:2500:5000:7500:10000"
 "260:2600:5200:7800:10400"
 "270:2700:5400:8100:10800"
 "280:2800:5600:8400:11200"
 "290:2900:5800:8700:11600"
 "300:3000:6000:9000:12000"
 "310:3100:6200:9300:12400"
 "320:3200:6400:9600:12800"
 "330:3300:6600:9900:13200"
 "340:3400:6800:10200:13600"
 "350:3500:7000:10500:14000"


)

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Helper functions — write to stdout and tee into LOG_FILE if set
log_info() {
  local msg="[INFO] $1"
  echo -e "${GREEN}${msg}${NC}"
  [ -n "${LOG_FILE:-}" ] && echo "$(date '+%Y-%m-%d %H:%M:%S') ${msg}" >> "${LOG_FILE}"
}

log_warn() {
  local msg="[WARN] $1"
  echo -e "${YELLOW}${msg}${NC}"
  [ -n "${LOG_FILE:-}" ] && echo "$(date '+%Y-%m-%d %H:%M:%S') ${msg}" >> "${LOG_FILE}"
}

log_error() {
  local msg="[ERROR] $1"
  echo -e "${RED}${msg}${NC}"
  [ -n "${LOG_FILE:-}" ] && echo "$(date '+%Y-%m-%d %H:%M:%S') ${msg}" >> "${LOG_FILE}"
}

check_health() {
  log_info "Checking CubeSandbox health..."
  if /usr/local/services/cubetoolbox/scripts/one-click/quickcheck.sh >/dev/null 2>&1; then
    log_info "✓ Health check passed"
    return 0
  else
    log_error "Health check failed"
    return 1
  fi
}

cleanup_sandboxes() {
  if [ ! -x "${CLEANUP_SCRIPT}" ]; then
    log_error "Cleanup script missing or not executable: ${CLEANUP_SCRIPT}"
    return 1
  fi

  API_URL="${API_URL}" API_KEY="${API_KEY}" "${CLEANUP_SCRIPT}"
}

run_benchmark() {
  local concurrency=$1
  local requests=$2
  local output_file="${REPORT_DIR}/benchmark_${RUN_TS}_c${concurrency}_n${requests}.json"
  
  log_info "Running: concurrency=${concurrency}, requests=${requests}"
  
  cd "${BENCH_DIR}"
  ./bin/cube-bench \
    --no-tui \
    -m create-delete \
    -c "${concurrency}" \
    -n "${requests}" \
    -w 3 \
    -t "${TEMPLATE_ID}" \
    --api-url "${API_URL}" \
    --api-key "${API_KEY}" \
    -o "${output_file}" 2>&1 | tail -20
  
  if [ -f "${output_file}" ]; then
    log_info "✓ Report saved: ${output_file}"
    return 0
  else
    log_error "✗ Report generation failed"
    return 1
  fi
}

extract_metrics() {
  local json_file=$1
  
  jq -r '.create,.delete' "${json_file}" 2>/dev/null | jq -s '
    {
      create_avg: .[0].avg,
      create_min: .[0].min,
      create_p95: .[0].p95,
      create_max: .[0].max,
      delete_avg: .[1].avg,
      delete_min: .[1].min,
      delete_p95: .[1].p95,
      delete_max: .[1].max
    }
  '
}

# Main execution
main() {
  mkdir -p "${REPORT_DIR}"
  : > "${LOG_FILE}"   # create / truncate log file

  log_info "=== CubeSandbox Benchmark Suite ==="
  log_info "Run directory : ${RUN_DIR}"
  log_info "Reports dir   : ${REPORT_DIR}"
  log_info "Log file      : ${LOG_FILE}"
  
  local total_tests=0
  local passed_tests=0
  
  for test_case in "${TEST_CASES[@]}"; do
    IFS=':' read -ra PARTS <<< "$test_case"
    local concurrency=${PARTS[0]}
    
    log_info "Starting concurrency group: $concurrency"
    
    # Check health before each concurrency group
#    if ! check_health; then
#      log_error "Health check failed, skipping this group"
#      continue
#    fi
    
    # Run tests for each request count in this group
    for i in "${!PARTS[@]}"; do
      if [ $i -eq 0 ]; then continue; fi
      
      local requests=${PARTS[$i]}
      total_tests=$((total_tests + 1))

      # Cleanup before each benchmark test case
      if ! cleanup_sandboxes; then
        log_error "Cleanup failed before test c=${concurrency}, n=${requests}, skipping this case"
        continue
      fi
      
      if run_benchmark "$concurrency" "$requests"; then
        passed_tests=$((passed_tests + 1))
      fi
      
      # Wait between tests
      sleep 30
      echo 3 > /proc/sys/vm/drop_caches
    done
    
    log_info "Completed concurrency group: $concurrency"
    echo ""
  done
  
  log_info "=== Benchmark Suite Complete ==="
  log_info "Passed: $passed_tests/$total_tests tests"
  log_info "Reports saved in : ${REPORT_DIR}"
  log_info "Full log at      : ${LOG_FILE}"
}

# Run main
main "$@"
