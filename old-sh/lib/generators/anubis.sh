#!/bin/bash

# Anubis botPolicy Generator
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
    {
        echo "{"
        echo "  \"ALLOW\": ["
        generate_allow_rules
        echo "  ],"
        echo "  \"CHALLENGE\": ["
        generate_challenge_rules
        echo "  ]"
        echo "}"
    } > "$BOT_POLICY_FILE"
    
    log_info "Anubis botPolicy.json generated: $BOT_POLICY_FILE"
    return 0
}

# =============================================================================
# ALLOW RULES GENERATION
# =============================================================================

# Generate ALLOW rules for paths and bots that should bypass protection
generate_allow_rules() {
    local comma_needed=""
    
    # Static assets that should always be allowed
    comma_needed=$(generate_static_allow_rules "$comma_needed")
    
    # Custom allow paths from configuration
    comma_needed=$(generate_custom_allow_paths "$comma_needed")
    
    # Service-specific allow paths
    comma_needed=$(generate_service_allow_paths "$comma_needed")
    
    # Bot whitelist
    comma_needed=$(generate_bot_whitelist "$comma_needed")
    
    echo
}

# Generate static allow rules
generate_static_allow_rules() {
    local first_var="$1"
    
    local static_paths=(
        "/favicon.ico"
        "/robots.txt" 
        "/sitemap.xml"
        "/apple-touch-icon*.png"
        "/manifest.json"
        "/.well-known/*"
        "/health"
        "/ping"
        "/status"
    )
    
    for path in "${static_paths[@]}"; do
        if [[ "$first_ref" == "false" ]]; then
            echo ","
        fi
        first_ref=false
        echo -n "    {\"path\": \"$path\"}"
    done
}

# Generate custom allow paths from configuration
generate_custom_allow_paths() {
    local -n first_ref=$1
    
    # Check for custom allow paths in config
    local config_keys
    config_keys=$(config_list_keys | grep "^anubis\.allow_paths\." || true)
    
    for key in $config_keys; do
        local path
        path=$(config_get_string "$key")
        if [[ -n "$path" ]]; then
            if [[ "$first_ref" == "false" ]]; then
                echo ","
            fi
            first_ref=false
            echo -n "    {\"path\": \"$path\"}"
        fi
    done
}

# Generate service-specific allow paths
generate_service_allow_paths() {
    local -n first_ref=$1
    
    local service_count
    service_count=$(config_get_array_table_count "services")
    
    for ((j=0; j<service_count; j++)); do
        local service_name service_domain
        service_name=$(config_get_string "services.${j}.name")
        service_domain=$(config_get_string "services.${j}.domain")
        
        if [[ -z "$service_name" || -z "$service_domain" ]]; then
            continue
        fi
        
        # Service-specific paths based on service type
        case "$service_name" in
            misskey)
                generate_misskey_allow_paths first_ref "$service_domain"
                ;;
            media-proxy)
                generate_media_proxy_allow_paths first_ref "$service_domain"
                ;;
            *)
                # Generic service paths
                generate_generic_service_allow_paths first_ref "$service_domain"
                ;;
        esac
    done
}

# Generate Misskey-specific allow paths
generate_misskey_allow_paths() {
    local -n first_ref=$1
    local domain="$2"
    
    local misskey_paths=(
        "/api/*"
        "/inbox"
        "/outbox"
        "/users/*/inbox"
        "/users/*/outbox"
        "/nodeinfo/2.0"
        "/nodeinfo/2.1"
        "/.well-known/nodeinfo"
        "/.well-known/host-meta"
        "/.well-known/webfinger"
        "/emoji/*"
        "/proxy/*"
        "/files/*"
    )
    
    for path in "${misskey_paths[@]}"; do
        if [[ "$first_ref" == "false" ]]; then
            echo ","
        fi
        first_ref=false
        echo -n "    {\"path\": \"$path\", \"host\": \"$domain\"}"
    done
}

# Generate media proxy allow paths
generate_media_proxy_allow_paths() {
    local -n first_ref=$1
    local domain="$2"
    
    local media_paths=(
        "/proxy/*"
        "/image/*"
        "/video/*"
        "/audio/*"
        "/thumbnail/*"
    )
    
    for path in "${media_paths[@]}"; do
        if [[ "$first_ref" == "false" ]]; then
            echo ","
        fi
        first_ref=false
        echo -n "    {\"path\": \"$path\", \"host\": \"$domain\"}"
    done
}

# Generate generic service allow paths
generate_generic_service_allow_paths() {
    local -n first_ref=$1
    local domain="$2"
    
    local generic_paths=(
        "/api/*"
        "/health"
        "/metrics"
    )
    
    for path in "${generic_paths[@]}"; do
        if [[ "$first_ref" == "false" ]]; then
            echo ","
        fi
        first_ref=false
        echo -n "    {\"path\": \"$path\", \"host\": \"$domain\"}"
    done
}

# Generate bot whitelist
generate_bot_whitelist() {
    local -n first_ref=$1
    
    # Standard search engine bots
    local bot_agents=(
        "*Googlebot*"
        "*bingbot*"
        "*Slurp*"  # Yahoo
        "*DuckDuckBot*"
        "*facebookexternalhit*"
        "*Twitterbot*"
        "*LinkedInBot*"
        "*WhatsApp*"
        "*Applebot*"
        "*YandexBot*"
    )
    
    # Custom bot whitelist from configuration
    local config_keys
    config_keys=$(config_list_keys | grep "^anubis\.bot_whitelist\." || true)
    
    for key in $config_keys; do
        local agent
        agent=$(config_get_string "$key")
        if [[ -n "$agent" ]]; then
            bot_agents+=("$agent")
        fi
    done
    
    for agent in "${bot_agents[@]}"; do
        if [[ "$first_ref" == "false" ]]; then
            echo ","
        fi
        first_ref=false
        echo -n "    {\"user-agent\": \"$agent\"}"
    done
}

# =============================================================================
# CHALLENGE RULES GENERATION
# =============================================================================

# Generate CHALLENGE rules for user agents that should solve challenges
generate_challenge_rules() {
    local first_rule=true
    
    # Browser user agents that should be challenged
    generate_browser_challenge_rules first_rule
    
    # Custom challenge agents from configuration
    generate_custom_challenge_agents first_rule
    
    echo
}

# Generate browser challenge rules
generate_browser_challenge_rules() {
    local -n first_ref=$1
    
    local browser_agents=(
        "Mozilla*"
        "*Chrome*"
        "*Firefox*"
        "*Safari*"
        "*Edge*"
        "*Opera*"
    )
    
    for agent in "${browser_agents[@]}"; do
        if [[ "$first_ref" == "false" ]]; then
            echo ","
        fi
        first_ref=false
        echo -n "    {\"user-agent\": \"$agent\"}"
    done
}

# Generate custom challenge agents from configuration
generate_custom_challenge_agents() {
    local -n first_ref=$1
    
    local config_keys
    config_keys=$(config_list_keys | grep "^anubis\.challenge_agents\." || true)
    
    for key in $config_keys; do
        local agent
        agent=$(config_get_string "$key")
        if [[ -n "$agent" ]]; then
            if [[ "$first_ref" == "false" ]]; then
                echo ","
            fi
            first_ref=false
            echo -n "    {\"user-agent\": \"$agent\"}"
        fi
    done
}

# =============================================================================
# TEMPLATE GENERATION
# =============================================================================

# Generate predefined templates
generate_anubis_template() {
    local template_type="${1:-basic}"
    
    log_info "Generating Anubis template: $template_type"
    
    safe_mkdir "$ANUBIS_DIR"
    
    case "$template_type" in
        basic)
            generate_basic_template
            ;;
        strict)
            generate_strict_template
            ;;
        permissive)
            generate_permissive_template
            ;;
        misskey)
            generate_misskey_template
            ;;
        *)
            log_error "Unknown template type: $template_type"
            return 1
            ;;
    esac
}

# Generate basic template
generate_basic_template() {
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
}

# Generate strict template
generate_strict_template() {
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
}

# Generate permissive template
generate_permissive_template() {
    cat > "${ANUBIS_DIR}/botPolicy-permissive.json" << 'EOF'
{
  "ALLOW": [
    {"path": "/favicon.ico"},
    {"path": "/robots.txt"},
    {"path": "/sitemap.xml"},
    {"path": "/.well-known/*"},
    {"path": "/health"},
    {"path": "/api/v1/instance"},
    {"path": "/api/meta"},
    {"user-agent": "*Googlebot*"},
    {"user-agent": "*bingbot*"},
    {"user-agent": "*Slurp*"},
    {"user-agent": "*DuckDuckBot*"},
    {"user-agent": "*facebookexternalhit*"},
    {"user-agent": "*Twitterbot*"},
    {"user-agent": "*LinkedInBot*"}
  ],
  "CHALLENGE": [
    {"user-agent": "Mozilla*"}
  ]
}
EOF
}

# Generate Misskey-specific template
generate_misskey_template() {
    cat > "${ANUBIS_DIR}/botPolicy-misskey.json" << 'EOF'
{
  "ALLOW": [
    {"path": "/favicon.ico"},
    {"path": "/robots.txt"},
    {"path": "/manifest.json"},
    {"path": "/.well-known/*"},
    {"path": "/nodeinfo/*"},
    {"path": "/api/meta"},
    {"path": "/api/stats"},
    {"path": "/api/ping"},
    {"path": "/api/v1/instance"},
    {"path": "/inbox"},
    {"path": "/outbox"},
    {"path": "/users/*/inbox"},
    {"path": "/users/*/outbox"},
    {"path": "/emoji/*"},
    {"path": "/proxy/*"},
    {"path": "/files/*"},
    {"user-agent": "*Googlebot*"},
    {"user-agent": "*bingbot*"},
    {"user-agent": "*facebookexternalhit*"},
    {"user-agent": "*Twitterbot*"},
    {"user-agent": "*LinkedInBot*"},
    {"user-agent": "*WhatsApp*"}
  ],
  "CHALLENGE": [
    {"user-agent": "Mozilla*"},
    {"user-agent": "*Chrome*"},
    {"user-agent": "*Firefox*"},
    {"user-agent": "*Safari*"}
  ]
}
EOF
}

# =============================================================================
# VALIDATION
# =============================================================================

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

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Get Anubis configuration summary
get_anubis_summary() {
    require_config_loaded
    
    if [[ "$(config_get_bool "anubis.enabled")" != "true" ]]; then
        echo "Anubis: Disabled"
        return 0
    fi
    
    echo "Anubis Configuration:"
    echo "  Enabled: $(config_get_bool "anubis.enabled")"
    echo "  Bind: $(config_get_string "anubis.bind" ":8080")"
    echo "  Difficulty: $(config_get_int "anubis.difficulty" 5)"
    echo "  Target: $(config_get_string "anubis.target" "http://proxy-2:80")"
    echo "  Metrics: $(config_get_string "anubis.metrics_bind" ":9090")"
    
    if [[ -f "$BOT_POLICY_FILE" ]]; then
        echo "  Policy file: Generated ($(wc -l < "$BOT_POLICY_FILE") lines)"
    else
        echo "  Policy file: Not generated"
    fi
}

# List available templates
list_anubis_templates() {
    echo "Available Anubis templates:"
    echo "  basic      - Basic protection with common allow rules"
    echo "  strict     - Strict protection, challenges most traffic"
    echo "  permissive - Permissive protection, allows more bots"
    echo "  misskey    - Optimized for Misskey instances"
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize generator
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    log_debug "Anubis generator loaded"
fi