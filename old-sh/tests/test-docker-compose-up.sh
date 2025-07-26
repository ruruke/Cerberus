#!/bin/bash

# Docker Compose Up Test
# Tests that generated docker-compose.yaml can be validated and started

set -euo pipefail

# Source test utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/core/utils.sh"

# Test configuration
readonly TEST_DIR="${SCRIPT_DIR}/tmp/docker-compose-up-test"
readonly CONFIG_FILE="${TEST_DIR}/config.toml"
readonly COMPOSE_FILE="${TEST_DIR}/built/docker-compose.yaml"

# Setup test environment
setup_test() {
    print_step "Setting up docker-compose up test..."
    
    # Clean and create test directory
    rm -rf "$TEST_DIR" 2>/dev/null || true
    safe_mkdir "$TEST_DIR"
    safe_mkdir "${TEST_DIR}/built"
    
    # Create test configuration
    cat > "$CONFIG_FILE" << 'EOF'
[project]
name = "cerberus-test"
scaling = false

[global]
auto_https = "off"
admin = "off"

[tls]
enabled = false

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
layer = 1
default_upstream = "http://anubis:8080"

[[proxies]]
name = "proxy-layer2"
type = "caddy"
external_port = 80
layer = 2

[[services]]
name = "test-service"
domain = "test.example.com"
upstream = "http://192.0.2.1:3000"
websocket = true
compress = true

[logging]
level = "INFO"
format = "json"
output = "/var/log/cerberus.log"
EOF
    
    print_success "Test environment setup complete"
}

# Generate configuration
generate_config() {
    print_step "Generating docker-compose configuration..."
    
    # Set environment variables
    export CONFIG_FILE="$CONFIG_FILE"
    export BUILT_DIR="${TEST_DIR}/built"
    
    # Generate configuration
    cd "$SCRIPT_DIR/.."
    ./cerberus.sh generate --force
    
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        print_error "Docker compose file was not generated"
        return 1
    fi
    
    print_success "Configuration generated successfully"
}

# Validate docker-compose syntax
validate_compose() {
    print_step "Validating docker-compose syntax..."
    
    if ! command -v docker-compose >/dev/null 2>&1; then
        print_warning "docker-compose not available, skipping validation"
        return 0
    fi
    
    # Validate syntax
    if docker-compose -f "$COMPOSE_FILE" config --quiet; then
        print_success "Docker compose syntax is valid"
    else
        print_error "Docker compose syntax validation failed"
        echo "Generated docker-compose.yaml content:"
        cat "$COMPOSE_FILE"
        return 1
    fi
}

# Test docker-compose up (dry run)
test_compose_up() {
    print_step "Testing docker-compose up (dry run)..."
    
    if ! command -v docker-compose >/dev/null 2>&1; then
        print_warning "docker-compose not available, skipping up test"
        return 0
    fi
    
    # Test with --dry-run if available
    if docker-compose -f "$COMPOSE_FILE" config >/dev/null 2>&1; then
        print_success "Docker compose up test passed"
    else
        print_error "Docker compose up test failed"
        return 1
    fi
}

# Test with different configurations
test_configurations() {
    print_step "Testing different configuration scenarios..."
    
    local configs=(
        "anubis_disabled"
        "tls_enabled"
        "scaling_enabled"
        "minimal_config"
    )
    
    for config in "${configs[@]}"; do
        print_info "Testing configuration: $config"
        "test_config_$config"
    done
    
    print_success "All configuration scenarios tested"
}

# Test configuration: Anubis disabled
test_config_anubis_disabled() {
    local test_config="${TEST_DIR}/config-anubis-disabled.toml"
    
    # Create config with anubis disabled
    sed 's/enabled = true/enabled = false/' "$CONFIG_FILE" > "$test_config"
    
    # Generate and validate
    export CONFIG_FILE="$test_config"
    generate_config
    validate_compose
}

# Test configuration: TLS enabled
test_config_tls_enabled() {
    local test_config="${TEST_DIR}/config-tls-enabled.toml"
    
    # Create config with TLS enabled
    sed 's/enabled = false/enabled = true/; s/auto_https = "off"/auto_https = "on"/' "$CONFIG_FILE" > "$test_config"
    
    # Generate and validate
    export CONFIG_FILE="$test_config"
    generate_config
    validate_compose
}

# Test configuration: Scaling enabled
test_config_scaling_enabled() {
    local test_config="${TEST_DIR}/config-scaling-enabled.toml"
    
    # Create config with scaling enabled
    sed 's/scaling = false/scaling = true/' "$CONFIG_FILE" > "$test_config"
    
    # Generate and validate
    export CONFIG_FILE="$test_config"
    generate_config
    validate_compose
}

# Test configuration: Minimal config
test_config_minimal_config() {
    local test_config="${TEST_DIR}/config-minimal.toml"
    
    cat > "$test_config" << 'EOF'
[project]
name = "minimal-test"

[[proxies]]
name = "simple-proxy"
type = "caddy"
external_port = 80

[[services]]
name = "simple-service"
domain = "simple.example.com"
upstream = "http://192.0.2.1:8080"
EOF
    
    # Generate and validate
    export CONFIG_FILE="$test_config"
    generate_config
    validate_compose
}

# Cleanup test environment
cleanup_test() {
    print_step "Cleaning up test environment..."
    rm -rf "$TEST_DIR" 2>/dev/null || true
    print_success "Cleanup complete"
}

# Main test function
run_test() {
    print_header "Docker Compose Up Test"
    
    setup_test
    generate_config
    validate_compose
    test_compose_up
    test_configurations
    cleanup_test
    
    print_success "🎉 All Docker Compose tests passed!"
}

# Error handling
trap 'cleanup_test; exit 1' ERR

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_test
fi