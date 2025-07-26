#!/bin/bash

# Test script for Anubis botPolicy Generator

set -euo pipefail

# Setup paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SCRIPT_DIR
export BUILT_DIR="${SCRIPT_DIR}/tests/tmp"

echo "Testing Anubis botPolicy Generator..."
echo "===================================="

# Load libraries
source "${SCRIPT_DIR}/lib/core/utils.sh"
source "${SCRIPT_DIR}/lib/core/config-simple.sh"
if [[ -f "${SCRIPT_DIR}/lib/generators/anubis-simple.sh" ]]; then
    source "${SCRIPT_DIR}/lib/generators/anubis-simple.sh"
else
    echo "⚠ WARNING: Anubis generator not available, creating stub functions"
    generate_anubis_config() { echo "Anubis config generation stubbed"; }
fi

# Test configuration
cat > "${SCRIPT_DIR}/tests/tmp/anubis-test.toml" << 'EOF'
[project]
name = "anubis-test"

[anubis]
enabled = true
bind = ":8080"
difficulty = 5
target = "http://proxy-2:80"
metrics_bind = ":9090"

# Allow paths
[anubis.allow_paths]
health = "/health"
api = "/api/*"
well_known = "/.well-known/*"
favicon = "/favicon.ico"
robots = "/robots.txt"

# User agents for challenge
[anubis.challenge_agents]
mozilla = "Mozilla*"
chrome = "*Chrome*"
safari = "*Safari*"

# Bot whitelist
[anubis.bot_whitelist]
googlebot = "*Googlebot*"
bingbot = "*bingbot*"
twitterbot = "*Twitterbot*"

[[services]]
name = "misskey"
domain = "mi.example.com"
upstream = "http://100.103.133.21:3000"

[[services]]
name = "media-proxy"
domain = "media.example.com"
upstream = "http://100.97.11.65:12766"
EOF

echo "1. Loading configuration..."
config_load "${SCRIPT_DIR}/tests/tmp/anubis-test.toml"

echo "2. Checking configuration access..."
anubis_enabled=$(config_get_bool "anubis.enabled")
echo "Anubis enabled: $anubis_enabled"

difficulty=$(config_get_int "anubis.difficulty")
echo "Difficulty: $difficulty"

# Test individual path access
health_path=$(config_get_string "anubis.allow_paths.health" "")
echo "Health path: $health_path"

echo "3. Testing library loading..."
if source "${SCRIPT_DIR}/lib/generators/anubis-simple.sh"; then
    echo "✓ Anubis generator loaded successfully"
else
    echo "✗ Failed to load Anubis generator"
    exit 1
fi

echo "4. Re-loading configuration after library loading..."
config_load "${SCRIPT_DIR}/tests/tmp/anubis-test.toml"

echo "5. Generating botPolicy.json..."
rm -rf "${BUILT_DIR}/anubis"
if generate_anubis_policy; then
    echo "✓ botPolicy.json generated successfully"
else
    echo "✗ botPolicy.json generation failed"
    exit 1
fi

echo "6. Checking generated files..."
if [[ -f "${BUILT_DIR}/anubis/botPolicy.json" ]]; then
    echo "✓ botPolicy.json created"
    
    # Check JSON validity
    if command -v jq >/dev/null 2>&1; then
        if jq . "${BUILT_DIR}/anubis/botPolicy.json" >/dev/null 2>&1; then
            echo "✓ botPolicy.json is valid JSON"
        else
            echo "✗ botPolicy.json is invalid JSON"
        fi
    else
        echo "! jq not available, skipping JSON validation"
    fi
    
    # Check content
    if grep -q "ALLOW" "${BUILT_DIR}/anubis/botPolicy.json"; then
        echo "✓ botPolicy.json contains ALLOW rules"
    fi
    
    if grep -q "CHALLENGE" "${BUILT_DIR}/anubis/botPolicy.json"; then
        echo "✓ botPolicy.json contains CHALLENGE rules"
    fi
    
    echo "--- Sample content (first 20 lines) ---"
    head -20 "${BUILT_DIR}/anubis/botPolicy.json"
else
    echo "✗ botPolicy.json not created"
    exit 1
fi

echo "7. Testing validation..."
if validate_anubis_policy; then
    echo "✓ botPolicy validation passed"
else
    echo "✗ botPolicy validation failed"
fi

echo "8. Testing template generation..."
if generate_anubis_template "basic"; then
    echo "✓ Basic template generated"
fi

if generate_anubis_template "strict"; then
    echo "✓ Strict template generated"
fi

echo
echo "All Anubis tests completed!"