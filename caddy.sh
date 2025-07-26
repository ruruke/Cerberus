#!/bin/bash

# Caddyfile Generator Script
# Generates Caddyfile from config.yaml

set -euo pipefail

# Default values
CONFIG_FILE=""
OUTPUT_DIR="."
DRY_RUN=false
VERBOSE=false
BACKUP=false
NO_COLOR=false

# Color codes
if [[ -t 1 ]] && [[ "${NO_COLOR:-}" != "true" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    NC=''
fi

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $*" >&2
    fi
}

show_help() {
    cat << EOF
${BLUE}Caddyfile Generator Script${NC}
Generates Caddyfiles from config.yaml

${YELLOW}Usage:${NC}
    $0 [OPTIONS] [CONFIG_FILE] [OUTPUT_DIR]

${YELLOW}Arguments:${NC}
    CONFIG_FILE     Configuration YAML file (default: config.yaml)
    OUTPUT_DIR      Output directory (default: current directory)

${YELLOW}Options:${NC}
    -d, --dry-run      Show what would be generated without writing files
    -b, --backup       Create backup of existing Caddyfiles
    -v, --verbose      Enable verbose output
    -h, --help         Show this help message
    --no-color         Disable colored output
    --validate-only    Only validate configuration without generating

${YELLOW}Examples:${NC}
    $0                              # Use config.yaml in current directory
    $0 --dry-run                    # Preview what would be generated
    $0 --backup config.yaml .       # Generate with backup
    $0 --verbose my-config.yaml ./output/

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -b|--backup)
                BACKUP=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            --no-color)
                NO_COLOR=true
                RED=''
                GREEN=''
                YELLOW=''
                BLUE=''
                CYAN=''
                NC=''
                shift
                ;;
            --validate-only)
                VALIDATE_ONLY=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                if [[ -z "$CONFIG_FILE" ]]; then
                    CONFIG_FILE="$1"
                elif [[ -z "$OUTPUT_DIR" || "$OUTPUT_DIR" == "." ]]; then
                    OUTPUT_DIR="$1"
                else
                    log_error "Too many arguments"
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Set defaults if not provided
    CONFIG_FILE="${CONFIG_FILE:-config.yaml}"
    OUTPUT_DIR="${OUTPUT_DIR:-.}"
}

# Validate configuration file
validate_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Config file '$CONFIG_FILE' not found"
        exit 1
    fi
    
    log_debug "Validating YAML syntax for $CONFIG_FILE"
    
    # Basic YAML syntax validation
    if command -v yq >/dev/null 2>&1; then
        if ! yq eval '.' "$CONFIG_FILE" >/dev/null 2>&1; then
            log_error "Invalid YAML syntax in $CONFIG_FILE"
            exit 1
        fi
        log_debug "YAML syntax validation passed"
    else
        log_warning "yq not found, skipping YAML syntax validation"
    fi
}

# Create backup if requested
create_backup() {
    if [[ "$BACKUP" == "true" ]]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_dir="${OUTPUT_DIR}/backup_${timestamp}"
        
        log_info "Creating backup in $backup_dir"
        mkdir -p "$backup_dir"
        
        if [[ -f "${OUTPUT_DIR}/proxy/Caddyfile" ]]; then
            cp "${OUTPUT_DIR}/proxy/Caddyfile" "$backup_dir/proxy_Caddyfile"
            log_debug "Backed up proxy/Caddyfile"
        fi
        
        if [[ -f "${OUTPUT_DIR}/proxy-2/Caddyfile" ]]; then
            cp "${OUTPUT_DIR}/proxy-2/Caddyfile" "$backup_dir/proxy-2_Caddyfile"
            log_debug "Backed up proxy-2/Caddyfile"
        fi
        
        log_success "Backup created successfully"
    fi
}

# Write file or show dry-run output
write_file() {
    local file_path="$1"
    local content="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would write to: $file_path"
        echo -e "${CYAN}--- Content Preview ---${NC}"
        echo "$content" | head -20
        if [[ $(echo "$content" | wc -l) -gt 20 ]]; then
            echo -e "${CYAN}... (content truncated, $(echo "$content" | wc -l) total lines)${NC}"
        fi
        echo -e "${CYAN}--- End Preview ---${NC}"
        echo
    else
        log_debug "Writing to $file_path"
        echo "$content" > "$file_path"
    fi
}

# Function to parse YAML (simple implementation)
parse_yaml() {
    local prefix=${2:-""}
    local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
    sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p" $1 |
    awk -F$fs '{
        indent = length($1)/2;
        vname[indent] = $2;
        for (i in vname) {if (i > indent) {delete vname[i]}}
        if (length($3) > 0) {
            vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
            printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
        }
    }'
}


# Generate proxy layer 1 Caddyfile  
generate_proxy_layer1() {
    local auto_https_setting="${global_auto_https:-off}"
    local admin_setting="${global_admin:-off}"
    
    log_debug "Generating proxy layer 1 Caddyfile"
    
    # Generate global block
    local content
    content=$(cat << EOF
{
    auto_https ${auto_https_setting}
    admin ${admin_setting}
$(generate_tls_config)
}

# Default routing (to anubis)
:80 {
    @media host media.ruruke.moe
    @summaly host summaly.ruruke.moe  
    @storage host storage.ruruke.moe
    
    # Direct routes (bypass anubis)
    handle @media {
        reverse_proxy http://proxy-2:80 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
        }
    }
    
    handle @summaly {
        reverse_proxy http://proxy-2:80 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
        }
    }
    
    handle @storage {
        reverse_proxy http://proxy-2:80 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
        }
    }
    
    # Default route to anubis
    handle {
        reverse_proxy http://anubis:8080 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
        }
    }
}

# Misskey special routing
mi.ruruke.moe:80 {
    # Bypass anubis for specific paths
    @bypass path /streaming* /inbox* /outbox* /api* /.well-known*
    
    handle @bypass {
        reverse_proxy http://proxy-2:80 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
            header_up Upgrade {>Upgrade}
            header_up Connection {>Connection}
        }
    }
    
    # Default route to anubis
    handle {
        reverse_proxy http://anubis:8080 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
        }
    }
}
EOF
)
    
    write_file "${OUTPUT_DIR}/proxy/Caddyfile" "$content"
}

# Generate TLS configuration block
generate_tls_config() {
    if [[ "${tls_enabled:-false}" == "true" ]]; then
        echo "    # TLS Configuration"
        
        # Internal CA configuration
        if [[ "${tls_ca_enabled:-false}" == "true" ]]; then
            echo "    pki {"
            echo "        ca local {"
            echo "            root_cert_file ${tls_ca_root_cert:-/etc/ssl/ca.crt}"
            echo "            root_key_file ${tls_ca_root_key:-/etc/ssl/ca.key}"
            echo "        }"
            echo "    }"
        fi
        
        # Custom certificates (if defined)
        # This would need more complex YAML parsing for arrays
        # For now, users can manually add certificate configuration
    fi
}

# Generate proxy layer 2 Caddyfile
generate_proxy_layer2() {
    local auto_https_setting="${global_auto_https:-off}"
    local admin_setting="${global_admin:-off}"
    local log_level="${logging_level:-INFO}"
    local log_format="${logging_format:-json}"
    local log_output="${logging_output:-/var/log/caddy/caddy.log}"
    
    log_debug "Generating proxy layer 2 Caddyfile"
    
    # Generate global block
    local content
    content=$(cat << EOF
{
    auto_https ${auto_https_setting}
    admin ${admin_setting}
$(generate_tls_config)
    log {
        output file ${log_output}
        format ${log_format}
        level ${log_level}
    }
}

# Misskey service
mi.ruruke.moe:80 {
    reverse_proxy http://100.103.133.21:3000 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
        header_up Upgrade {>Upgrade}
        header_up Connection {>Connection}
    }
    
    request_body {
        max_size 100MB
    }
    
    log {
        output file /var/log/caddy/misskey_access.log
        format json
    }
}

# Media proxy service
media.ruruke.moe:80 {
    reverse_proxy http://100.97.11.65:12766 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
    
    log {
        output file /var/log/caddy/media_proxy_access.log
        format json
    }
}

# Storage service (S3 proxy)
storage.ruruke.moe:80 {
    reverse_proxy https://s3.ap-northeast-2-ntt.wasabisys.com/storage.ruruke.moe/ {
        header_up Host s3.us-east-2.wasabisys.com
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-Proto https
        header_up Proxy ""
        header_down Cache-Control "public, max-age=2592000"
        header_down Pragma "public"
    }
    
    request_body {
        max_size 1000MB
    }
    
    encode gzip
    
    log {
        output file /var/log/caddy/storage_access.log
        format json
    }
}

# Summaly service
summaly.ruruke.moe:80 {
    reverse_proxy http://100.114.43.64:3030 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
    
    log {
        output file /var/log/caddy/summaly_access.log
        format json
    }
}

# Homepage
ruru.my:80 {
    reverse_proxy http://100.114.43.64:8080 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
    
    log {
        output file /var/log/caddy/homepage_access.log
        format json
    }
}
EOF
)
    
    write_file "${OUTPUT_DIR}/proxy-2/Caddyfile" "$content"
}

# Validate generated Caddyfiles
validate_caddyfiles() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would validate Caddyfiles"
        return 0
    fi
    
    if ! command -v caddy >/dev/null 2>&1; then
        log_warning "caddy command not found, skipping validation"
        return 0
    fi
    
    log_info "Validating generated Caddyfiles..."
    local validation_failed=false
    
    if [[ -f "${OUTPUT_DIR}/proxy/Caddyfile" ]]; then
        if caddy validate --config "${OUTPUT_DIR}/proxy/Caddyfile" >/dev/null 2>&1; then
            log_success "proxy/Caddyfile is valid"
        else
            log_error "proxy/Caddyfile validation failed"
            validation_failed=true
        fi
    fi
    
    if [[ -f "${OUTPUT_DIR}/proxy-2/Caddyfile" ]]; then
        if caddy validate --config "${OUTPUT_DIR}/proxy-2/Caddyfile" >/dev/null 2>&1; then
            log_success "proxy-2/Caddyfile is valid"
        else
            log_error "proxy-2/Caddyfile validation failed"
            validation_failed=true
        fi
    fi
    
    if [[ "$validation_failed" == "true" ]]; then
        exit 1
    fi
}

# Main execution
main() {
    # Parse arguments
    parse_args "$@"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Running in DRY RUN mode - no files will be written"
    fi
    
    log_info "Generating Caddyfiles from $CONFIG_FILE..."
    
    # Validate configuration
    validate_config
    
    # Parse YAML configuration
    log_debug "Parsing YAML configuration"
    if ! eval $(parse_yaml "$CONFIG_FILE"); then
        log_error "Failed to parse YAML configuration"
        exit 1
    fi
    
    # Create backup if requested
    create_backup
    
    # Create directories if they don't exist
    if [[ "$DRY_RUN" != "true" ]]; then
        mkdir -p "${OUTPUT_DIR}/proxy"
        mkdir -p "${OUTPUT_DIR}/proxy-2"
        log_debug "Created output directories"
    fi
    
    # Generate Caddyfiles
    generate_proxy_layer1
    generate_proxy_layer2
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log_success "Generated Caddyfiles:"
        log_success "  - ${OUTPUT_DIR}/proxy/Caddyfile"
        log_success "  - ${OUTPUT_DIR}/proxy-2/Caddyfile"
        
        # Validate generated files
        validate_caddyfiles
        log_success "All operations completed successfully!"
    else
        log_info "DRY RUN completed - no files were modified"
    fi
}

# Run main function
main "$@"