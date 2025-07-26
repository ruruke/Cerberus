#!/bin/bash

# Simple TOML Configuration Parser
# Supports basic key-value pairs, sections, and array tables
# Designed for Cerberus configuration management

set -euo pipefail

# Environment setup
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

# Source utilities
source "${SCRIPT_DIR}/lib/core/utils.sh"

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

# Configuration state
declare -g CONFIG_LOADED=false
declare -g CONFIG_FILE_PATH=""
declare -gA CONFIG_CACHE

# =============================================================================
# CONFIGURATION LOADING
# =============================================================================

# Load configuration from TOML file
# Usage: config_load [config_file]
config_load() {
    local config_file="${1:-${CONFIG_FILE:-}}"
    
    # Validation
    if [[ -z "$config_file" ]]; then
        log_error "No configuration file specified"
        return 1
    fi
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    if [[ ! -r "$config_file" ]]; then
        log_error "Configuration file not readable: $config_file"
        return 1
    fi
    
    # Initialize state
    CONFIG_FILE_PATH="$config_file"
    CONFIG_CACHE=()
    
    log_info "Loading configuration from: $config_file"
    
    # Parse configuration
    local current_section=""
    local line_number=0
    local -A array_counters  # Track array table instances
    
    log_debug "About to start reading file"
    
    # Process file line by line
    while IFS= read -r raw_line; do
        ((line_number++))
        log_debug "Read line $line_number: $raw_line"
        
        # Remove comments and trim whitespace
        local line="${raw_line%%#*}"
        # Simple trim without function call
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        
        # Skip empty lines
        [[ -z "$line" ]] && continue
        
        # Process line based on type
        if [[ "$line" =~ ^\[\[([^\]]+)\]\]$ ]]; then
            # Array table: [[section]]
            local section="${BASH_REMATCH[1]}"
            local count="${array_counters[$section]:-0}"
            current_section="${section}.${count}"
            array_counters["$section"]=$((count + 1))
            log_debug "Array table: [$current_section]"
            
        elif [[ "$line" =~ ^\[([^\]]+)\]$ ]]; then
            # Regular section: [section]
            current_section="${BASH_REMATCH[1]}"
            log_debug "Section: [$current_section]"
            
        elif [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
            # Key-value pair: key = value
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            # Clean key and value - simple trim
            key="${key#"${key%%[![:space:]]*}"}"
            key="${key%"${key##*[![:space:]]}"}"
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"
            
            # Remove quotes from string values
            if [[ "$value" =~ ^\"(.*)\"$ ]]; then
                value="${BASH_REMATCH[1]}"
            fi
            
            # Build full key path
            local full_key="$key"
            if [[ -n "$current_section" ]]; then
                full_key="${current_section}.${key}"
            fi
            
            # Store in cache
            CONFIG_CACHE["$full_key"]="$value"
            log_debug "Config: $full_key = $value"
            
        elif [[ -n "$line" ]]; then
            # Unrecognized syntax
            log_warn "Unknown syntax at line $line_number: $line"
        fi
        
    done < "$config_file"
    
    # Mark as loaded
    CONFIG_LOADED=true
    log_info "Configuration loaded successfully (${#CONFIG_CACHE[@]} keys)"
    
    return 0
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
        log_error "Configuration not loaded. Call config_load first."
        return 1
    fi
}

# Check if configuration key exists
# Usage: config_has_key "key.path"
config_has_key() {
    local key="$1"
    require_config_loaded
    [[ -n "${CONFIG_CACHE[$key]:-}" ]]
}

# Get string value from configuration
# Usage: config_get_string "key.path" [default_value]
config_get_string() {
    local key="$1"
    local default="${2:-}"
    
    require_config_loaded
    
    local value="${CONFIG_CACHE[$key]:-$default}"
    echo "$value"
}

# Get integer value from configuration
# Usage: config_get_int "key.path" [default_value]
config_get_int() {
    local key="$1"
    local default="${2:-0}"
    
    local value
    value=$(config_get_string "$key" "$default")
    
    # Validate integer
    if [[ ! "$value" =~ ^-?[0-9]+$ ]]; then
        log_warn "Invalid integer value for $key: $value (using default: $default)"
        echo "$default"
        return 1
    fi
    
    echo "$value"
}

# Get boolean value from configuration
# Usage: config_get_bool "key.path" [default_value]
config_get_bool() {
    local key="$1"
    local default="${2:-false}"
    
    local value
    value=$(config_get_string "$key" "$default")
    
    # Convert to lowercase for comparison
    value=$(echo "$value" | tr '[:upper:]' '[:lower:]')
    
    case "$value" in
        true|yes|1|on|enabled)
            echo "true"
            ;;
        false|no|0|off|disabled)
            echo "false"
            ;;
        *)
            log_warn "Invalid boolean value for $key: $value (using default: $default)"
            echo "$default"
            return 1
            ;;
    esac
}

# Get array table count
# Usage: config_get_array_table_count "table_name"
config_get_array_table_count() {
    local table="$1"
    require_config_loaded
    
    local count=0
    local pattern="^${table}\\.[0-9]+\\."
    
    # Count matching keys
    for key in "${!CONFIG_CACHE[@]}"; do
        if [[ "$key" =~ $pattern ]]; then
            local index
            index=$(echo "$key" | sed "s/^${table}\\.//" | cut -d. -f1)
            if [[ "$index" =~ ^[0-9]+$ ]] && [[ $index -ge $count ]]; then
                count=$((index + 1))
            fi
        fi
    done
    
    echo "$count"
}

# =============================================================================
# DEBUGGING AND UTILITIES
# =============================================================================

# List all configuration keys (for debugging)
config_list_keys() {
    require_config_loaded
    
    echo "Configuration keys:"
    for key in "${!CONFIG_CACHE[@]}"; do
        echo "  $key = ${CONFIG_CACHE[$key]}"
    done | sort
}

# Get configuration statistics
config_stats() {
    require_config_loaded
    
    echo "Configuration Statistics:"
    echo "  File: $CONFIG_FILE_PATH"
    echo "  Keys: ${#CONFIG_CACHE[@]}"
    echo "  Loaded: $CONFIG_LOADED"
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    log_debug "Config library loaded"
fi