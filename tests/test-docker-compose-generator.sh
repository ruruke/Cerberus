#!/bin/bash

# Test script for Docker Compose Generator
# Usage: ./tests/test-docker-compose-generator.sh

set -euo pipefail

# Setup test environment
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
TEST_DIR="${SCRIPT_DIR}/tests"
FIXTURES_DIR="${TEST_DIR}/fixtures"
TEMP_DIR="${TEST_DIR}/tmp"

# Source libraries
source "${SCRIPT_DIR}/lib/core/utils.sh"
source "${SCRIPT_DIR}/lib/core/config.sh"
source "${SCRIPT_DIR}/lib/generators/docker-compose.sh"

# Test configuration
TEST_CONFIG="${TEMP_DIR}/test-config.toml"
TEST_OUTPUT="${TEMP_DIR}/docker-compose.yaml"

# =============================================================================
# TEST UTILITIES
# =============================================================================

# Test framework variables
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Initialize test environment
setup_test_env() {
    echo "Setting up test environment..."
    safe_mkdir "$TEMP_DIR"
    safe_mkdir "$FIXTURES_DIR"
    
    # Create test configuration
    create_test_config
}

# Cleanup test environment
cleanup_test_env() {
    echo "Cleaning up test environment..."
    safe_remove "$TEMP_DIR"
}

# Create minimal test configuration
create_test_config() {
    cat > "$TEST_CONFIG" << 'EOF'
[project]
name = "test-cerberus"
version = "1.0.0"
scaling = true

[[proxies]]
name = "proxy"
type = "nginx"
external_port = 8080
internal_port = 80
instances = 1
upstream = "http://anubis:8080"

[[proxies]]
name = "proxy-2"
type = "nginx"
external_port = 80
internal_port = 80
instances = 1
upstream = "http://100.103.133.21:3000"

[anubis]
enabled = true
bind = ":8080"
difficulty = 5
target = "http://proxy-2:80"
metrics_bind = ":9090"

[[services]]
name = "misskey"
domain = "mi.example.com"
upstream = "http://100.103.133.21:3000"
websocket = true
max_body_size = "100m"

[[services]]
name = "media-proxy"
domain = "media.example.com"
upstream = "http://100.97.11.65:12766"
websocket = false
max_body_size = "1m"

[scaling]
enabled = true
check_interval = "30s"

[scaling.metrics]
cpu_threshold = 80
memory_threshold = 85
connections_threshold = 1000
EOF
}

# Test assertion functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"
    
    ((TESTS_RUN++))
    
    if [[ "$expected" == "$actual" ]]; then
        echo "✓ PASS: $message"
        ((TESTS_PASSED++))
    else
        echo "✗ FAIL: $message"
        echo "  Expected: $expected"
        echo "  Actual: $actual"
        ((TESTS_FAILED++))
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist: $file}"
    
    ((TESTS_RUN++))
    
    if [[ -f "$file" ]]; then
        echo "✓ PASS: $message"
        ((TESTS_PASSED++))
    else
        echo "✗ FAIL: $message"
        echo "  File not found: $file"
        ((TESTS_FAILED++))
    fi
}

assert_file_contains() {
    local file="$1"
    local pattern="$2"
    local message="${3:-File should contain pattern: $pattern}"
    
    ((TESTS_RUN++))
    
    if [[ -f "$file" ]] && grep -q "$pattern" "$file"; then
        echo "✓ PASS: $message"
        ((TESTS_PASSED++))
    else
        echo "✗ FAIL: $message"
        echo "  Pattern '$pattern' not found in $file"
        ((TESTS_FAILED++))
    fi
}

assert_not_empty() {
    local value="$1"
    local message="${2:-Value should not be empty}"
    
    ((TESTS_RUN++))
    
    if [[ -n "$value" ]]; then
        echo "✓ PASS: $message"
        ((TESTS_PASSED++))
    else
        echo "✗ FAIL: $message"
        echo "  Value is empty"
        ((TESTS_FAILED++))
    fi
}

# =============================================================================
# UNIT TESTS
# =============================================================================

# Test config loading
test_config_loading() {
    echo
    echo "Testing configuration loading..."
    
    config_load "$TEST_CONFIG"
    
    # Test basic project config
    local project_name
    project_name=$(config_get_string "project.name")
    assert_equals "test-cerberus" "$project_name" "Project name should be loaded correctly"
    
    local scaling_enabled 
    scaling_enabled=$(config_get_bool "project.scaling")
    assert_equals "true" "$scaling_enabled" "Scaling should be enabled"
    
    # Test proxy configuration
    local proxy_count
    proxy_count=$(config_get_array_table_count "proxies")
    assert_equals "2" "$proxy_count" "Should have 2 proxy configurations"
    
    local proxy_name
    proxy_name=$(config_get_string "proxies.0.name")
    assert_equals "proxy" "$proxy_name" "First proxy name should be 'proxy'"
    
    # Test service configuration  
    local service_count
    service_count=$(config_get_array_table_count "services")
    assert_equals "2" "$service_count" "Should have 2 service configurations"
    
    local service_domain
    service_domain=$(config_get_string "services.0.domain")
    assert_equals "mi.example.com" "$service_domain" "First service domain should be correct"
}

# Test proxy image selection
test_proxy_image_selection() {
    echo
    echo "Testing proxy image selection..."
    
    local nginx_image caddy_image haproxy_image traefik_image
    nginx_image=$(get_proxy_image "nginx")
    caddy_image=$(get_proxy_image "caddy")
    haproxy_image=$(get_proxy_image "haproxy")
    traefik_image=$(get_proxy_image "traefik")
    
    assert_equals "nginx:stable-alpine" "$nginx_image" "Nginx image should be correct"
    assert_equals "caddy:alpine" "$caddy_image" "Caddy image should be correct"
    assert_equals "haproxy:alpine" "$haproxy_image" "HAProxy image should be correct"
    assert_equals "traefik:latest" "$traefik_image" "Traefik image should be correct"
}

# Test proxy config directory mapping
test_proxy_config_dir() {
    echo
    echo "Testing proxy config directory mapping..."
    
    local nginx_dir caddy_dir haproxy_dir traefik_dir
    nginx_dir=$(get_proxy_config_dir "nginx")
    caddy_dir=$(get_proxy_config_dir "caddy")
    haproxy_dir=$(get_proxy_config_dir "haproxy")
    traefik_dir=$(get_proxy_config_dir "traefik")
    
    assert_equals "nginx" "$nginx_dir" "Nginx config dir should be 'nginx'"
    assert_equals "caddy" "$caddy_dir" "Caddy config dir should be 'caddy'"
    assert_equals "haproxy" "$haproxy_dir" "HAProxy config dir should be 'haproxy'"
    assert_equals "traefik" "$traefik_dir" "Traefik config dir should be 'traefik'"
}

# Test service image selection
test_service_image_selection() {
    echo
    echo "Testing service image selection..."
    
    local misskey_image media_image summaly_image postgres_image redis_image
    misskey_image=$(get_service_image "misskey")
    media_image=$(get_service_image "media-proxy")
    summaly_image=$(get_service_image "summaly")
    postgres_image=$(get_service_image "postgres")
    redis_image=$(get_service_image "redis")
    
    assert_equals "misskey/misskey:latest" "$misskey_image" "Misskey image should be correct"
    assert_equals "ghcr.io/misskey-dev/media-proxy:latest" "$media_image" "Media proxy image should be correct"
    assert_equals "ghcr.io/misskey-dev/summaly:latest" "$summaly_image" "Summaly image should be correct"
    assert_equals "postgres:14-alpine" "$postgres_image" "Postgres image should be correct"
    assert_equals "redis:7-alpine" "$redis_image" "Redis image should be correct"
}

# Test compose header generation
test_compose_header_generation() {
    echo
    echo "Testing compose header generation..."
    
    config_load "$TEST_CONFIG"
    
    local header
    header=$(generate_compose_header)
    
    assert_not_empty "$header" "Header should not be empty"
    
    # Check if header contains expected elements
    if echo "$header" | grep -q "version: '3.8'"; then
        echo "✓ PASS: Header contains correct version"
        ((TESTS_PASSED++))
    else
        echo "✗ FAIL: Header missing version information"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
    
    if echo "$header" | grep -q "test-cerberus"; then
        echo "✓ PASS: Header contains project name"
        ((TESTS_PASSED++))
    else
        echo "✗ FAIL: Header missing project name"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test full docker-compose generation
test_docker_compose_generation() {
    echo
    echo "Testing full Docker Compose generation..."
    
    config_load "$TEST_CONFIG"
    
    # Generate docker-compose.yaml
    if generate_docker_compose "$TEST_OUTPUT"; then
        echo "✓ PASS: Docker Compose generation completed without errors"
        ((TESTS_PASSED++))
    else
        echo "✗ FAIL: Docker Compose generation failed"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
    
    # Check if output file exists
    assert_file_exists "$TEST_OUTPUT" "Generated docker-compose.yaml should exist"
    
    # Check key components in generated file
    assert_file_contains "$TEST_OUTPUT" "version: '3.8'" "Should contain version specification"
    assert_file_contains "$TEST_OUTPUT" "services:" "Should contain services section"
    assert_file_contains "$TEST_OUTPUT" "networks:" "Should contain networks section"
    assert_file_contains "$TEST_OUTPUT" "volumes:" "Should contain volumes section"
    
    # Check specific services
    assert_file_contains "$TEST_OUTPUT" "proxy:" "Should contain proxy service"
    assert_file_contains "$TEST_OUTPUT" "proxy-2:" "Should contain proxy-2 service"
    assert_file_contains "$TEST_OUTPUT" "anubis:" "Should contain anubis service"
    
    # Check network configuration
    assert_file_contains "$TEST_OUTPUT" "front-net:" "Should contain front-net network"
    assert_file_contains "$TEST_OUTPUT" "back-net:" "Should contain back-net network"
    
    # Check port mappings
    assert_file_contains "$TEST_OUTPUT" "8080:80" "Should contain correct port mapping for proxy"
    assert_file_contains "$TEST_OUTPUT" "8080:8080" "Should contain correct port mapping for anubis"
}

# Test error handling
test_error_handling() {
    echo
    echo "Testing error handling..."
    
    # Test with invalid configuration
    local invalid_config="${TEMP_DIR}/invalid-config.toml"
    cat > "$invalid_config" << 'EOF'
[project]
# Missing required name field

[[proxies]]
# Missing required name and type fields
external_port = 8080
EOF
    
    # This should fail validation
    if config_load "$invalid_config" 2>/dev/null; then
        # If it loads, validation should catch the errors
        if ! config_validate 2>/dev/null; then
            echo "✓ PASS: Invalid configuration correctly rejected"
            ((TESTS_PASSED++))
        else
            echo "✗ FAIL: Invalid configuration should have been rejected"
            ((TESTS_FAILED++))
        fi
    else
        echo "✓ PASS: Invalid configuration correctly rejected during loading"
        ((TESTS_PASSED++))
    fi
    ((TESTS_RUN++))
}

# Test validation function
test_validation() {
    echo
    echo "Testing docker-compose validation..."
    
    config_load "$TEST_CONFIG"
    generate_docker_compose "$TEST_OUTPUT"
    
    # Test validation function
    if validate_docker_compose "$TEST_OUTPUT"; then
        echo "✓ PASS: Docker Compose validation passed"
        ((TESTS_PASSED++))
    else
        echo "✗ FAIL: Docker Compose validation failed"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

# Test integration with CLI
test_cli_integration() {
    echo
    echo "Testing CLI integration..."
    
    # Copy test config to expected location
    cp "$TEST_CONFIG" "${SCRIPT_DIR}/config.toml"
    
    # Test generate command
    cd "$SCRIPT_DIR"
    if ./cerberus.sh generate --force 2>/dev/null; then
        echo "✓ PASS: CLI generate command succeeded"
        ((TESTS_PASSED++))
        
        # Check if built directory was created
        assert_file_exists "${SCRIPT_DIR}/built/docker-compose.yaml" "CLI should generate docker-compose.yaml in built/"
    else
        echo "✗ FAIL: CLI generate command failed"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
    
    # Cleanup
    rm -f "${SCRIPT_DIR}/config.toml"
    safe_remove "${SCRIPT_DIR}/built"
}

# =============================================================================
# MAIN TEST RUNNER
# =============================================================================

# Show test results
show_test_results() {
    echo
    echo "========================================"
    echo "Test Results"
    echo "========================================"
    echo "Tests run: $TESTS_RUN"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    echo
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "✓ All tests passed!"
        return 0
    else
        echo "✗ Some tests failed!"
        return 1
    fi
}

# Main test runner
main() {
    echo "Docker Compose Generator Test Suite"
    echo "==================================="
    
    setup_test_env
    
    # Run unit tests
    test_config_loading
    test_proxy_image_selection
    test_proxy_config_dir
    test_service_image_selection
    test_compose_header_generation
    test_docker_compose_generation
    test_error_handling
    test_validation
    
    # Run integration tests
    test_cli_integration
    
    cleanup_test_env
    show_test_results
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_utils
    main "$@"
fi