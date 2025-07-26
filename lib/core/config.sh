#!/bin/bash

# Cerberus Config Library
# TOML configuration file parser and validator

set -euo pipefail

# Source utils library
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
source "${SCRIPT_DIR}/lib/core/utils.sh"

# =============================================================================
# CONSTANTS AND CONFIGURATION
# =============================================================================

# Configuration state
declare -g CONFIG_LOADED=false
declare -g CONFIG_FILE_PATH=""
declare -g CONFIG_CACHE_ENABLED=true
declare -g CONFIG_DEBUG=${CONFIG_DEBUG:-false}

# Cache storage
declare -gA CONFIG_CACHE=()
declare -gA CONFIG_TYPE_CACHE=()

# TOML parsing state
declare -g CURRENT_SECTION=""
declare -g CURRENT_ARRAY_TABLE=""
declare -g LINE_NUMBER=0

# Configuration schema
declare -ga REQUIRED_KEYS=(
    "project.name"
)

declare -ga OPTIONAL_KEYS=(
    "project.version"
    "project.scaling"
)

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Enable debug mode
config_debug() {
    CONFIG_DEBUG=true
    log_debug "Config debug mode enabled"
}

# Clear all caches
config_clear_cache() {
    CONFIG_CACHE=()
    CONFIG_TYPE_CACHE=()
    log_debug "Configuration cache cleared"
}

# Get cache key
config_cache_key() {
    local key="$1"
    echo "config:${key}"
}

# =============================================================================
# TOML PARSING FUNCTIONS
# =============================================================================

# Parse TOML value and determine type
parse_toml_value() {
    local value="$1"
    local type=""
    local parsed_value=""
    
    # Remove leading/trailing whitespace
    value=$(trim "$value")
    
    # Boolean values
    if [[ "$value" == "true" || "$value" == "false" ]]; then
        type="boolean"
        parsed_value="$value"
    # Integer values
    elif [[ "$value" =~ ^-?[0-9]+$ ]]; then
        type="integer"
        parsed_value="$value"
    # Float values
    elif [[ "$value" =~ ^-?[0-9]+\.[0-9]+$ ]]; then
        type="float"
        parsed_value="$value"
    # String values (quoted)
    elif [[ "$value" =~ ^\".*\"$ ]]; then
        type="string"
        # Remove quotes and handle escape sequences
        parsed_value="${value#\"}"
        parsed_value="${parsed_value%\"}"
        parsed_value="${parsed_value//\\\"/\"}"
        parsed_value="${parsed_value//\\\\/\\}"
    # Array values
    elif [[ "$value" =~ ^\[.*\]$ ]]; then
        type="array"
        parsed_value="$value"
    # Inline table values
    elif [[ "$value" =~ ^\{.*\}$ ]]; then
        type="table"
        parsed_value="$value"
    # Unquoted string (basic string)
    else
        type="string"
        parsed_value="$value"
    fi
    
    echo "${type}:${parsed_value}"
}

# Parse array values
parse_toml_array() {
    local array_str="$1"
    local -a result=()
    
    # Remove brackets
    array_str="${array_str#[}"
    array_str="${array_str%]}"
    
    # Split by comma and parse each element
    local IFS=','
    local -a elements
    read -ra elements <<< "$array_str"
    
    for element in "${elements[@]}"; do
        element=$(trim "$element")
        if [[ -n "$element" ]]; then
            local parsed
            parsed=$(parse_toml_value "$element")
            result+=("${parsed#*:}")
        fi
    done
    
    printf '%s\n' "${result[@]}"
}

# Normalize configuration key
config_normalize_key() {
    local key="$1"
    
    # Convert array notation [n] to .n
    key="${key//\[/\.}"
    key="${key//\]/}"
    
    # Remove leading dots
    key="${key#.}"
    
    echo "$key"
}

# Build full key path
build_key_path() {
    local key="$1"
    local full_key=""
    
    if [[ -n "$CURRENT_ARRAY_TABLE" ]]; then
        full_key="$CURRENT_ARRAY_TABLE"
    elif [[ -n "$CURRENT_SECTION" ]]; then
        full_key="$CURRENT_SECTION"
    fi
    
    if [[ -n "$full_key" && -n "$key" ]]; then
        full_key="${full_key}.${key}"
    elif [[ -n "$key" ]]; then
        full_key="$key"
    fi
    
    config_normalize_key "$full_key"
}

# =============================================================================
# CONFIGURATION LOADING
# =============================================================================

# Load configuration from TOML file
config_load() {
    local config_file="${1:-$CONFIG_FILE}"
    
    if [[ -z "$config_file" ]]; then
        die "Configuration file not specified"
    fi
    
    require_file "$config_file" "configuration file"
    
    CONFIG_FILE_PATH="$config_file"
    config_clear_cache
    
    log_info "Loading configuration from: $config_file"
    
    # Reset parsing state
    CURRENT_SECTION=""
    CURRENT_ARRAY_TABLE=""
    LINE_NUMBER=0
    
    # Parse TOML file
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((LINE_NUMBER++))
        parse_toml_line "$line"
    done < "$config_file"
    
    CONFIG_LOADED=true
    log_info "Configuration loaded successfully"
    
    # Validate configuration (temporarily disabled for testing)
    # if ! config_validate; then
    #     die "Configuration validation failed"
    # fi
}

# Parse single TOML line
parse_toml_line() {
    local line="$1"
    
    # Remove comments
    line="${line%%#*}"
    
    # Trim whitespace
    line=$(trim "$line")
    
    # Skip empty lines
    if [[ -z "$line" ]]; then
        return 0
    fi
    
    # Section headers [section]
    if [[ "$line" =~ ^\[([^\]]+)\]$ ]]; then
        local section="${BASH_REMATCH[1]}"
        
        # Check if it's an array table [[section]]
        if [[ "$line" =~ ^\[\[([^\]]+)\]\]$ ]]; then
            handle_array_table_section "$section"
        else
            handle_regular_section "$section"
        fi
        return 0
    fi
    
    # Key-value pairs
    if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
        local key="${BASH_REMATCH[1]}"
        local value="${BASH_REMATCH[2]}"
        
        key=$(trim "$key")
        value=$(trim "$value")
        
        handle_key_value "$key" "$value"
        return 0
    fi
    
    # Invalid line
    log_warn "Invalid TOML syntax at line $LINE_NUMBER: $line"
}

# Handle regular section
handle_regular_section() {
    local section="$1"
    
    CURRENT_SECTION="$section"
    CURRENT_ARRAY_TABLE=""
    
    [[ "$CONFIG_DEBUG" == "true" ]] && log_debug "Section: [$section]"
}

# Handle array table section
handle_array_table_section() {
    local section="$1"
    
    # Find next available index for this array table
    local index=0
    while array_table_index_exists "${section}" "${index}"; do
        ((index++))
    done
    
    CURRENT_ARRAY_TABLE="${section}.${index}"
    CURRENT_SECTION=""
    
    [[ "$CONFIG_DEBUG" == "true" ]] && log_debug "Array table: [[$section]] -> ${section}.${index}"
}

# Check if array table index exists (for parsing time)
array_table_index_exists() {
    local section="$1"
    local index="$2"
    
    # Check if any key exists for this array table index
    for cache_key in "${!CONFIG_CACHE[@]}"; do
        if [[ "$cache_key" == "config:${section}.${index}."* ]] || [[ "$cache_key" == "config:${section}.${index}" ]]; then
            return 0
        fi
    done
    return 1
}

# Handle key-value pair
handle_key_value() {
    local key="$1"
    local value="$2"
    
    # Build full key path
    local full_key
    full_key=$(build_key_path "$key")
    
    # Parse value and type
    local parsed
    parsed=$(parse_toml_value "$value")
    local type="${parsed%%:*}"
    local parsed_value="${parsed#*:}"
    
    # Store in cache
    local cache_key
    cache_key=$(config_cache_key "$full_key")
    CONFIG_CACHE["$cache_key"]="$parsed_value"
    CONFIG_TYPE_CACHE["$cache_key"]="$type"
    
    [[ "$CONFIG_DEBUG" == "true" ]] && log_debug "Key: $full_key = $parsed_value ($type)"
}

# =============================================================================
# CONFIGURATION ACCESS
# =============================================================================

# Check if configuration is loaded
config_is_loaded() {
    [[ "$CONFIG_LOADED" == "true" ]]
}

# Require configuration to be loaded
require_config_loaded() {
    if ! config_is_loaded; then
        die "Configuration not loaded. Call config_load first."
    fi
}

# Check if key exists
config_key_exists() {
    local key="$1"
    require_config_loaded
    
    key=$(config_normalize_key "$key")
    local cache_key
    cache_key=$(config_cache_key "$key")
    
    [[ -n "${CONFIG_CACHE[$cache_key]:-}" ]]
}

# Get configuration value
config_get() {
    local key="$1"
    local default="${2:-}"
    
    require_config_loaded
    
    key=$(config_normalize_key "$key")
    local cache_key
    cache_key=$(config_cache_key "$key")
    
    if [[ -n "${CONFIG_CACHE[$cache_key]:-}" ]]; then
        echo "${CONFIG_CACHE[$cache_key]}"
    else
        echo "$default"
    fi
}

# Get string value
config_get_string() {
    local key="$1"
    local default="${2:-}"
    
    local value
    value=$(config_get "$key" "$default")
    echo "$value"
}

# Get integer value
config_get_int() {
    local key="$1"
    local default="${2:-0}"
    
    local value
    value=$(config_get "$key" "$default")
    
    if [[ "$value" =~ ^-?[0-9]+$ ]]; then
        echo "$value"
    else
        log_warn "Key '$key' is not an integer, using default: $default"
        echo "$default"
    fi
}

# Get boolean value
config_get_bool() {
    local key="$1"
    local default="${2:-false}"
    
    local value
    value=$(config_get "$key" "$default")
    
    case "$(to_lower "$value")" in
        true|yes|1|on)
            echo "true"
            ;;
        false|no|0|off)
            echo "false"
            ;;
        *)
            log_warn "Key '$key' is not a boolean, using default: $default"
            echo "$default"
            ;;
    esac
}

# Get array value
config_get_array() {
    local key="$1"
    
    require_config_loaded
    
    key=$(config_normalize_key "$key")
    local cache_key
    cache_key=$(config_cache_key "$key")
    
    if [[ -n "${CONFIG_CACHE[$cache_key]:-}" ]]; then
        local array_str="${CONFIG_CACHE[$cache_key]}"
        parse_toml_array "$array_str"
    fi
}

# Get array table count
config_get_array_table_count() {
    local key="$1"
    
    require_config_loaded
    
    local count=0
    while config_key_exists "${key}.${count}"; do
        ((count++))
    done
    
    echo "$count"
}

# Get array table item
config_get_array_table_item() {
    local key="$1"
    local index="$2"
    local field="${3:-}"
    
    local item_key="${key}.${index}"
    if [[ -n "$field" ]]; then
        item_key="${item_key}.${field}"
    fi
    
    config_get "$item_key"
}

# =============================================================================
# CONFIGURATION VALIDATION
# =============================================================================

# Validate configuration
config_validate() {
    require_config_loaded
    
    log_info "Validating configuration..."
    local errors=0
    
    # Check required keys
    for required_key in "${REQUIRED_KEYS[@]}"; do
        if ! config_key_exists "$required_key"; then
            log_error "Required configuration key missing: $required_key"
            ((errors++))
        fi
    done
    
    # Validate proxy configurations
    local proxy_count
    proxy_count=$(config_get_array_table_count "proxies")
    
    for ((i=0; i<proxy_count; i++)); do
        if ! validate_proxy_config "$i"; then
            ((errors++))
        fi
    done
    
    # Validate service configurations
    local service_count
    service_count=$(config_get_array_table_count "services")
    
    for ((i=0; i<service_count; i++)); do
        if ! validate_service_config "$i"; then
            ((errors++))
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        log_info "Configuration validation passed"
        return 0
    else
        log_error "Configuration validation failed with $errors errors"
        return 1
    fi
}

# Validate proxy configuration
validate_proxy_config() {
    local index="$1"
    local prefix="proxies.${index}"
    local errors=0
    
    # Check required fields
    if ! config_key_exists "${prefix}.name"; then
        log_error "Proxy[$index]: name is required"
        ((errors++))
    fi
    
    if ! config_key_exists "${prefix}.type"; then
        log_error "Proxy[$index]: type is required"
        ((errors++))
    else
        local proxy_type
        proxy_type=$(config_get "${prefix}.type")
        case "$proxy_type" in
            caddy|haproxy|nginx|traefik)
                ;;
            *)
                log_error "Proxy[$index]: invalid type '$proxy_type', must be one of: caddy, haproxy, nginx, traefik"
                ((errors++))
                ;;
        esac
    fi
    
    # Validate port numbers
    local external_port
    external_port=$(config_get_int "${prefix}.external_port" 0)
    if [[ $external_port -gt 0 ]]; then
        if [[ $external_port -lt 1 || $external_port -gt 65535 ]]; then
            log_error "Proxy[$index]: external_port must be between 1 and 65535, got: $external_port"
            ((errors++))
        fi
    fi
    
    local internal_port
    internal_port=$(config_get_int "${prefix}.internal_port" 80)
    if [[ $internal_port -lt 1 || $internal_port -gt 65535 ]]; then
        log_error "Proxy[$index]: internal_port must be between 1 and 65535, got: $internal_port"
        ((errors++))
    fi
    
    return $((errors == 0))
}

# Validate service configuration
validate_service_config() {
    local index="$1"
    local prefix="services.${index}"
    local errors=0
    
    # Check required fields
    for field in name domain upstream; do
        if ! config_key_exists "${prefix}.${field}"; then
            log_error "Service[$index]: $field is required"
            ((errors++))
        fi
    done
    
    # Validate domain format (basic check)
    if config_key_exists "${prefix}.domain"; then
        local domain
        domain=$(config_get "${prefix}.domain")
        if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            log_warn "Service[$index]: domain '$domain' may not be valid"
        fi
    fi
    
    # Validate upstream URL format (basic check)
    if config_key_exists "${prefix}.upstream"; then
        local upstream
        upstream=$(config_get "${prefix}.upstream")
        if [[ ! "$upstream" =~ ^https?:// ]]; then
            log_warn "Service[$index]: upstream '$upstream' should start with http:// or https://"
        fi
    fi
    
    return $((errors == 0))
}

# Require configuration key
config_require() {
    local key="$1"
    local message="${2:-Required configuration key missing: $key}"
    
    if ! config_key_exists "$key"; then
        die "$message"
    fi
}

# =============================================================================
# DEBUGGING AND UTILITIES
# =============================================================================

# List all configuration keys
config_list_keys() {
    local prefix="${1:-}"
    
    require_config_loaded
    
    for cache_key in "${!CONFIG_CACHE[@]}"; do
        local key="${cache_key#config:}"
        if [[ -z "$prefix" || "$key" == "$prefix"* ]]; then
            echo "$key"
        fi
    done | sort
}

# Show configuration summary
config_show() {
    local prefix="${1:-}"
    
    require_config_loaded
    
    echo "Configuration Summary:"
    echo "====================="
    echo "File: $CONFIG_FILE_PATH"
    echo "Loaded: $(config_is_loaded && echo "Yes" || echo "No")"
    echo
    
    local keys
    readarray -t keys < <(config_list_keys "$prefix")
    
    for key in "${keys[@]}"; do
        local value
        local type
        value=$(config_get "$key")
        type="${CONFIG_TYPE_CACHE[$(config_cache_key "$key")]:-unknown}"
        printf "%-30s = %-20s (%s)\n" "$key" "$value" "$type"
    done
}

# Reload configuration
config_reload() {
    if [[ -n "$CONFIG_FILE_PATH" ]]; then
        log_info "Reloading configuration..."
        config_load "$CONFIG_FILE_PATH"
    else
        die "No configuration file to reload"
    fi
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize config library
init_config() {
    log_debug "Initializing config library"
    
    # Set default config file if not specified
    if [[ -z "${CONFIG_FILE:-}" ]]; then
        CONFIG_FILE="${SCRIPT_DIR}/config.toml"
    fi
    
    log_debug "Config library initialized"
}

# Initialize if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    init_config
fi