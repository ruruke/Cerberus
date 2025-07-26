#!/bin/bash

# Test simple config parser

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Testing simple config parser..."

# Test 1: Load libraries
echo "1. Loading libraries..."
source "${SCRIPT_DIR}/lib/core/utils.sh"
source "${SCRIPT_DIR}/lib/core/config-simple.sh"

# Create test directory and config
mkdir -p "${SCRIPT_DIR}/tests/tmp"

# Use test fixture if available, otherwise create inline
if [[ -f "${SCRIPT_DIR}/tests/fixtures/test-config.toml" ]]; then
    cp "${SCRIPT_DIR}/tests/fixtures/test-config.toml" "${SCRIPT_DIR}/tests/tmp/test-config.toml"
else
    cat > "${SCRIPT_DIR}/tests/tmp/test-config.toml" << 'EOF'
[project]
name = "test-project"
version = "1.0.0"
scaling = true

[[proxies]]
name = "nginx-proxy"
type = "nginx"
external_port = 80
internal_port = 80

[[proxies]]
name = "haproxy-main"
type = "haproxy"
external_port = 443
internal_port = 443

[anubis]
enabled = true
bind = ":8080"
difficulty = 5

[[services]]
name = "web"
domain = "test.local"
upstream = "http://127.0.0.1:3000"
EOF
fi

# Test 2: Load configuration
echo "2. Loading test configuration..."
config_load "${SCRIPT_DIR}/tests/tmp/test-config.toml"

# Test 3: Basic access
echo "3. Testing basic access..."
project_name=$(config_get_string "project.name")
echo "Project name: $project_name"

# Test 4: Array table count
echo "4. Testing array table count..."
proxy_count=$(config_get_array_table_count "proxies")
echo "Proxy count: $proxy_count"

# Test 5: Access array table items
echo "5. Testing array table access..."
if [[ $proxy_count -gt 0 ]]; then
    proxy_name=$(config_get_string "proxies.0.name")
    proxy_type=$(config_get_string "proxies.0.type")
    echo "First proxy: $proxy_name ($proxy_type)"
fi

# Test 6: Boolean values
echo "6. Testing boolean values..."
scaling=$(config_get_bool "project.scaling")
anubis_enabled=$(config_get_bool "anubis.enabled")
echo "Scaling: $scaling, Anubis: $anubis_enabled"

echo "All tests completed successfully!"