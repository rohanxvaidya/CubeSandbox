#!/bin/bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: bash sandbox_verify.sh <template-id>"
  exit 2
fi

# Allow caller override; keep sensible defaults for local deployment.
export E2B_API_URL="${E2B_API_URL:-http://127.0.0.1:3000}"
export E2B_API_KEY="${E2B_API_KEY:-e2b_000000}"
export CUBE_TEMPLATE_ID="$1"

# Bypass enterprise HTTP(S) proxy for local Cube API and sandbox domains.
BYPASS_LIST="127.0.0.1,localhost,.cube.app,10.112.120.6"
export NO_PROXY="${NO_PROXY:+$NO_PROXY,}${BYPASS_LIST}"
export no_proxy="${no_proxy:+$no_proxy,}${BYPASS_LIST}"

# Auto-detect a valid CA/cert file for sandbox TLS endpoints.
CERT_CANDIDATES=(
  "/root/.local/share/mkcert/rootCA.pem"
  "/usr/local/services/cubetoolbox/cubeproxy/certs/cube.app+3.pem"
  "/etc/cube/ca/cube-root-ca.crt"
)

for cert in "${CERT_CANDIDATES[@]}"; do
  if [[ -f "$cert" ]]; then
    export SSL_CERT_FILE="$cert"
    break
  fi
done

if [[ -n "${SSL_CERT_FILE:-}" ]]; then
  echo "[verify] SSL_CERT_FILE=$SSL_CERT_FILE"
else
  echo "[verify] WARNING: no cert file found, TLS verification may fail"
fi

echo "[verify] E2B_API_URL=$E2B_API_URL"
echo "[verify] CUBE_TEMPLATE_ID=$CUBE_TEMPLATE_ID"
echo "[verify] NO_PROXY=$NO_PROXY"

python3 -m pip install -q e2b-code-interpreter
python3 hello.py
