#!/bin/bash

# Cerberus Template Manager
# Template creation, management, and application

set -euo pipefail

# Source required libraries
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
source "${SCRIPT_DIR}/lib/core/utils.sh"

# =============================================================================
# CONSTANTS
# =============================================================================

readonly TEMPLATES_DIR="${SCRIPT_DIR}/lib/templates"
readonly USER_TEMPLATES_DIR="${HOME}/.cerberus/templates"
readonly BUILT_TEMPLATES_DIR="${BUILT_DIR}/templates"

# Built-in templates
readonly BUILTIN_TEMPLATES=("basic" "advanced" "minimal" "misskey" "wordpress" "nextjs")

# =============================================================================
# TEMPLATE UTILITIES
# =============================================================================

# Initialize template directories
init_template_dirs() {
    safe_mkdir "$TEMPLATES_DIR"
    safe_mkdir "$USER_TEMPLATES_DIR"
    safe_mkdir "$BUILT_TEMPLATES_DIR"
}

# List available templates
list_templates() {
    local show_builtin="${1:-true}"
    local show_user="${2:-true}"
    
    echo "Available Templates:"
    echo "==================="
    
    if [[ "$show_builtin" == "true" ]]; then
        echo
        echo "Built-in Templates:"
        echo "-------------------"
        for template in "${BUILTIN_TEMPLATES[@]}"; do
            local template_file="${TEMPLATES_DIR}/${template}.toml"
            if [[ -f "$template_file" ]]; then
                local description
                description=$(get_template_description "$template_file")
                echo "  ✓ $template - $description"
            else
                echo "  ✗ $template - (template file missing)"
            fi
        done
    fi
    
    if [[ "$show_user" == "true" ]]; then
        echo
        echo "User Templates:"
        echo "---------------"
        if [[ -d "$USER_TEMPLATES_DIR" ]]; then
            local found_user_templates=""
            for template_file in "$USER_TEMPLATES_DIR"/*.toml; do
                if [[ -f "$template_file" ]]; then
                    local template_name
                    template_name=$(basename "$template_file" .toml)
                    local description
                    description=$(get_template_description "$template_file")
                    echo "  ✓ $template_name - $description"
                    found_user_templates="true"
                fi
            done
            
            if [[ -z "$found_user_templates" ]]; then
                echo "  (no user templates found)"
            fi
        else
            echo "  (user templates directory not found)"
        fi
    fi
}

# Get template description from file
get_template_description() {
    local template_file="$1"
    
    if [[ -f "$template_file" ]]; then
        # Try to extract description from template comment
        if grep -q "^# Description:" "$template_file" 2>/dev/null; then
            grep "^# Description:" "$template_file" | head -1 | cut -d':' -f2- | sed 's/^ *//'
        else
            echo "No description available"
        fi
    else
        echo "Template file not found"
    fi
}

# Check if template exists
template_exists() {
    local template_name="$1"
    
    # Check built-in templates
    if [[ -f "${TEMPLATES_DIR}/${template_name}.toml" ]]; then
        return 0
    fi
    
    # Check user templates
    if [[ -f "${USER_TEMPLATES_DIR}/${template_name}.toml" ]]; then
        return 0
    fi
    
    return 1
}

# Get template path
get_template_path() {
    local template_name="$1"
    
    # Check built-in templates first
    if [[ -f "${TEMPLATES_DIR}/${template_name}.toml" ]]; then
        echo "${TEMPLATES_DIR}/${template_name}.toml"
        return 0
    fi
    
    # Check user templates
    if [[ -f "${USER_TEMPLATES_DIR}/${template_name}.toml" ]]; then
        echo "${USER_TEMPLATES_DIR}/${template_name}.toml"
        return 0
    fi
    
    return 1
}

# =============================================================================
# TEMPLATE CREATION
# =============================================================================

# Create built-in templates
create_builtin_templates() {
    init_template_dirs
    
    log_info "Creating built-in templates..."
    
    # Basic template
    create_basic_template
    create_advanced_template
    create_minimal_template
    create_misskey_template
    create_wordpress_template
    create_nextjs_template
    
    log_info "Built-in templates created successfully"
}

# Create basic template
create_basic_template() {
    cat > "${TEMPLATES_DIR}/basic.toml" << 'EOF'
# Description: Basic multi-layer proxy with Nginx and Anubis DDoS protection
# Use case: Simple web applications with basic DDoS protection

[project]
name = "basic-proxy"
version = "1.0.0"
scaling = false

# Simple Nginx proxy
[[proxies]]
name = "nginx-proxy"
type = "nginx"
external_port = 80
internal_port = 80
instances = 1
upstream = "http://web:3000"

# Basic Anubis DDoS protection
[anubis]
enabled = true
bind = ":8080"
difficulty = 5
target = "http://nginx-proxy:80"
metrics_bind = ":9090"

# Web application service
[[services]]
name = "web"
domain = "example.com"
upstream = "http://127.0.0.1:3000"
websocket = false
compress = true
max_body_size = "10m"
EOF
}

# Create advanced template
create_advanced_template() {
    cat > "${TEMPLATES_DIR}/advanced.toml" << 'EOF'
# Description: Advanced multi-layer proxy with HAProxy, Nginx, and auto-scaling
# Use case: High-traffic applications requiring load balancing and auto-scaling

[project]
name = "advanced-proxy"
version = "1.0.0"
scaling = true

# HAProxy load balancer (Layer 1)
[[proxies]]
name = "haproxy-lb"
type = "haproxy"
external_port = 80
internal_port = 80
instances = 2
upstream = "http://anubis:8080"
max_connections = 4096

# Nginx backend proxy (Layer 2)
[[proxies]]
name = "nginx-backend"
type = "nginx"
external_port = 8080
internal_port = 80
instances = 3
upstream = "http://web:3000"

# Advanced Anubis DDoS protection
[anubis]
enabled = true
bind = ":8080"
difficulty = 7
target = "http://nginx-backend:80"
metrics_bind = ":9090"

# Multiple services
[[services]]
name = "web"
domain = "app.example.com"
upstream = "http://127.0.0.1:3000"
websocket = true
compress = true
max_body_size = "100m"

[[services]]
name = "api"
domain = "api.example.com"
upstream = "http://127.0.0.1:4000"
websocket = false
compress = true
max_body_size = "50m"

# Auto-scaling configuration
[scaling]
enabled = true
check_interval = "30s"
min_instances = 1
max_instances = 10

[scaling.metrics]
cpu_threshold = 75
memory_threshold = 80
connections_threshold = 2000
response_time_threshold = 1500

[scaling.rules]
scale_up_cooldown = "3m"
scale_down_cooldown = "10m"
EOF
}

# Create minimal template
create_minimal_template() {
    cat > "${TEMPLATES_DIR}/minimal.toml" << 'EOF'
# Description: Minimal proxy setup with just Nginx
# Use case: Development environments or simple static sites

[project]
name = "minimal-proxy"
version = "1.0.0"
scaling = false

# Single Nginx proxy
[[proxies]]
name = "nginx"
type = "nginx"
external_port = 80
internal_port = 80
instances = 1
upstream = "http://web:80"

# No Anubis (disabled)
[anubis]
enabled = false

# Simple web service
[[services]]
name = "web"
domain = "localhost"
upstream = "http://127.0.0.1:8080"
websocket = false
compress = false
max_body_size = "1m"
EOF
}

# Create Misskey template
create_misskey_template() {
    cat > "${TEMPLATES_DIR}/misskey.toml" << 'EOF'
# Description: Optimized setup for Misskey social media platform
# Use case: Misskey instances with media proxy and high traffic handling

[project]
name = "misskey-proxy"
version = "1.0.0"
scaling = true

# HAProxy for main traffic
[[proxies]]
name = "haproxy-main"
type = "haproxy"
external_port = 80
internal_port = 80
instances = 2
upstream = "http://anubis:8080"
max_connections = 8192

# Nginx for media proxy
[[proxies]]
name = "nginx-media"
type = "nginx"
external_port = 8080
internal_port = 80
instances = 2
upstream = "http://media-proxy:12766"

# Anubis with Misskey-specific rules
[anubis]
enabled = true
bind = ":8080"
difficulty = 6
target = "http://nginx-backend:80"
metrics_bind = ":9090"

# Misskey main service
[[services]]
name = "misskey"
domain = "mi.example.com"
upstream = "http://127.0.0.1:3000"
websocket = true
compress = true
max_body_size = "100m"

# Media proxy service
[[services]]
name = "media-proxy"
domain = "media.example.com"
upstream = "http://127.0.0.1:12766"
websocket = false
compress = true
max_body_size = "500m"

# Summaly service
[[services]]
name = "summaly"
domain = "summaly.example.com"
upstream = "http://127.0.0.1:3030"
websocket = false
compress = false
max_body_size = "1m"

# Auto-scaling for high traffic
[scaling]
enabled = true
check_interval = "20s"
min_instances = 2
max_instances = 15

[scaling.metrics]
cpu_threshold = 70
memory_threshold = 75
connections_threshold = 3000
response_time_threshold = 1000

[scaling.rules]
scale_up_cooldown = "2m"
scale_down_cooldown = "15m"
EOF
}

# Create WordPress template
create_wordpress_template() {
    cat > "${TEMPLATES_DIR}/wordpress.toml" << 'EOF'
# Description: WordPress optimized proxy setup with caching
# Use case: WordPress sites with high traffic and caching requirements

[project]
name = "wordpress-proxy"
version = "1.0.0"
scaling = true

# Nginx with WordPress optimizations
[[proxies]]
name = "nginx-wp"
type = "nginx"
external_port = 80
internal_port = 80
instances = 2
upstream = "http://wordpress:80"

# Light Anubis protection
[anubis]
enabled = true
bind = ":8080"
difficulty = 4
target = "http://nginx-wp:80"
metrics_bind = ":9090"

# WordPress service
[[services]]
name = "wordpress"
domain = "blog.example.com"
upstream = "http://127.0.0.1:8080"
websocket = false
compress = true
max_body_size = "50m"

# Auto-scaling for WordPress
[scaling]
enabled = true
check_interval = "60s"
min_instances = 1
max_instances = 5

[scaling.metrics]
cpu_threshold = 85
memory_threshold = 90
connections_threshold = 1000
response_time_threshold = 3000

[scaling.rules]
scale_up_cooldown = "5m"
scale_down_cooldown = "20m"
EOF
}

# Create Next.js template
create_nextjs_template() {
    cat > "${TEMPLATES_DIR}/nextjs.toml" << 'EOF'
# Description: Next.js application proxy with server-side rendering support
# Use case: React/Next.js applications with SSR and API routes

[project]
name = "nextjs-proxy"
version = "1.0.0"
scaling = true

# Nginx optimized for Next.js
[[proxies]]
name = "nginx-nextjs"
type = "nginx"
external_port = 80
internal_port = 80
instances = 2
upstream = "http://nextjs:3000"

# Moderate Anubis protection
[anubis]
enabled = true
bind = ":8080"
difficulty = 5
target = "http://nginx-nextjs:80"
metrics_bind = ":9090"

# Next.js application
[[services]]
name = "nextjs"
domain = "app.example.com"
upstream = "http://127.0.0.1:3000"
websocket = true
compress = true
max_body_size = "20m"

# API service (separate)
[[services]]
name = "api"
domain = "api.example.com"
upstream = "http://127.0.0.1:4000"
websocket = false
compress = true
max_body_size = "10m"

# Auto-scaling for dynamic applications
[scaling]
enabled = true
check_interval = "30s"
min_instances = 1
max_instances = 8

[scaling.metrics]
cpu_threshold = 80
memory_threshold = 85
connections_threshold = 1500
response_time_threshold = 2000

[scaling.rules]
scale_up_cooldown = "3m"
scale_down_cooldown = "12m"
EOF
}

# =============================================================================
# TEMPLATE MANAGEMENT
# =============================================================================

# Create custom template
create_custom_template() {
    local template_name="$1"
    local base_template="${2:-basic}"
    
    if [[ -z "$template_name" ]]; then
        log_error "Template name is required"
        return 1
    fi
    
    init_template_dirs
    
    local template_file="${USER_TEMPLATES_DIR}/${template_name}.toml"
    
    if [[ -f "$template_file" ]]; then
        log_error "Template '$template_name' already exists"
        return 1
    fi
    
    # Get base template path
    local base_path
    if ! base_path=$(get_template_path "$base_template"); then
        log_error "Base template '$base_template' not found"
        return 1
    fi
    
    # Copy base template
    if safe_copy "$base_path" "$template_file"; then
        # Update template metadata
        sed -i "1i# Description: Custom template based on $base_template" "$template_file"
        sed -i "s/name = \"[^\"]*\"/name = \"$template_name\"/" "$template_file"
        
        log_info "Custom template '$template_name' created at: $template_file"
        print_info "Edit the template file to customize configuration"
        return 0
    else
        log_error "Failed to create custom template"
        return 1
    fi
}

# Delete template
delete_template() {
    local template_name="$1"
    
    if [[ -z "$template_name" ]]; then
        log_error "Template name is required"
        return 1
    fi
    
    # Only allow deletion of user templates
    local template_file="${USER_TEMPLATES_DIR}/${template_name}.toml"
    
    if [[ ! -f "$template_file" ]]; then
        log_error "User template '$template_name' not found"
        return 1
    fi
    
    # Confirm deletion
    echo -n "Delete template '$template_name'? (y/N): "
    read -r confirmation
    
    if [[ "$confirmation" =~ ^[Yy]$ ]]; then
        if rm "$template_file"; then
            log_info "Template '$template_name' deleted"
            return 0
        else
            log_error "Failed to delete template '$template_name'"
            return 1
        fi
    else
        log_info "Template deletion cancelled"
        return 1
    fi
}

# Apply template to create configuration
apply_template() {
    local template_name="$1"
    local output_file="${2:-config.toml}"
    local project_name="${3:-}"
    
    if [[ -z "$template_name" ]]; then
        log_error "Template name is required"
        return 1
    fi
    
    local template_path
    if ! template_path=$(get_template_path "$template_name"); then
        log_error "Template '$template_name' not found"
        return 1
    fi
    
    # Create output directory if needed
    safe_mkdir "$(dirname "$output_file")"
    
    # Copy template to output
    if safe_copy "$template_path" "$output_file"; then
        # Update project name if provided
        if [[ -n "$project_name" ]]; then
            sed -i "s/name = \"[^\"]*\"/name = \"$project_name\"/" "$output_file"
        fi
        
        log_info "Applied template '$template_name' to: $output_file"
        return 0
    else
        log_error "Failed to apply template '$template_name'"
        return 1
    fi
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize template manager
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    log_debug "Template manager loaded"
    
    # Create built-in templates if they don't exist
    if [[ ! -f "${TEMPLATES_DIR}/basic.toml" ]]; then
        create_builtin_templates
    fi
fi