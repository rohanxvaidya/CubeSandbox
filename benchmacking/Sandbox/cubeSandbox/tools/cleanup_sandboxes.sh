#!/usr/bin/env bash
set -euo pipefail

API_URL="${API_URL:-http://127.0.0.1:3000}"
API_KEY="${API_KEY:-e2b_000000}"
CURL_TIMEOUT="${CURL_TIMEOUT:-15}"
RETRY_COUNT="${RETRY_COUNT:-3}"
RETRY_BACKOFF_SEC="${RETRY_BACKOFF_SEC:-1}"

QUICKCHECK_BIN="/usr/local/services/cubetoolbox/scripts/one-click/quickcheck.sh"

log_info() {
  echo "[INFO] $*"
}

log_warn() {
  echo "[WARN] $*" >&2
}

log_error() {
  echo "[ERROR] $*" >&2
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_error "Missing required command: $1"
    exit 1
  fi
}

api_get() {
  local path="$1"
  curl -fsS \
    --max-time "${CURL_TIMEOUT}" \
    -H "Authorization: Bearer ${API_KEY}" \
    "${API_URL}${path}"
}

check_environment() {
  log_info "Checking CubeSandbox environment"

  require_cmd curl
  require_cmd jq

  if [[ -x "${QUICKCHECK_BIN}" ]]; then
    if "${QUICKCHECK_BIN}" >/dev/null 2>&1; then
      log_info "quickcheck passed"
    else
      log_warn "quickcheck failed; continue with API-level cleanup"
    fi
  else
    log_warn "quickcheck not found at ${QUICKCHECK_BIN}; skipping"
  fi

  local health
  if ! health="$(api_get "/health")"; then
    log_error "CubeAPI health check failed at ${API_URL}/health"
    exit 1
  fi

  local status
  status="$(echo "${health}" | jq -r '.status // empty' 2>/dev/null || true)"
  if [[ -n "${status}" && "${status}" != "ok" ]]; then
    log_warn "Health response status is '${status}', continue with cleanup"
  fi

  log_info "CubeAPI reachable: ${API_URL}"
}

list_sandbox_ids() {
  local resp
  resp="$(api_get "/sandboxes")"

  echo "${resp}" | jq -r '
    (if type == "array" then .
     elif (type == "object" and has("items")) then .items
     elif (type == "object" and has("data")) then .data
     else [] end)
    | .[]
    | .sandboxID // .sandboxId // .id // empty
  '
}

delete_one_sandbox() {
  local sandbox_id="$1"
  local tmp_body
  tmp_body="$(mktemp)"

  local attempt
  for attempt in $(seq 1 "${RETRY_COUNT}"); do
    local code
    code="$(curl -sS -o "${tmp_body}" -w "%{http_code}" \
      --max-time "${CURL_TIMEOUT}" \
      -X DELETE \
      -H "Authorization: Bearer ${API_KEY}" \
      "${API_URL}/sandboxes/${sandbox_id}" || true)"

    if [[ "${code}" == "200" || "${code}" == "202" || "${code}" == "204" || "${code}" == "404" ]]; then
      rm -f "${tmp_body}"
      return 0
    fi

    if [[ "${attempt}" -lt "${RETRY_COUNT}" ]]; then
      log_warn "Delete sandbox ${sandbox_id} failed (HTTP ${code}), retry ${attempt}/${RETRY_COUNT}"
      sleep "${RETRY_BACKOFF_SEC}"
    fi
  done

  log_error "Delete sandbox ${sandbox_id} failed after ${RETRY_COUNT} attempts"
  if [[ -s "${tmp_body}" ]]; then
    log_error "Last response: $(head -c 300 "${tmp_body}")"
  fi
  rm -f "${tmp_body}"
  return 1
}

main() {
  check_environment

  mapfile -t sandbox_ids < <(list_sandbox_ids)

  if [[ "${#sandbox_ids[@]}" -eq 0 ]]; then
    log_info "No sandbox found, nothing to clean"
    exit 0
  fi

  log_info "Found ${#sandbox_ids[@]} sandbox(es), start cleanup"

  local ok=0
  local fail=0
  local sid
  for sid in "${sandbox_ids[@]}"; do
    if delete_one_sandbox "${sid}"; then
      ok=$((ok + 1))
    else
      fail=$((fail + 1))
    fi
  done

  mapfile -t remaining < <(list_sandbox_ids)
  log_info "Cleanup done: deleted=${ok}, failed=${fail}, remaining=${#remaining[@]}"

  if [[ "${#remaining[@]}" -gt 0 ]]; then
    log_error "Some sandbox still remain"
    printf '%s\n' "${remaining[@]}" >&2
    exit 1
  fi

  if [[ "${fail}" -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
