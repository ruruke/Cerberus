#!/bin/bash

# Simple TOML Configuration Parser
# Simplified version for testing

set -euo pipefail

# Source utils library
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
source "${SCRIPT_DIR}/lib/core/utils.sh"

# Configuration state
declare -g CONFIG_LOADED=false
declare -g CONFIG_FILE_PATH=""
declare -gA CONFIG_CACHE=()

# Load configuration from TOML file (simplified)
config_load() {
    local config_file="${1:-$CONFIG_FILE}"
    
    if [[ -z "$config_file" ]]; then
        die "Configuration file not specified"
    fi
    
    require_file "$config_file" "configuration file"
    
    CONFIG_FILE_PATH="$config_file"
    CONFIG_CACHE=()
    
    log_info "Loading configuration from: $config_file"
    
    local current_section=""
    local line_number=0
    declare -A array_table_counters
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_number++))
        
        # Remove comments and trim
        line="${line%%#*}"
        line=$(trim "$line")
        
        # Skip empty lines
        [[ -z "$line" ]] && continue
        
        # Handle sections [section] and [[array_section]]
        if [[ "$line" =~ ^\[\[([^\]]+)\]\]$ ]]; then
            # Array table
            local section="${BASH_REMATCH[1]}"
            if [[ -z "$section" ]]; then
                log_error "Invalid array table syntax at line $line_number: $line"
                return 1
            fi
            local count="${array_table_counters[$section]:-0}"
            current_section="${section}.${count}"
            array_table_counters["$section"]=$((count + 1))
            continue
        elif [[ "$line" =~ ^\[([^\]]+)\]$ ]]; then
            # Regular section
            local section="${BASH_REMATCH[1]}"
            if [[ -z "$section" ]]; then
                log_error "Invalid section syntax at line $line_number: $line"
                return 1
            fi
            current_section="$section"
            continue
        fi
        
        # Handle key-value pairs
        if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            key=$(trim "$key")
            value=$(trim "$value")
            
            # Validate key
            if [[ -z "$key" ]]; then
                log_error "Empty key at line $line_number: $line"
                return 1
            fi
            
            # Remove quotes from strings
            if [[ "$value" =~ ^\"(.*)\"$ ]]; then
                value="${BASH_REMATCH[1]}"
            fi
            
            # Build full key
            local full_key="$key"
            if [[ -n "$current_section" ]]; then
                full_key="${current_section}.${key}"
            fi
            
            CONFIG_CACHE["$full_key"]="$value"
        elif [[ -n "$line" ]]; then
            # Non-empty line that doesn't match expected patterns
            log_warn "Unrecognized syntax at line $line_number: $line"
        fi
    done < "$config_file"
    
    CONFIG_LOADED=true
    log_info "Configuration loaded successfully (${#CONFIG_CACHE[@]} keys loaded)"
}

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
    config_is_loaded || return 1
    [[ -n "${CONFIG_CACHE[$key]:-}" ]]
}

# Get configuration value
config_get() {
    local key="$1"
    local default="${2:-}"
    
    config_is_loaded || return 1
    echo "${CONFIG_CACHE[$key]:-$default}"
}

# Get string value
config_get_string() {
    local key="$1"
    local default="${2:-}"
    config_get "$key" "$default"
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
            echo "$default"
            ;;
    esac
}

# Get array table count
config_get_array_table_count() {
    local key="$1"
    
    config_is_loaded || return 1
    
    local count=0
    # Try different ways to detect array table entries
    while config_key_exists "${key}.${count}.name" || 
          config_key_exists "${key}.${count}.type" || 
          config_key_exists "${key}.${count}.domain" || 
          config_key_exists "${key}.${count}.upstream" ||
          config_key_exists "${key}.${count}"; do
        ((count++))
    done
    
    echo "$count"
}

# Simple validation - just check required keys
config_validate() {
    config_is_loaded || return 1
    
    local required_keys=(
        "project.name"
    )
    
    local errors=0
    for key in "${required_keys[@]}"; do
        if ! config_key_exists "$key"; then
            log_error "Required key missing: $key"
            ((errors++))
        fi
    done
    
    return $((errors == 0))
}

# List all keys (for debugging)
config_list_keys() {
    if ! config_is_loaded; then
        return 1
    fi
    
    for key in "${!CONFIG_CACHE[@]}"; do
        echo "$key"
    done | sort
}

# Show configuration
config_show() {
    echo "Configuration loaded from: $CONFIG_FILE_PATH"
    echo "Keys found:"
    for key in "${!CONFIG_CACHE[@]}"; do
        printf "  %-30s = %s\\n" "$key" "${CONFIG_CACHE[$key]}"
    done | sort
}

log_debug "Simple config library loaded"