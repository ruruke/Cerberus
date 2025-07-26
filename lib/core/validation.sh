#!/bin/bash

# Cerberus Validation Library
# Common validation functions used across generators

set -euo pipefail

# Source required libraries
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
source "${SCRIPT_DIR}/lib/core/utils.sh"

# =============================================================================
# COMMON FILE VALIDATION
# =============================================================================

# Validate file exists and is readable
validate_file_exists() {
    local file="$1"
    local description="${2:-file}"
    
    if [[ ! -f "$file" ]]; then
        log_error "$description not found: $file"
        return 1
    fi
    
    if [[ ! -r "$file" ]]; then
        log_error "$description not readable: $file"
        return 1
    fi
    
    return 0
}

# Validate directory exists and is writable
validate_directory() {
    local dir="$1"
    local description="${2:-directory}"
    
    if [[ ! -d "$dir" ]]; then
        log_error "$description not found: $dir"
        return 1
    fi
    
    if [[ ! -w "$dir" ]]; then
        log_error "$description not writable: $dir"
        return 1
    fi
    
    return 0
}

# Validate JSON syntax
validate_json() {
    local file="$1"
    local description="${2:-JSON file}"
    
    validate_file_exists "$file" "$description" || return 1
    
    if command -v jq >/dev/null 2>&1; then
        if jq . "$file" >/dev/null 2>&1; then
            log_debug "$description syntax validation passed"
            return 0
        else
            log_error "Invalid JSON syntax in $file"
            return 1
        fi
    else
        log_warn "jq not available, skipping JSON validation for $file"
        return 0
    fi
}

# Validate YAML syntax
validate_yaml() {
    local file="$1"
    local description="${2:-YAML file}"
    
    validate_file_exists "$file" "$description" || return 1
    
    if command -v yq >/dev/null 2>&1; then
        if yq eval '.' "$file" >/dev/null 2>&1; then
            log_debug "$description syntax validation passed"
            return 0
        else
            log_error "Invalid YAML syntax in $file"
            return 1
        fi
    else
        log_warn "yq not available, skipping YAML validation for $file"
        return 0
    fi
}

# =============================================================================
# DOCKER VALIDATION
# =============================================================================

# Validate Docker Compose file
validate_docker_compose_file() {
    local compose_file="${1:-${BUILT_DIR}/docker-compose.yaml}"
    
    validate_file_exists "$compose_file" "Docker Compose file" || return 1
    
    # Check Docker Compose availability and validate
    if command -v docker-compose >/dev/null 2>&1; then
        if docker-compose -f "$compose_file" config >/dev/null 2>&1; then
            log_debug "Docker Compose syntax validation passed"
            return 0
        else
            log_error "Docker Compose syntax validation failed"
            return 1
        fi
    elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        if docker compose -f "$compose_file" config >/dev/null 2>&1; then
            log_debug "Docker Compose syntax validation passed"
            return 0
        else
            log_error "Docker Compose syntax validation failed"
            return 1
        fi
    else
        log_warn "Docker Compose not available, performing basic validation"
        validate_yaml "$compose_file" "Docker Compose file"
    fi
}

# Validate Dockerfile
validate_dockerfile() {
    local dockerfile="$1"
    local description="${2:-Dockerfile}"
    
    validate_file_exists "$dockerfile" "$description" || return 1
    
    # Check for required FROM instruction
    if ! grep -q "^FROM " "$dockerfile"; then
        log_error "$description missing FROM instruction"
        return 1
    fi
    
    log_debug "$description validation passed"
    return 0
}

# =============================================================================
# CONFIGURATION VALIDATION
# =============================================================================

# Validate proxy configuration file
validate_proxy_config() {
    local config_file="$1"
    local proxy_type="$2"
    local description="${3:-$proxy_type configuration}"
    
    validate_file_exists "$config_file" "$description" || return 1
    
    case "$proxy_type" in
        nginx)
            # Basic nginx config validation
            if command -v nginx >/dev/null 2>&1; then
                if nginx -t -c "$config_file" 2>/dev/null; then
                    log_debug "$description syntax validation passed"
                    return 0
                else
                    log_error "$description syntax validation failed"
                    return 1
                fi
            else
                log_warn "nginx not available, skipping syntax validation for $config_file"
            fi
            ;;
        caddy)
            # Basic Caddy config validation
            if command -v caddy >/dev/null 2>&1; then
                if caddy validate --config "$config_file" 2>/dev/null; then
                    log_debug "$description syntax validation passed"
                    return 0
                else
                    log_error "$description syntax validation failed"
                    return 1
                fi
            else
                log_warn "caddy not available, skipping syntax validation for $config_file"
            fi
            ;;
        haproxy)
            # Basic HAProxy config validation
            if command -v haproxy >/dev/null 2>&1; then
                if haproxy -c -f "$config_file" 2>/dev/null; then
                    log_debug "$description syntax validation passed"
                    return 0
                else
                    log_error "$description syntax validation failed"
                    return 1
                fi
            else
                log_warn "haproxy not available, skipping syntax validation for $config_file"
            fi
            ;;
        traefik)
            # Basic Traefik config validation (YAML/YML)
            validate_yaml "$config_file" "$description"
            ;;
        *)
            log_warn "Unknown proxy type: $proxy_type, performing basic file validation"
            validate_file_exists "$config_file" "$description"
            ;;
    esac
    
    return 0
}

# =============================================================================
# NETWORK VALIDATION
# =============================================================================

# Check if port is available
validate_port_available() {
    local port="$1"
    local description="${2:-Port $port}"
    
    if command -v netstat >/dev/null 2>&1; then
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            log_error "$description is already in use"
            return 1
        fi
    elif command -v ss >/dev/null 2>&1; then
        if ss -tuln 2>/dev/null | grep -q ":$port "; then
            log_error "$description is already in use"
            return 1
        fi
    else
        log_warn "netstat/ss not available, skipping port validation for $port"
    fi
    
    log_debug "$description is available"
    return 0
}

# Validate URL format
validate_url() {
    local url="$1"
    local description="${2:-URL}"
    
    if [[ ! "$url" =~ ^https?://[^/]+(/.*)?$ ]]; then
        log_error "Invalid $description format: $url"
        return 1
    fi
    
    log_debug "$description format validation passed"
    return 0
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize validation library
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    log_debug "Validation library loaded"
fi