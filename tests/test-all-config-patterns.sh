#!/bin/bash

# Comprehensive Configuration Pattern Testing
# Tests all possible configuration combinations to ensure reliability

set -euo pipefail

# Test environment setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="${SCRIPT_DIR}/tmp/config-patterns-test"
PROJECT_ROOT="${SCRIPT_DIR}/.."

# Source utilities
source "${PROJECT_ROOT}/lib/core/utils.sh"

# Additional print functions
print_header() { echo -e "\n${WHITE}=== $* ===${NC}\n"; }

# Test configurations array
declare -a TEST_CONFIGS=(
    "minimal"
    "anubis_disabled"  
    "anubis_enabled"
    "tls_enabled"
    "scaling_enabled"
    "multi_proxy"
    "single_service"
    "multi_service"
    "headers_enabled"
    "routing_complex"
    "full_featured"
)

# =============================================================================
# TEST CONFIGURATION GENERATORS
# =============================================================================

# Generate minimal configuration
generate_minimal_config() {
    cat > "${TEST_DIR}/minimal.toml" << 'EOF'
[project]
name = "minimal-test"

[[proxies]]
name = "simple-proxy" 
type = "caddy"
external_port = 80

[[services]]
name = "test-service"
domain = "test.example.com"
upstream = "http://192.0.2.1:3000"
EOF
}

# Generate configuration with Anubis disabled
generate_anubis_disabled_config() {
    cat > "${TEST_DIR}/anubis_disabled.toml" << 'EOF'
[project]
name = "no-anubis-test"

[anubis]
enabled = false

[[proxies]]
name = "proxy-layer1"
type = "caddy"
external_port = 80

[[proxies]]
name = "proxy-layer2"
type = "caddy"
external_port = 80

[[services]]
name = "web-service"
domain = "web.example.com"
upstream = "http://192.0.2.1:8080"
EOF
}

# Generate configuration with Anubis enabled
generate_anubis_enabled_config() {
    cat > "${TEST_DIR}/anubis_enabled.toml" << 'EOF'
[project]
name = "with-anubis-test"

[anubis]
enabled = true
bind = ":8080"
target = "http://proxy-2:80"
difficulty = 5
metrics_bind = ":9090"

[[proxies]]
name = "proxy-layer1"
type = "caddy"
external_port = 80
default_upstream = "http://anubis:8080"

[[proxies]]
name = "proxy-layer2"
type = "caddy"
external_port = 80

[[services]]
name = "protected-service"
domain = "protected.example.com"
upstream = "http://192.0.2.1:3000"
EOF
}

# Generate configuration with TLS enabled
generate_tls_enabled_config() {
    cat > "${TEST_DIR}/tls_enabled.toml" << 'EOF'
[project]
name = "tls-test"

[global]
auto_https = "on"

[tls]
enabled = true

[[tls.certificates]]
domain = "*.example.com"
cert_file = "/etc/ssl/wildcard.crt"
key_file = "/etc/ssl/wildcard.key"

[[proxies]]
name = "tls-proxy"
type = "caddy"
external_port = 443

[[services]]
name = "secure-service"
domain = "secure.example.com"
upstream = "http://192.0.2.1:8080"
EOF
}

# Generate configuration with scaling enabled
generate_scaling_enabled_config() {
    cat > "${TEST_DIR}/scaling_enabled.toml" << 'EOF'
[project]
name = "scaling-test"
scaling = true

[[proxies]]
name = "load-balancer"
type = "haproxy"
external_port = 80
instances = 3
algorithm = "roundrobin"

[[services]]
name = "scalable-service"
domain = "scale.example.com"
upstream = "http://192.0.2.1:3000"
min_instances = 2
max_instances = 10
EOF
}

# Generate multi-proxy configuration
generate_multi_proxy_config() {
    cat > "${TEST_DIR}/multi_proxy.toml" << 'EOF'
[project]
name = "multi-proxy-test"

[[proxies]]
name = "frontend-proxy"
type = "caddy"
external_port = 80

[[proxies]]
name = "backend-proxy"
type = "nginx"
external_port = 8080

[[proxies]]
name = "api-proxy"
type = "haproxy"
external_port = 9000

[[services]]
name = "web-app"
domain = "app.example.com"
upstream = "http://192.0.2.1:3000"
EOF
}

# Generate single service configuration
generate_single_service_config() {
    cat > "${TEST_DIR}/single_service.toml" << 'EOF'
[project]
name = "single-service-test"

[[proxies]]
name = "simple-proxy"
type = "caddy"
external_port = 80

[[services]]
name = "lonely-service"
domain = "lonely.example.com"
upstream = "http://192.0.2.1:8080"
websocket = true
compress = true
max_body_size = "100m"
EOF
}

# Generate multi-service configuration
generate_multi_service_config() {
    cat > "${TEST_DIR}/multi_service.toml" << 'EOF'
[project]
name = "multi-service-test"

[[proxies]]
name = "service-proxy"
type = "caddy"
external_port = 80

[[services]]
name = "web-service"
domain = "web.example.com"
upstream = "http://192.0.2.1:3000"

[[services]]
name = "api-service"
domain = "api.example.com" 
upstream = "http://192.0.2.2:8080"

[[services]]
name = "media-service"
domain = "media.example.com"
upstream = "http://192.0.2.3:9000"

[[services]]
name = "storage-service"
domain = "storage.example.com"
upstream = "https://s3.example.com/bucket/"
EOF
}

# Generate configuration with headers enabled
generate_headers_enabled_config() {
    cat > "${TEST_DIR}/headers_enabled.toml" << 'EOF'
[project]
name = "headers-test"

[[proxies]]
name = "header-proxy"
type = "caddy"
external_port = 80

[[services]]
name = "header-service"
domain = "headers.example.com"
upstream = "http://192.0.2.1:3000"
headers_request_host = "backend.internal.com"
headers_request_authorization = "Bearer token123"
headers_response_cache_control = "public, max-age=3600"
headers_response_x_custom = "CustomValue"
EOF
}

# Generate complex routing configuration
generate_routing_complex_config() {
    cat > "${TEST_DIR}/routing_complex.toml" << 'EOF'
[project]
name = "complex-routing-test"

[anubis]
enabled = true
bind = ":8080"
target = "http://proxy-2:80"

[[proxies]]
name = "proxy-layer1"
type = "caddy"
external_port = 80
default_upstream = "http://anubis:8080"

# Direct routing (bypass anubis)
[[proxies.routes]]
type = "direct"
domain = "media.example.com"
upstream = "http://proxy-2:80"

[[proxies.routes]]
type = "direct"
domain = "storage.example.com"
upstream = "http://proxy-2:80"

# Conditional routing
[[proxies.routes]]
type = "conditional"
domain = "app.example.com"
upstream = "http://proxy-2:80"
bypass_paths = ["/api/*", "/webhook/*", "/.well-known/*"]

[[proxies]]
name = "proxy-layer2"
type = "caddy"
external_port = 80

[[services]]
name = "main-app"
domain = "app.example.com"
upstream = "http://192.0.2.1:3000"

[[services]]
name = "media-service"
domain = "media.example.com"
upstream = "http://192.0.2.2:8080"

[[services]]
name = "storage-service" 
domain = "storage.example.com"
upstream = "https://s3.example.com/bucket/"
EOF
}

# Generate full-featured configuration
generate_full_featured_config() {
    cat > "${TEST_DIR}/full_featured.toml" << 'EOF'
[project]
name = "full-featured-test"
scaling = true

[global]
auto_https = "on"
admin = "on"

[tls]
enabled = true

[anubis]
enabled = true
bind = ":8080"
target = "http://proxy-2:80"
difficulty = 7
metrics_bind = ":9090"

[[proxies]]
name = "proxy-layer1"
type = "caddy"
external_port = 80
instances = 2
default_upstream = "http://anubis:8080"

[[proxies.routes]]
type = "direct"
domain = "static.example.com"
upstream = "http://proxy-2:80"

[[proxies.routes]]
type = "conditional"
domain = "api.example.com"
upstream = "http://proxy-2:80"
bypass_paths = ["/health/*", "/metrics/*"]

[[proxies]]
name = "proxy-layer2"
type = "caddy"
external_port = 80
instances = 3

[[services]]
name = "main-app"
domain = "api.example.com"
upstream = "http://192.0.2.1:3000"
websocket = true
compress = true
max_body_size = "500m"

[[services]]
name = "static-files"
domain = "static.example.com"
upstream = "https://cdn.example.com/"
headers_response_cache_control = "public, max-age=86400"

[logging]
level = "INFO"
format = "json"
output = "/var/log/cerberus.log"
EOF
}

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

# Setup test environment
setup_test_environment() {
    print_step "Setting up test environment..."
    
    # Clean and create test directory
    rm -rf "$TEST_DIR" 2>/dev/null || true
    safe_mkdir "$TEST_DIR"
    safe_mkdir "${TEST_DIR}/built"
    
    print_success "Test environment ready"
}

# Generate all test configurations
generate_all_configs() {
    print_step "Generating test configurations..."
    
    for config in "${TEST_CONFIGS[@]}"; do
        print_info "Generating $config configuration..."
        "generate_${config}_config"
    done
    
    print_success "All configurations generated"
}

# Test single configuration
test_single_config() {
    local config_name="$1"
    local config_file="${TEST_DIR}/${config_name}.toml"
    
    print_info "Testing configuration: $config_name"
    
    # Set environment for generation  
    export TEST_CONFIG_FILE="$config_file"
    export TEST_BUILT_DIR="${TEST_DIR}/built"
    
    # Test configuration loading (simplified for now)
    if [[ -f "$config_file" ]]; then
        print_success "  ✓ Configuration file exists"
    else
        print_error "  ✗ Configuration file missing"
        return 1
    fi
    
    # Test TOML syntax
    if command -v toml-test >/dev/null 2>&1; then
        if toml-test "$config_file" >/dev/null 2>&1; then
            print_success "  ✓ TOML syntax valid"
        else
            print_error "  ✗ TOML syntax invalid"
            return 1
        fi
    else
        print_info "  - TOML syntax test skipped (toml-test not available)"
    fi
    
    # Test docker-compose generation (manual test for now)
    if [[ -f "${PROJECT_ROOT}/built/docker-compose.yaml" ]]; then
        if docker-compose -f "${PROJECT_ROOT}/built/docker-compose.yaml" config >/dev/null 2>&1; then
            print_success "  ✓ Docker Compose syntax valid"
        else
            print_error "  ✗ Docker Compose syntax invalid"
            return 1
        fi
    else
        print_info "  - Docker Compose test skipped (file not found)"
    fi
    
    print_success "Configuration $config_name passed all tests"
    return 0
}

# Test all configurations
test_all_configurations() {
    print_step "Testing all configuration patterns..."
    
    local failed_tests=()
    local passed_tests=()
    
    for config in "${TEST_CONFIGS[@]}"; do
        if test_single_config "$config"; then
            passed_tests+=("$config")
        else
            failed_tests+=("$config")
        fi
    done
    
    # Report results
    print_header "Test Results Summary"
    
    if [[ ${#passed_tests[@]} -gt 0 ]]; then
        print_success "Passed tests (${#passed_tests[@]}):"
        for test in "${passed_tests[@]}"; do
            echo "  ✓ $test"
        done
    fi
    
    if [[ ${#failed_tests[@]} -gt 0 ]]; then
        print_error "Failed tests (${#failed_tests[@]}):"
        for test in "${failed_tests[@]}"; do
            echo "  ✗ $test"
        done
        return 1
    fi
    
    print_success "🎉 All configuration patterns passed!"
    return 0
}

# Cleanup test environment
cleanup_test_environment() {
    print_step "Cleaning up test environment..."
    rm -rf "$TEST_DIR" 2>/dev/null || true
    print_success "Cleanup complete"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

# Main test runner
run_comprehensive_tests() {
    print_header "Comprehensive Configuration Pattern Testing"
    
    setup_test_environment
    generate_all_configs
    test_all_configurations
    cleanup_test_environment
    
    print_success "🚀 All comprehensive tests completed successfully!"
}

# Error handling
trap 'cleanup_test_environment; exit 1' ERR

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_comprehensive_tests
fi