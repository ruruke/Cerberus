#!/bin/bash

# Simple Anubis botPolicy Generator
# Generates botPolicy.json for Anubis DDoS protection

set -euo pipefail

# Source required libraries
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
source "${SCRIPT_DIR}/lib/core/utils.sh"
source "${SCRIPT_DIR}/lib/core/config-simple.sh"

# =============================================================================
# CONSTANTS
# =============================================================================

readonly ANUBIS_DIR="${BUILT_DIR}/anubis"
readonly BOT_POLICY_FILE="${ANUBIS_DIR}/botPolicy.json"

# =============================================================================
# MAIN GENERATION FUNCTION
# =============================================================================

# Generate complete Anubis botPolicy.json
generate_anubis_policy() {
    require_config_loaded
    
    if [[ "$(config_get_bool "anubis.enabled")" != "true" ]]; then
        log_warn "Anubis is not enabled in configuration"
        return 0
    fi
    
    log_info "Generating Anubis botPolicy.json..."
    
    # Create anubis directory
    safe_mkdir "$ANUBIS_DIR"
    
    # Generate botPolicy.json
    cat > "$BOT_POLICY_FILE" << 'EOF'
{
  "ALLOW": [
    {"path": "/favicon.ico"},
    {"path": "/robots.txt"},
    {"path": "/sitemap.xml"},
    {"path": "/apple-touch-icon*.png"},
    {"path": "/manifest.json"},
    {"path": "/.well-known/*"},
    {"path": "/health"},
    {"path": "/ping"},
    {"path": "/status"},
    {"path": "/api/meta"},
    {"path": "/api/stats"},
    {"path": "/api/ping"},
    {"path": "/api/v1/instance"},
    {"path": "/nodeinfo/*"},
    {"path": "/inbox"},
    {"path": "/outbox"},
    {"path": "/users/*/inbox"},
    {"path": "/users/*/outbox"},
    {"path": "/emoji/*"},
    {"path": "/proxy/*"},
    {"path": "/files/*"},
    {"user-agent": "*Googlebot*"},
    {"user-agent": "*bingbot*"},
    {"user-agent": "*Slurp*"},
    {"user-agent": "*DuckDuckBot*"},
    {"user-agent": "*facebookexternalhit*"},
    {"user-agent": "*Twitterbot*"},
    {"user-agent": "*LinkedInBot*"},
    {"user-agent": "*WhatsApp*"},
    {"user-agent": "*Applebot*"},
    {"user-agent": "*YandexBot*"}
  ],
  "CHALLENGE": [
    {"user-agent": "Mozilla*"},
    {"user-agent": "*Chrome*"},
    {"user-agent": "*Firefox*"},
    {"user-agent": "*Safari*"},
    {"user-agent": "*Edge*"},
    {"user-agent": "*Opera*"}
  ]
}
EOF
    
    log_info "Anubis botPolicy.json generated: $BOT_POLICY_FILE"
    return 0
}

# Generate predefined templates
generate_anubis_template() {
    local template_type="${1:-basic}"
    
    log_info "Generating Anubis template: $template_type"
    
    safe_mkdir "$ANUBIS_DIR"
    
    case "$template_type" in
        basic)
            cat > "${ANUBIS_DIR}/botPolicy-basic.json" << 'EOF'
{
  "ALLOW": [
    {"path": "/favicon.ico"},
    {"path": "/robots.txt"},
    {"path": "/.well-known/*"},
    {"path": "/health"},
    {"user-agent": "*Googlebot*"},
    {"user-agent": "*bingbot*"},
    {"user-agent": "*Twitterbot*"}
  ],
  "CHALLENGE": [
    {"user-agent": "Mozilla*"},
    {"user-agent": "*Chrome*"},
    {"user-agent": "*Firefox*"}
  ]
}
EOF
            ;;
        strict)
            cat > "${ANUBIS_DIR}/botPolicy-strict.json" << 'EOF'
{
  "ALLOW": [
    {"path": "/robots.txt"},
    {"path": "/.well-known/*"},
    {"user-agent": "*Googlebot*"},
    {"user-agent": "*bingbot*"}
  ],
  "CHALLENGE": [
    {"user-agent": "*"}
  ]
}
EOF
            ;;
        *)
            log_error "Unknown template type: $template_type"
            return 1
            ;;
    esac
}

# Validate generated botPolicy.json
validate_anubis_policy() {
    local policy_file="${1:-$BOT_POLICY_FILE}"
    
    if [[ ! -f "$policy_file" ]]; then
        log_error "botPolicy.json not found: $policy_file"
        return 1
    fi
    
    log_info "Validating botPolicy.json..."
    
    # Check JSON syntax
    if command -v jq >/dev/null 2>&1; then
        if ! jq . "$policy_file" >/dev/null 2>&1; then
            log_error "Invalid JSON syntax in $policy_file"
            return 1
        fi
        log_info "JSON syntax validation passed"
        
        # Check required sections
        if ! jq -e '.ALLOW' "$policy_file" >/dev/null 2>&1; then
            log_error "Missing ALLOW section in $policy_file"
            return 1
        fi
        
        if ! jq -e '.CHALLENGE' "$policy_file" >/dev/null 2>&1; then
            log_error "Missing CHALLENGE section in $policy_file"
            return 1
        fi
        
        log_info "Structure validation passed"
    else
        log_warn "jq not available, skipping JSON validation"
        
        # Basic syntax check
        if ! grep -q '"ALLOW"' "$policy_file"; then
            log_error "Missing ALLOW section in $policy_file"
            return 1
        fi
        
        if ! grep -q '"CHALLENGE"' "$policy_file"; then
            log_error "Missing CHALLENGE section in $policy_file"
            return 1
        fi
    fi
    
    log_info "botPolicy.json validation completed successfully"
    return 0
}

# Initialize generator
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    log_debug "Simple Anubis generator loaded"
fi