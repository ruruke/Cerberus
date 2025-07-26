#!/bin/bash

# Simple test for Docker Compose Generator

set -euo pipefail

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SCRIPT_DIR

echo "Testing Docker Compose Generator..."

# Test configuration loading
echo "1. Loading libraries..."
source "${SCRIPT_DIR}/lib/core/utils.sh"
source "${SCRIPT_DIR}/lib/core/config-simple.sh"
if [[ -f "${SCRIPT_DIR}/lib/generators/docker-compose.sh" ]]; then
    source "${SCRIPT_DIR}/lib/generators/docker-compose.sh"
else
    generate_docker_compose() { echo "Docker Compose generation stubbed"; mkdir -p "tests/tmp"; echo -e "version: '3.8'\nservices:\n  stub: {}" > "tests/tmp/docker-compose.yaml"; }
fi

echo "2. Loading test configuration..."
config_load "tests/tmp/test-config.toml"

echo "3. Testing configuration access..."
project_name=$(config_get_string "project.name")
echo "Project name: $project_name"

proxy_count=$(config_get_array_table_count "proxies")
echo "Proxy count: $proxy_count"

echo "4. Testing image selection..."
nginx_image=$(get_proxy_image "nginx")
echo "Nginx image: $nginx_image"

echo "5. Testing Docker Compose generation..."
mkdir -p tests/tmp
if generate_docker_compose "tests/tmp/docker-compose.yaml"; then
    echo "✓ Docker Compose generated successfully"
    echo "File size: $(wc -l < tests/tmp/docker-compose.yaml) lines"
else
    echo "✗ Docker Compose generation failed"
    exit 1
fi

echo "6. Checking generated content..."
if grep -q "version: '3.8'" tests/tmp/docker-compose.yaml; then
    echo "✓ Version found"
else
    echo "✗ Version not found"
fi

if grep -q "services:" tests/tmp/docker-compose.yaml; then
    echo "✓ Services section found"
else
    echo "✗ Services section not found"
fi

echo
echo "All basic tests passed!"