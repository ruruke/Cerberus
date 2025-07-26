#!/bin/bash

# Cerberus Utils Library
# Common functions and utilities used throughout the system

set -euo pipefail

# =============================================================================
# CONSTANTS AND CONFIGURATION
# =============================================================================

if [[ -z "${SCRIPT_DIR:-}" ]]; then
    readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
if [[ -z "${CONFIG_FILE:-}" ]]; then
    readonly CONFIG_FILE="${SCRIPT_DIR}/config.toml"
fi
if [[ -z "${BUILT_DIR:-}" ]]; then
    readonly BUILT_DIR="${SCRIPT_DIR}/built"
fi
if [[ -z "${LIB_DIR:-}" ]]; then
    readonly LIB_DIR="${SCRIPT_DIR}/lib"
fi

# Colors for output
if [[ -z "${RED:-}" ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly PURPLE='\033[0;35m'
    readonly CYAN='\033[0;36m'
    readonly WHITE='\033[1;37m'
    readonly NC='\033[0m' # No Color
fi

# Log levels
if [[ -z "${LOG_DEBUG:-}" ]]; then
    readonly LOG_DEBUG=0
    readonly LOG_INFO=1
    readonly LOG_WARN=2
    readonly LOG_ERROR=3
fi

# Global log level (can be overridden)
LOG_LEVEL=${LOG_LEVEL:-$LOG_INFO}

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

# Print log message with timestamp and level
# Usage: log_message <level> <message>
log_message() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ $level -ge $LOG_LEVEL ]]; then
        case $level in
            $LOG_DEBUG)
                echo -e "${CYAN}[DEBUG]${NC} ${timestamp} $message" >&2
                ;;
            $LOG_INFO)
                echo -e "${BLUE}[INFO]${NC} ${timestamp} $message" >&2
                ;;
            $LOG_WARN)
                echo -e "${YELLOW}[WARN]${NC} ${timestamp} $message" >&2
                ;;
            $LOG_ERROR)
                echo -e "${RED}[ERROR]${NC} ${timestamp} $message" >&2
                ;;
        esac
    fi
}

# Convenience logging functions
log_debug() { log_message $LOG_DEBUG "$*"; }
log_info() { log_message $LOG_INFO "$*"; }
log_warn() { log_message $LOG_WARN "$*"; }
log_error() { log_message $LOG_ERROR "$*"; }

# Print colored output without timestamp (for user-facing messages)
print_success() { echo -e "${GREEN}✓${NC} $*"; }
print_info() { echo -e "${BLUE}ℹ${NC} $*"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $*"; }
print_error() { echo -e "${RED}✗${NC} $*"; }
print_step() { echo -e "${PURPLE}→${NC} $*"; }

# =============================================================================
# ERROR HANDLING
# =============================================================================

# Exit with error message
die() {
    log_error "$*"
    print_error "$*"
    exit 1
}

# Check if command exists
require_command() {
    local cmd="$1"
    local install_hint="${2:-}"
    
    if ! command -v "$cmd" >/dev/null 2>&1; then
        if [[ -n "$install_hint" ]]; then
            die "Required command '$cmd' not found. Install with: $install_hint"
        else
            die "Required command '$cmd' not found. Please install it."
        fi
    fi
}

# Check if file exists and is readable
require_file() {
    local file="$1"
    local description="${2:-file}"
    
    if [[ ! -f "$file" ]]; then
        die "Required $description not found: $file"
    fi
    
    if [[ ! -r "$file" ]]; then
        die "Required $description is not readable: $file"
    fi
}

# Check if directory exists and is writable
require_directory() {
    local dir="$1"
    local description="${2:-directory}"
    
    if [[ ! -d "$dir" ]]; then
        log_info "Creating $description: $dir"
        mkdir -p "$dir" || die "Failed to create $description: $dir"
    fi
    
    if [[ ! -w "$dir" ]]; then
        die "Required $description is not writable: $dir"
    fi
}

# Validate input parameters
validate_not_empty() {
    local value="$1"
    local name="$2"
    
    if [[ -z "$value" ]]; then
        die "Parameter '$name' cannot be empty"
    fi
}

# Validate numeric input
validate_number() {
    local value="$1"
    local name="$2"
    local min="${3:-}"
    local max="${4:-}"
    
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        die "Parameter '$name' must be a number, got: $value"
    fi
    
    if [[ -n "$min" && "$value" -lt "$min" ]]; then
        die "Parameter '$name' must be at least $min, got: $value"
    fi
    
    if [[ -n "$max" && "$value" -gt "$max" ]]; then
        die "Parameter '$name' must be at most $max, got: $value"
    fi
}

# =============================================================================
# FILE AND DIRECTORY UTILITIES
# =============================================================================

# Safely create directory with logging
safe_mkdir() {
    local dir="$1"
    local mode="${2:-755}"
    
    if [[ ! -d "$dir" ]]; then
        log_debug "Creating directory: $dir"
        mkdir -p "$dir" || die "Failed to create directory: $dir"
        chmod "$mode" "$dir" || die "Failed to set permissions on directory: $dir"
    fi
}

# Safely remove file or directory
safe_remove() {
    local path="$1"
    
    if [[ -e "$path" ]]; then
        log_debug "Removing: $path"
        rm -rf "$path" || die "Failed to remove: $path"
    fi
}

# Copy file with backup
safe_copy() {
    local src="$1"
    local dest="$2"
    local backup="${3:-true}"
    
    require_file "$src" "source file"
    
    if [[ "$backup" == "true" && -f "$dest" ]]; then
        local backup_file="${dest}.backup.$(date +%s)"
        log_debug "Backing up existing file: $dest -> $backup_file"
        cp "$dest" "$backup_file" || die "Failed to create backup: $backup_file"
    fi
    
    log_debug "Copying: $src -> $dest"
    cp "$src" "$dest" || die "Failed to copy: $src -> $dest"
}

# Get file modification time
get_file_mtime() {
    local file="$1"
    
    if [[ -f "$file" ]]; then
        case "$(uname -s)" in
            Darwin)
                stat -f %m "$file"
                ;;
            Linux)
                stat -c %Y "$file"
                ;;
            *)
                log_warn "Unknown system, using fallback for file time"
                echo 0
                ;;
        esac
    else
        echo 0
    fi
}

# Check if file is newer than another
is_file_newer() {
    local file1="$1"
    local file2="$2"
    
    local mtime1
    local mtime2
    mtime1=$(get_file_mtime "$file1")
    mtime2=$(get_file_mtime "$file2")
    
    [[ "$mtime1" -gt "$mtime2" ]]
}

# =============================================================================
# STRING UTILITIES
# =============================================================================

# Trim whitespace from string
trim() {
    local var="$1"
    # Remove leading whitespace
    var="${var#"${var%%[![:space:]]*}"}"
    # Remove trailing whitespace
    var="${var%"${var##*[![:space:]]}"}"
    echo "$var"
}

# Convert string to lowercase
to_lower() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

# Convert string to uppercase
to_upper() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

# Check if string contains substring
contains() {
    local string="$1"
    local substring="$2"
    [[ "$string" == *"$substring"* ]]
}

# Join array elements with delimiter
join_array() {
    local delimiter="$1"
    shift
    local first="$1"
    shift
    printf '%s' "$first" "${@/#/$delimiter}"
}

# Generate random string
random_string() {
    local length="${1:-16}"
    local charset="${2:-a-zA-Z0-9}"
    
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 32 | tr -d "=+/" | cut -c1-"$length"
    else
        cat /dev/urandom | tr -dc "$charset" | fold -w "$length" | head -n 1
    fi
}

# =============================================================================
# DOCKER UTILITIES
# =============================================================================

# Check if Docker is running
check_docker() {
    require_command "docker" "curl -fsSL https://get.docker.com | sh"
    
    if ! docker info >/dev/null 2>&1; then
        die "Docker is not running. Please start Docker daemon."
    fi
}

# Check if Docker Compose is available
check_docker_compose() {
    if command -v docker-compose >/dev/null 2>&1; then
        return 0
    elif docker compose version >/dev/null 2>&1; then
        return 0
    else
        die "Docker Compose not found. Please install docker-compose or use Docker with compose plugin."
    fi
}

# Get Docker Compose command
get_docker_compose_cmd() {
    if command -v docker-compose >/dev/null 2>&1; then
        echo "docker-compose"
    else
        echo "docker compose"
    fi
}

# Run Docker Compose command with proper error handling
run_docker_compose() {
    local compose_file="$1"
    shift
    local cmd
    cmd=$(get_docker_compose_cmd)
    
    require_file "$compose_file" "docker-compose file"
    
    log_debug "Running: $cmd -f $compose_file $*"
    $cmd -f "$compose_file" "$@" || die "Docker Compose command failed: $*"
}

# Check if Docker service is running
is_service_running() {
    local compose_file="$1"
    local service="$2"
    local cmd
    cmd=$(get_docker_compose_cmd)
    
    $cmd -f "$compose_file" ps -q "$service" 2>/dev/null | grep -q .
}

# =============================================================================
# SYSTEM UTILITIES
# =============================================================================

# Get system information
get_system_info() {
    echo "System: $(uname -s)"
    echo "Architecture: $(uname -m)"
    echo "Kernel: $(uname -r)"
    
    if command -v docker >/dev/null 2>&1; then
        echo "Docker: $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'Not available')"
    fi
    
    local compose_cmd
    compose_cmd=$(get_docker_compose_cmd 2>/dev/null || echo "")
    if [[ -n "$compose_cmd" ]]; then
        echo "Docker Compose: $($compose_cmd version --short 2>/dev/null || echo 'Not available')"
    fi
}

# Check if running as root
is_root() {
    [[ $EUID -eq 0 ]]
}

# Get current user
get_current_user() {
    if [[ -n "${SUDO_USER:-}" ]]; then
        echo "$SUDO_USER"
    else
        whoami
    fi
}

# =============================================================================
# NETWORK UTILITIES
# =============================================================================

# Check if port is available
is_port_available() {
    local port="$1"
    ! netstat -tuln 2>/dev/null | grep -q ":$port "
}

# Wait for service to be ready
wait_for_service() {
    local host="$1"
    local port="$2"
    local timeout="${3:-30}"
    local interval="${4:-1}"
    
    log_info "Waiting for $host:$port to be ready (timeout: ${timeout}s)"
    
    local count=0
    while [[ $count -lt $timeout ]]; do
        if timeout 1 bash -c "cat < /dev/null > /dev/tcp/$host/$port" 2>/dev/null; then
            log_info "Service $host:$port is ready"
            return 0
        fi
        sleep "$interval"
        ((count += interval))
    done
    
    die "Service $host:$port failed to become ready within ${timeout}s"
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize utilities library
init_utils() {
    log_debug "Initializing utils library"
    
    # Ensure required directories exist
    safe_mkdir "$BUILT_DIR"
    safe_mkdir "${BUILT_DIR}/dockerfiles"
    safe_mkdir "${BUILT_DIR}/anubis" 
    safe_mkdir "${BUILT_DIR}/configs"
    
    # Create test directories if they don't exist
    if [[ -n "${SCRIPT_DIR:-}" ]]; then
        safe_mkdir "${SCRIPT_DIR}/tests/tmp"
    fi
    
    # Check basic requirements
    require_command "bash"
    require_command "date"
    require_command "mkdir"
    require_command "chmod"
    
    log_debug "Utils library initialized successfully"
}

# Initialize if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    init_utils
fi