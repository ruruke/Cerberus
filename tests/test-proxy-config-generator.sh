#!/bin/bash

# Test script for Proxy Configuration Generator

set -euo pipefail

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SCRIPT_DIR
export BUILT_DIR="${SCRIPT_DIR}/tests/tmp"

echo "Testing Proxy Configuration Generator..."
echo "======================================"

# Load libraries
source "${SCRIPT_DIR}/lib/core/utils.sh"
source "${SCRIPT_DIR}/lib/core/config-simple.sh"
source "${SCRIPT_DIR}/lib/generators/proxy-configs.sh"

# Test configuration
TEST_CONFIG="${SCRIPT_DIR}/tests/tmp/test-config.toml"
TEST_OUTPUT_DIR="${SCRIPT_DIR}/tests/tmp/proxy-configs"

# Clean and setup
rm -rf "$TEST_OUTPUT_DIR"

echo "1. Loading test configuration..."
config_load "$TEST_CONFIG"

echo "2. Generating proxy configurations..."
if generate_proxy_configs; then
    echo "✓ Proxy configurations generated successfully"
else
    echo "✗ Proxy configuration generation failed"
    exit 1
fi

echo "3. Checking generated files..."
# Check proxy directories
for proxy_name in proxy proxy-2; do
    if [[ -d "$TEST_OUTPUT_DIR/$proxy_name" ]]; then
        echo "✓ Directory created for $proxy_name"
        
        # Check nginx configuration files
        if [[ -f "$TEST_OUTPUT_DIR/$proxy_name/nginx.conf" ]]; then
            echo "✓ nginx.conf created for $proxy_name"
            
            # Check content
            if grep -q "worker_processes auto" "$TEST_OUTPUT_DIR/$proxy_name/nginx.conf"; then
                echo "✓ nginx.conf contains expected content"
            fi
        fi
        
        # Check conf.d directory
        if [[ -d "$TEST_OUTPUT_DIR/$proxy_name/conf.d" ]]; then
            echo "✓ conf.d directory created for $proxy_name"
            
            # List generated service configs
            echo "  Service configurations:"
            for conf in "$TEST_OUTPUT_DIR/$proxy_name/conf.d"/*.conf; do
                if [[ -f "$conf" ]]; then
                    echo "  - $(basename "$conf")"
                fi
            done
        fi
    else
        echo "✗ Directory not created for $proxy_name"
    fi
done

echo "4. Testing different proxy types..."

# Create test config with different proxy types
cat > "${SCRIPT_DIR}/tests/tmp/multi-proxy-config.toml" << 'EOF'
[project]
name = "multi-proxy-test"

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

[[proxies]]
name = "traefik-proxy"
type = "traefik"
external_port = 8083
internal_port = 80

[[services]]
name = "test-service"
domain = "test.example.com"
upstream = "http://backend:3000"
websocket = true
compress = true
max_body_size = "10m"
EOF

echo "5. Loading multi-proxy configuration..."
config_load "${SCRIPT_DIR}/tests/tmp/multi-proxy-config.toml"

echo "6. Generating multi-proxy configurations..."
rm -rf "$TEST_OUTPUT_DIR"
if generate_proxy_configs; then
    echo "✓ Multi-proxy configurations generated successfully"
else
    echo "✗ Multi-proxy configuration generation failed"
    exit 1
fi

echo "7. Verifying different proxy types..."
# Check nginx
if [[ -f "$TEST_OUTPUT_DIR/nginx-proxy/nginx.conf" ]]; then
    echo "✓ Nginx configuration generated"
fi

# Check Caddy
if [[ -f "$TEST_OUTPUT_DIR/caddy-proxy/Caddyfile" ]]; then
    echo "✓ Caddyfile generated"
    if grep -q "test.example.com:80" "$TEST_OUTPUT_DIR/caddy-proxy/Caddyfile"; then
        echo "✓ Caddyfile contains service configuration"
    fi
fi

# Check HAProxy
if [[ -f "$TEST_OUTPUT_DIR/haproxy-proxy/haproxy.cfg" ]]; then
    echo "✓ HAProxy configuration generated"
    if grep -q "backend test-service_backend" "$TEST_OUTPUT_DIR/haproxy-proxy/haproxy.cfg"; then
        echo "✓ HAProxy contains backend configuration"
    fi
fi

# Check Traefik
if [[ -f "$TEST_OUTPUT_DIR/traefik-proxy/traefik.yml" ]]; then
    echo "✓ Traefik static configuration generated"
fi
if [[ -f "$TEST_OUTPUT_DIR/traefik-proxy/dynamic/config.yml" ]]; then
    echo "✓ Traefik dynamic configuration generated"
fi

echo "8. Testing configuration validation..."
if validate_proxy_configs; then
    echo "✓ Proxy configurations validated successfully"
else
    echo "✗ Proxy configuration validation failed"
fi

echo
echo "All tests completed!"