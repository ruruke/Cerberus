#!/bin/bash

# Debug proxy config generation

set -euo pipefail

# Setup paths
SCRIPT_DIR="/mnt/e/codeing/shellscript/cerberus"
export SCRIPT_DIR
export BUILT_DIR="${SCRIPT_DIR}/tests/tmp"

echo "Debugging Proxy Config Generator"
echo "================================"

# Load libraries
source "${SCRIPT_DIR}/lib/core/utils.sh"
source "${SCRIPT_DIR}/lib/core/config-simple.sh"
source "${SCRIPT_DIR}/lib/generators/proxy-configs.sh"

# Create multi-proxy config
cat > "${SCRIPT_DIR}/tests/tmp/debug-proxy.toml" << 'EOF'
[project]
name = "debug-test"

[[proxies]]
name = "nginx-proxy"
type = "nginx"
external_port = 8080
internal_port = 80

[[proxies]]
name = "caddy-proxy"
type = "caddy"
external_port = 8081
internal_port = 80

[[proxies]]
name = "haproxy-proxy"
type = "haproxy"
external_port = 8082
internal_port = 80

[[services]]
name = "test-service"
domain = "test.example.com"
upstream = "http://backend:3000"
EOF

echo "1. Loading configuration..."
config_load "${SCRIPT_DIR}/tests/tmp/debug-proxy.toml"

echo "2. Checking proxy count..."
proxy_count=$(config_get_array_table_count "proxies")
echo "Total proxies: $proxy_count"

echo "3. Listing proxy configurations..."
for ((i=0; i<proxy_count; i++)); do
    name=$(config_get_string "proxies.${i}.name")
    type=$(config_get_string "proxies.${i}.type")
    echo "Proxy[$i]: $name ($type)"
done

echo "4. Generating configurations one by one..."
rm -rf "${BUILT_DIR}/proxy-configs"
for ((i=0; i<proxy_count && i<5; i++)); do  # Limit to 5 for safety
    echo "Generating config for proxy $i (max count: $proxy_count)..."
    name=$(config_get_string "proxies.${i}.name" "")
    type=$(config_get_string "proxies.${i}.type" "")
    echo "  Name: $name, Type: $type"
    
    if [[ -z "$name" || -z "$type" ]]; then
        echo "  ✗ Skipping: missing name or type"
        continue
    fi
    
    if generate_single_proxy_config "$i"; then
        echo "  ✓ Generated successfully"
    else
        echo "  ✗ Generation failed"
        break
    fi
done

echo "5. Listing generated files..."
if [[ -d "${BUILT_DIR}/proxy-configs" ]]; then
    find "${BUILT_DIR}/proxy-configs" -type f | sort
else
    echo "No proxy-configs directory found"
fi

echo
echo "Debug completed!"