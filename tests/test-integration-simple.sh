#!/bin/bash

# Cerberus Simple Integration Test
# Quick validation of core functionality

set -euo pipefail

# Setup paths
SCRIPT_DIR="/mnt/e/codeing/shellscript/cerberus"
export SCRIPT_DIR
export BUILT_DIR="${SCRIPT_DIR}/tests/tmp/simple-test"

echo "========================================"
echo "🚀 Cerberus Simple Integration Test"
echo "========================================"

# Load libraries
source "${SCRIPT_DIR}/lib/core/utils.sh"
source "${SCRIPT_DIR}/lib/core/config-simple.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_result() {
    local test_name="$1"
    local result="$2"
    local message="${3:-}"
    
    ((TESTS_RUN++))
    
    if [[ "$result" == "pass" ]]; then
        echo "✅ PASS: $test_name"
        ((TESTS_PASSED++))
    else
        echo "❌ FAIL: $test_name"
        if [[ -n "$message" ]]; then
            echo "   Error: $message"
        fi
        ((TESTS_FAILED++))
    fi
}

# Clean test directory
rm -rf "$BUILT_DIR"
safe_mkdir "$BUILT_DIR"

# Create simple test configuration
cat > "${BUILT_DIR}/simple-config.toml" << 'EOF'
[project]
name = "simple-test"
version = "1.0.0"

[[proxies]]
name = "nginx-proxy"
type = "nginx"
external_port = 80
internal_port = 80
upstream = "http://misskey:3000"

[anubis]
enabled = true
bind = ":8080"
difficulty = 5
target = "http://nginx-proxy:80"

[[services]]
name = "misskey"
domain = "mi.test.local"
upstream = "http://127.0.0.1:3000"
websocket = true
EOF

echo "📝 Loading test configuration..."
config_load "${BUILT_DIR}/simple-config.toml"

echo
echo "🧪 Running Core Tests..."

# Test 1: Configuration Loading
echo "Testing configuration loading..."
if [[ -n "${CONFIG_FILE_PATH:-}" ]]; then
    test_result "Configuration Loading" "pass"
else
    test_result "Configuration Loading" "fail" "CONFIG_FILE_PATH not set"
fi

# Test 2: Docker Compose Generation
echo "Testing Docker Compose generation..."
source "${SCRIPT_DIR}/lib/generators/docker-compose.sh"
if generate_docker_compose "${BUILT_DIR}/docker-compose.yaml"; then
    if [[ -f "${BUILT_DIR}/docker-compose.yaml" ]]; then
        test_result "Docker Compose Generation" "pass"
    else
        test_result "Docker Compose Generation" "fail" "File not created"
    fi
else
    test_result "Docker Compose Generation" "fail" "Generation failed"
fi

# Test 3: Docker Compose Content
echo "Testing Docker Compose content..."
if [[ -f "${BUILT_DIR}/docker-compose.yaml" ]]; then
    content_checks=0
    total_checks=3
    
    if grep -q "version: '3.8'" "${BUILT_DIR}/docker-compose.yaml"; then ((content_checks++)); fi
    if grep -q "nginx-proxy:" "${BUILT_DIR}/docker-compose.yaml"; then ((content_checks++)); fi
    if grep -q "anubis:" "${BUILT_DIR}/docker-compose.yaml"; then ((content_checks++)); fi
    
    if [[ $content_checks -eq $total_checks ]]; then
        test_result "Docker Compose Content" "pass"
    else
        test_result "Docker Compose Content" "fail" "$content_checks/$total_checks checks passed"
    fi
else
    test_result "Docker Compose Content" "fail" "File not found"
fi

# Test 4: Anubis Policy Generation
echo "Testing Anubis policy generation..."
source "${SCRIPT_DIR}/lib/generators/anubis-simple.sh"
if generate_anubis_policy; then
    if [[ -f "${BUILT_DIR}/anubis/botPolicy.json" ]]; then
        test_result "Anubis Policy Generation" "pass"
    else
        test_result "Anubis Policy Generation" "fail" "botPolicy.json not created"
    fi
else
    test_result "Anubis Policy Generation" "fail" "Generation failed"
fi

# Test 5: Library Loading
echo "Testing library loading..."
libraries_loaded=0
total_libraries=4

if declare -f log_info >/dev/null 2>&1; then ((libraries_loaded++)); fi
if declare -f config_get_string >/dev/null 2>&1; then ((libraries_loaded++)); fi
if declare -f generate_docker_compose >/dev/null 2>&1; then ((libraries_loaded++)); fi
if declare -f generate_anubis_policy >/dev/null 2>&1; then ((libraries_loaded++)); fi

if [[ $libraries_loaded -eq $total_libraries ]]; then
    test_result "Library Loading" "pass"
else
    test_result "Library Loading" "fail" "$libraries_loaded/$total_libraries libraries loaded"
fi

# Test 6: CLI Existence
echo "Testing CLI existence..."
if [[ -f "${SCRIPT_DIR}/cerberus.sh" ]]; then
    if grep -q "cmd_generate" "${SCRIPT_DIR}/cerberus.sh"; then
        test_result "CLI Existence" "pass"
    else
        test_result "CLI Existence" "fail" "Generate command not found"
    fi
else
    test_result "CLI Existence" "fail" "cerberus.sh not found"
fi

echo
echo "========================================"
echo "📊 Simple Integration Test Results"
echo "========================================"
echo "Tests Run:    $TESTS_RUN"
echo "Tests Passed: $TESTS_PASSED"
echo "Tests Failed: $TESTS_FAILED"
echo

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "🎉 ALL TESTS PASSED! Basic Cerberus functionality works!"
    echo
    echo "📁 Generated Files:"
    echo "   Docker Compose: ${BUILT_DIR}/docker-compose.yaml"
    echo "   Anubis Policy: ${BUILT_DIR}/anubis/botPolicy.json"
    exit 0
else
    echo "❌ $TESTS_FAILED test(s) failed. Please review the errors above."
    exit 1
fi