#!/bin/bash

# Test simple config parser

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Testing simple config parser..."

# Test 1: Load libraries
echo "1. Loading libraries..."
source "${SCRIPT_DIR}/lib/core/utils.sh"
source "${SCRIPT_DIR}/lib/core/config-simple.sh"

# Test 2: Load configuration
echo "2. Loading test configuration..."
config_load "tests/tmp/test-config.toml"

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