#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SCRIPT_DIR
export BUILT_DIR="${SCRIPT_DIR}/tests/tmp"

mkdir -p "${SCRIPT_DIR}/tests/tmp"

source "${SCRIPT_DIR}/lib/core/utils.sh"
source "${SCRIPT_DIR}/lib/core/config-simple.sh"

TEST_CONFIG="${SCRIPT_DIR}/tests/tmp/debug-config.toml"

# Create very simple test config
cat > "$TEST_CONFIG" << 'EOF'
[project]
name = "debug-test"

[[proxies]]
name = "proxy1"
type = "nginx"

[[proxies]]
name = "proxy2"
type = "nginx"
EOF

echo "Loading config..."
config_load "$TEST_CONFIG"

echo "Getting project name..."
project_name=$(config_get_string "project.name")
echo "Project name: $project_name"

echo "Getting proxy count..."
proxy_count=$(config_get_array_table_count "proxies")
echo "Proxy count: $proxy_count"

echo "Test completed successfully"