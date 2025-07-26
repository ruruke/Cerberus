#!/bin/bash

# Simple test for proxy config generation

set -euo pipefail

# Setup paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SCRIPT_DIR
export BUILT_DIR="${SCRIPT_DIR}/tests/tmp"

echo "Simple Proxy Config Generator Test"
echo "=================================="

# Load libraries
source "${SCRIPT_DIR}/lib/core/utils.sh"
source "${SCRIPT_DIR}/lib/core/config-simple.sh"
source "${SCRIPT_DIR}/lib/generators/proxy-configs.sh"

# Create simple test config
cat > "${SCRIPT_DIR}/tests/tmp/simple-proxy.toml" << 'EOF'
[project]
name = "simple-test"

[[proxies]]
name = "test-nginx"
type = "nginx"
external_port = 8080
internal_port = 80

[[services]]
name = "test-service"
domain = "test.example.com"
upstream = "http://backend:3000"
EOF

echo "1. Loading configuration..."
config_load "${SCRIPT_DIR}/tests/tmp/simple-proxy.toml"

echo "2. Checking configuration..."
proxy_count=$(config_get_array_table_count "proxies")
echo "Proxy count: $proxy_count"

echo "3. Generating single proxy config..."
rm -rf "${BUILT_DIR}/proxy-configs"
generate_single_proxy_config 0

echo "4. Checking generated files..."
if [[ -f "${BUILT_DIR}/proxy-configs/test-nginx/nginx.conf" ]]; then
    echo "✓ nginx.conf generated"
    echo "Content preview:"
    head -10 "${BUILT_DIR}/proxy-configs/test-nginx/nginx.conf"
else
    echo "✗ nginx.conf not generated"
fi

echo
echo "Test completed!"