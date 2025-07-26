#!/bin/bash

# Cerberus - Multi-Layer Proxy Architecture Manager
# Main CLI interface for configuration generation and service management

set -euo pipefail

# =============================================================================
# CONSTANTS AND CONFIGURATION
# =============================================================================

readonly CERBERUS_VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/lib"
readonly BUILT_DIR="${SCRIPT_DIR}/built"
readonly COMPOSE_FILE="${BUILT_DIR}/docker-compose.yaml"

# Source core libraries
source "${LIB_DIR}/core/utils.sh"
source "${LIB_DIR}/core/config.sh"

# Global configuration
CONFIG_FILE="${CERBERUS_CONFIG:-${SCRIPT_DIR}/config.toml}"
VERBOSE=false
QUIET=false
DEBUG=false

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Show version information
show_version() {
    echo "Cerberus v${CERBERUS_VERSION}"
    get_system_info
}

# Show usage information
show_usage() {
    cat << 'EOF'
Cerberus - Multi-Layer Proxy Architecture Manager

Usage: ./cerberus.sh <command> [options] [arguments]

Commands:
  Configuration Management:
    generate [--force] [--validate]     Generate all configuration files
    validate [--strict]                 Validate configuration
    clean [--all] [--confirm]           Clean built directory

  Service Management:
    up [services...] [-d] [--build]     Start services
    down [services...] [-v]             Stop services
    restart [services...] [--timeout N] Restart services
    logs [services...] [-f] [--tail N]  Show service logs
    ps [--format FORMAT] [--all]        Show service status
    build [services...] [--no-cache]    Build service images

  Scaling Management:
    scale <service>=<count>              Scale service manually
    scale auto [--enable|--disable]     Control auto-scaling
    scale status                         Show scaling status

  Setup & Templates:
    init [--template NAME] [-i]         Initialize configuration
    template list                       List templates
    template show <name>                Show template content
    template apply <name> [--force]     Apply template

  Monitoring & Debug:
    status [--detailed] [--json]        Show system status
    health [services...] [--timeout N]  Run health checks
    metrics [services...] [--interval N] Show metrics
    docs [--serve] [--port N]           Generate/serve documentation

  Testing:
    test [--integration] [pattern...]   Run tests

Global Options:
  -c, --config <file>    Configuration file (default: config.toml)
  -v, --verbose          Verbose output
  -q, --quiet            Quiet mode
  -h, --help             Show help
  --version              Show version
  --debug                Enable debug mode

Examples:
  ./cerberus.sh init --template misskey --interactive
  ./cerberus.sh generate --force --validate
  ./cerberus.sh up --detach --build
  ./cerberus.sh scale proxy=3 auto --enable
  ./cerberus.sh logs --follow --tail 100
  ./cerberus.sh status --detailed

For more help on specific commands: ./cerberus.sh help <command>
EOF
}

# Show command-specific help
show_command_help() {
    local command="$1"
    
    case "$command" in
        generate)
            cat << 'EOF'
Generate Configuration Files

Usage: ./cerberus.sh generate [options]

Generates all configuration files from config.toml:
- docker-compose.yaml
- Dockerfiles for each service
- Caddyfiles/nginx configs
- botPolicy.json for Anubis

Options:
  --force      Force overwrite existing files
  --validate   Validate configuration after generation

Examples:
  ./cerberus.sh generate
  ./cerberus.sh generate --force --validate
EOF
            ;;
        up)
            cat << 'EOF'
Start Services

Usage: ./cerberus.sh up [services...] [options]

Starts Docker Compose services. If configuration files don't exist,
they will be generated automatically.

Options:
  -d, --detach     Run in background
  --build          Force rebuild of images
  --timeout N      Timeout in seconds (default: 300)

Examples:
  ./cerberus.sh up                    # Start all services
  ./cerberus.sh up proxy anubis       # Start specific services
  ./cerberus.sh up --detach --build   # Background start with rebuild
EOF
            ;;
        scale)
            cat << 'EOF'
Service Scaling

Usage: 
  ./cerberus.sh scale <service>=<count>
  ./cerberus.sh scale auto [--enable|--disable]
  ./cerberus.sh scale status

Manual scaling sets the number of instances for a service.
Auto-scaling enables/disables automatic scaling based on metrics.

Examples:
  ./cerberus.sh scale proxy=3           # Scale proxy to 3 instances
  ./cerberus.sh scale proxy=2 anubis=1  # Scale multiple services
  ./cerberus.sh scale auto --enable     # Enable auto-scaling
  ./cerberus.sh scale status            # Show current scaling status
EOF
            ;;
        *)
            print_error "No specific help available for command: $command"
            echo "Use './cerberus.sh --help' for general help"
            ;;
    esac
}

# Parse global options
parse_global_options() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                LOG_LEVEL=$LOG_DEBUG
                shift
                ;;
            -q|--quiet)
                QUIET=true
                LOG_LEVEL=$LOG_ERROR
                shift
                ;;
            --debug)
                DEBUG=true
                CONFIG_DEBUG=true
                LOG_LEVEL=$LOG_DEBUG
                set -x
                shift
                ;;
            -h|--help)
                if [[ ${#COMMAND_ARGS[@]} -gt 0 ]]; then
                    show_command_help "${COMMAND_ARGS[0]}"
                else
                    show_usage
                fi
                exit 0
                ;;
            --version)
                show_version
                exit 0
                ;;
            -*)
                die "Unknown global option: $1"
                ;;
            *)
                # This is a command, not a global option
                COMMAND_ARGS+=("$1")
                shift
                ;;
        esac
    done
}

# =============================================================================
# CONFIGURATION MANAGEMENT COMMANDS
# =============================================================================

# Generate all configuration files
cmd_generate() {
    local force=false
    local validate=false
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force=true
                shift
                ;;
            --validate)
                validate=true
                shift
                ;;
            *)
                die "Unknown option for generate: $1"
                ;;
        esac
    done
    
    print_step "Generating configuration files..."
    
    # Load configuration
    if [[ ! -f "$CONFIG_FILE" ]]; then
        die "Configuration file not found: $CONFIG_FILE"
    fi
    
    config_load "$CONFIG_FILE"
    
    # Create built directory
    safe_mkdir "$BUILT_DIR"
    
    # Check if files exist and force is not set
    if [[ "$force" != "true" && -f "$COMPOSE_FILE" ]]; then
        print_warning "Configuration files already exist. Use --force to overwrite."
        return 1
    fi
    
    # Generate files (these functions will be implemented in generators)
    if command -v generate_docker_compose >/dev/null 2>&1; then
        generate_docker_compose
    else
        log_warn "Docker Compose generator not yet implemented"
    fi
    
    if command -v generate_dockerfiles >/dev/null 2>&1; then
        generate_dockerfiles
    else
        log_warn "Dockerfile generator not yet implemented"
    fi
    
    if command -v generate_proxy_configs >/dev/null 2>&1; then
        generate_proxy_configs
    else
        log_warn "Proxy config generator not yet implemented"
    fi
    
    print_success "Configuration files generated successfully"
    
    # Validate if requested
    if [[ "$validate" == "true" ]]; then
        cmd_validate
    fi
}

# Validate configuration
cmd_validate() {
    local strict=false
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --strict)
                strict=true
                shift
                ;;
            *)
                die "Unknown option for validate: $1"
                ;;
        esac
    done
    
    print_step "Validating configuration..."
    
    # Load and validate configuration
    config_load "$CONFIG_FILE"
    
    if config_validate; then
        print_success "Configuration validation passed"
    else
        die "Configuration validation failed"
    fi
}

# Clean built directory
cmd_clean() {
    local all=false
    local confirm=false
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --all)
                all=true
                shift
                ;;
            --confirm)
                confirm=true
                shift
                ;;
            *)
                die "Unknown option for clean: $1"
                ;;
        esac
    done
    
    # Confirmation
    if [[ "$confirm" != "true" ]]; then
        echo -n "Are you sure you want to clean the built directory? [y/N] "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Clean operation cancelled"
            return 0
        fi
    fi
    
    print_step "Cleaning built directory..."
    
    if [[ -d "$BUILT_DIR" ]]; then
        if [[ "$all" == "true" ]]; then
            safe_remove "$BUILT_DIR"
            safe_mkdir "$BUILT_DIR"
        else
            # Remove generated files but keep logs
            find "$BUILT_DIR" -name "*.yaml" -o -name "*.yml" -o -name "Dockerfile" -o -name "Caddyfile" | xargs -r rm -f
        fi
        print_success "Built directory cleaned"
    else
        print_info "Built directory doesn't exist"
    fi
}

# =============================================================================
# SERVICE MANAGEMENT COMMANDS
# =============================================================================

# Start services
cmd_up() {
    local services=()
    local detach=false
    local build=false
    local timeout=300
    
    # Parse options and services
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--detach)
                detach=true
                shift
                ;;
            --build)
                build=true
                shift
                ;;
            --timeout)
                timeout="$2"
                validate_number "$timeout" "timeout" 1
                shift 2
                ;;
            -*)
                die "Unknown option for up: $1"
                ;;
            *)
                services+=("$1")
                shift
                ;;
        esac
    done
    
    print_step "Starting services..."
    
    # Ensure configuration exists
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        print_info "Docker Compose file not found, generating configuration..."
        cmd_generate
    fi
    
    # Check Docker
    check_docker
    check_docker_compose
    
    # Build Docker Compose command
    local compose_args=("up")
    
    if [[ "$detach" == "true" ]]; then
        compose_args+=("--detach")
    fi
    
    if [[ "$build" == "true" ]]; then
        compose_args+=("--build")
    fi
    
    compose_args+=("--timeout" "$timeout")
    
    # Add specific services if provided
    if [[ ${#services[@]} -gt 0 ]]; then
        compose_args+=("${services[@]}")
    fi
    
    # Run Docker Compose
    run_docker_compose "$COMPOSE_FILE" "${compose_args[@]}"
    
    print_success "Services started successfully"
    
    # Show status if not detached
    if [[ "$detach" != "true" ]]; then
        echo
        cmd_ps
    fi
}

# Stop services
cmd_down() {
    local services=()
    local volumes=false
    local remove_orphans=false
    
    # Parse options and services
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--volumes)
                volumes=true
                shift
                ;;
            --remove-orphans)
                remove_orphans=true
                shift
                ;;
            -*)
                die "Unknown option for down: $1"
                ;;
            *)
                services+=("$1")
                shift
                ;;
        esac
    done
    
    print_step "Stopping services..."
    
    # Check if compose file exists
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        print_warning "Docker Compose file not found"
        return 0
    fi
    
    # Build Docker Compose command
    local compose_args=("down")
    
    if [[ "$volumes" == "true" ]]; then
        compose_args+=("--volumes")
    fi
    
    if [[ "$remove_orphans" == "true" ]]; then
        compose_args+=("--remove-orphans")
    fi
    
    # Add specific services if provided
    if [[ ${#services[@]} -gt 0 ]]; then
        # For specific services, use stop instead of down
        compose_args=("stop" "${services[@]}")
    fi
    
    # Run Docker Compose
    run_docker_compose "$COMPOSE_FILE" "${compose_args[@]}"
    
    print_success "Services stopped successfully"
}

# Show service status
cmd_ps() {
    local format="table"
    local all=false
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --format)
                format="$2"
                shift 2
                ;;
            -a|--all)
                all=true
                shift
                ;;
            *)
                die "Unknown option for ps: $1"
                ;;
        esac
    done
    
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        print_warning "Docker Compose file not found"
        return 0
    fi
    
    local compose_args=("ps")
    
    if [[ "$all" == "true" ]]; then
        compose_args+=("--all")
    fi
    
    case "$format" in
        table)
            run_docker_compose "$COMPOSE_FILE" "${compose_args[@]}"
            ;;
        json)
            run_docker_compose "$COMPOSE_FILE" "${compose_args[@]}" --format json
            ;;
        *)
            run_docker_compose "$COMPOSE_FILE" "${compose_args[@]}"
            ;;
    esac
}

# Show service logs
cmd_logs() {
    local services=()
    local follow=false
    local tail=""
    local since=""
    
    # Parse options and services
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--follow)
                follow=true
                shift
                ;;
            --tail)
                tail="$2"
                validate_number "$tail" "tail" 1
                shift 2
                ;;
            --since)
                since="$2"
                shift 2
                ;;
            -*)
                die "Unknown option for logs: $1"
                ;;
            *)
                services+=("$1")
                shift
                ;;
        esac
    done
    
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        print_warning "Docker Compose file not found"
        return 0
    fi
    
    # Build Docker Compose command
    local compose_args=("logs")
    
    if [[ "$follow" == "true" ]]; then
        compose_args+=("--follow")
    fi
    
    if [[ -n "$tail" ]]; then
        compose_args+=("--tail" "$tail")
    fi
    
    if [[ -n "$since" ]]; then
        compose_args+=("--since" "$since")
    fi
    
    # Add specific services if provided
    if [[ ${#services[@]} -gt 0 ]]; then
        compose_args+=("${services[@]}")
    fi
    
    # Run Docker Compose
    run_docker_compose "$COMPOSE_FILE" "${compose_args[@]}"
}

# =============================================================================
# SCALING MANAGEMENT COMMANDS
# =============================================================================

# Handle scaling commands
cmd_scale() {
    if [[ $# -eq 0 ]]; then
        die "Scale command requires arguments. Use 'scale status' or 'scale <service>=<count>'"
    fi
    
    local subcommand="$1"
    shift
    
    case "$subcommand" in
        auto)
            cmd_scale_auto "$@"
            ;;
        status)
            cmd_scale_status "$@"
            ;;
        *=*)
            cmd_scale_manual "$subcommand" "$@"
            ;;
        *)
            die "Unknown scale subcommand: $subcommand"
            ;;
    esac
}

# Manual scaling
cmd_scale_manual() {
    local scale_specs=("$@")
    
    if [[ ${#scale_specs[@]} -eq 0 ]]; then
        die "No scaling specifications provided"
    fi
    
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        die "Docker Compose file not found. Run 'generate' first."
    fi
    
    print_step "Scaling services..."
    
    # Parse scaling specifications (service=count)
    local compose_args=("up" "--detach" "--scale")
    
    for spec in "${scale_specs[@]}"; do
        if [[ ! "$spec" =~ ^([a-zA-Z0-9_-]+)=([0-9]+)$ ]]; then
            die "Invalid scale specification: $spec (expected format: service=count)"
        fi
        
        local service="${BASH_REMATCH[1]}"
        local count="${BASH_REMATCH[2]}"
        
        compose_args+=("${service}=${count}")
        log_info "Scaling $service to $count instances"
    done
    
    # Run Docker Compose
    run_docker_compose "$COMPOSE_FILE" "${compose_args[@]}"
    
    print_success "Services scaled successfully"
}

# Auto-scaling management
cmd_scale_auto() {
    local action=""
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --enable)
                action="enable"
                shift
                ;;
            --disable)
                action="disable"
                shift
                ;;
            *)
                die "Unknown option for scale auto: $1"
                ;;
        esac
    done
    
    if [[ -z "$action" ]]; then
        die "Auto-scaling requires --enable or --disable"
    fi
    
    case "$action" in
        enable)
            print_step "Enabling auto-scaling..."
            # TODO: Implement auto-scaling enablement
            print_warning "Auto-scaling is not yet implemented"
            ;;
        disable)
            print_step "Disabling auto-scaling..."
            # TODO: Implement auto-scaling disablement
            print_warning "Auto-scaling is not yet implemented"
            ;;
    esac
}

# Show scaling status
cmd_scale_status() {
    print_step "Scaling Status"
    echo "=============="
    
    if [[ -f "$COMPOSE_FILE" ]]; then
        cmd_ps --format table
    else
        print_warning "Docker Compose file not found"
    fi
    
    echo
    print_info "Auto-scaling: Not yet implemented"
}

# =============================================================================
# MONITORING COMMANDS
# =============================================================================

# Show system status
cmd_status() {
    local detailed=false
    local json=false
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --detailed)
                detailed=true
                shift
                ;;
            --json)
                json=true
                shift
                ;;
            *)
                die "Unknown option for status: $1"
                ;;
        esac
    done
    
    if [[ "$json" == "true" ]]; then
        # TODO: Implement JSON output
        print_warning "JSON output not yet implemented"
        return 0
    fi
    
    print_step "Cerberus System Status"
    echo "======================"
    echo
    
    # Configuration status
    echo "Configuration:"
    if [[ -f "$CONFIG_FILE" ]]; then
        print_success "Config file: $CONFIG_FILE"
        
        if config_is_loaded || config_load "$CONFIG_FILE" 2>/dev/null; then
            local project_name
            project_name=$(config_get_string "project.name" "unknown")
            echo "  Project: $project_name"
            
            local proxy_count
            proxy_count=$(config_get_array_table_count "proxies")
            echo "  Proxies: $proxy_count configured"
            
            local service_count
            service_count=$(config_get_array_table_count "services")
            echo "  Services: $service_count configured"
        fi
    else
        print_error "Config file not found: $CONFIG_FILE"
    fi
    
    echo
    
    # Generated files status
    echo "Generated Files:"
    if [[ -f "$COMPOSE_FILE" ]]; then
        print_success "Docker Compose: $(basename "$COMPOSE_FILE")"
    else
        print_warning "Docker Compose file not generated"
    fi
    
    echo
    
    # Service status
    echo "Services:"
    if [[ -f "$COMPOSE_FILE" ]]; then
        cmd_ps 2>/dev/null || print_warning "Could not get service status"
    else
        print_warning "No services configured"
    fi
    
    if [[ "$detailed" == "true" ]]; then
        echo
        echo "System Information:"
        get_system_info
    fi
}

# =============================================================================
# INITIALIZATION AND TEMPLATE COMMANDS
# =============================================================================

# Initialize configuration
cmd_init() {
    local template=""
    local interactive=false
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --template)
                template="$2"
                shift 2
                ;;
            -i|--interactive)
                interactive=true
                shift
                ;;
            *)
                die "Unknown option for init: $1"
                ;;
        esac
    done
    
    # Check if config file already exists
    if [[ -f "$CONFIG_FILE" ]]; then
        echo -n "Configuration file already exists. Overwrite? [y/N] "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Initialization cancelled"
            return 0
        fi
    fi
    
    print_step "Initializing Cerberus configuration..."
    
    if [[ -n "$template" ]]; then
        # Use template
        local template_file="${SCRIPT_DIR}/templates/configs/${template}.toml"
        if [[ -f "$template_file" ]]; then
            safe_copy "$template_file" "$CONFIG_FILE" false
            print_success "Configuration initialized from template: $template"
        else
            print_error "Template not found: $template"
            print_info "Available templates:"
            cmd_template_list
            return 1
        fi
    elif [[ "$interactive" == "true" ]]; then
        # Interactive setup
        print_info "Starting interactive configuration setup..."
        # TODO: Implement interactive setup
        print_warning "Interactive setup not yet implemented"
        
        # For now, copy example config
        if [[ -f "${SCRIPT_DIR}/config-example.toml" ]]; then
            safe_copy "${SCRIPT_DIR}/config-example.toml" "$CONFIG_FILE" false
            print_success "Configuration initialized from example"
        else
            die "Example configuration not found"
        fi
    else
        # Use example config
        if [[ -f "${SCRIPT_DIR}/config-example.toml" ]]; then
            safe_copy "${SCRIPT_DIR}/config-example.toml" "$CONFIG_FILE" false
            print_success "Configuration initialized from example"
        else
            die "Example configuration not found"
        fi
    fi
    
    print_info "Edit $CONFIG_FILE to customize your configuration"
    print_info "Then run: ./cerberus.sh generate"
}

# Template management
cmd_template() {
    if [[ $# -eq 0 ]]; then
        die "Template command requires a subcommand: list, show, apply"
    fi
    
    local subcommand="$1"
    shift
    
    case "$subcommand" in
        list)
            cmd_template_list "$@"
            ;;
        show)
            cmd_template_show "$@"
            ;;
        apply)
            cmd_template_apply "$@"
            ;;
        *)
            die "Unknown template subcommand: $subcommand"
            ;;
    esac
}

# List available templates
cmd_template_list() {
    local template_dir="${SCRIPT_DIR}/templates/configs"
    
    print_step "Available Configuration Templates"
    echo "================================="
    
    if [[ -d "$template_dir" ]]; then
        local found=false
        for template in "$template_dir"/*.toml; do
            if [[ -f "$template" ]]; then
                local name
                name=$(basename "$template" .toml)
                echo "  $name"
                found=true
            fi
        done
        
        if [[ "$found" != "true" ]]; then
            print_warning "No templates found in $template_dir"
        fi
    else
        print_warning "Template directory not found: $template_dir"
    fi
}

# Show template content
cmd_template_show() {
    local template_name="$1"
    
    if [[ -z "$template_name" ]]; then
        die "Template name required"
    fi
    
    local template_file="${SCRIPT_DIR}/templates/configs/${template_name}.toml"
    
    if [[ -f "$template_file" ]]; then
        print_step "Template: $template_name"
        echo "==================="
        cat "$template_file"
    else
        die "Template not found: $template_name"
    fi
}

# Apply template
cmd_template_apply() {
    local template_name="$1"
    local force=false
    
    if [[ -z "$template_name" ]]; then
        die "Template name required"
    fi
    
    # Parse remaining options
    shift
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force=true
                shift
                ;;
            *)
                die "Unknown option for template apply: $1"
                ;;
        esac
    done
    
    local template_file="${SCRIPT_DIR}/templates/configs/${template_name}.toml"
    
    if [[ ! -f "$template_file" ]]; then
        die "Template not found: $template_name"
    fi
    
    if [[ -f "$CONFIG_FILE" && "$force" != "true" ]]; then
        print_warning "Configuration file already exists. Use --force to overwrite."
        return 1
    fi
    
    safe_copy "$template_file" "$CONFIG_FILE" true
    print_success "Template '$template_name' applied to $CONFIG_FILE"
}

# =============================================================================
# MAIN COMMAND DISPATCHER
# =============================================================================

# Main function
main() {
    # Global command arguments array
    declare -ga COMMAND_ARGS=()
    
    # Parse global options and extract command
    parse_global_options "$@"
    
    # Check if we have a command
    if [[ ${#COMMAND_ARGS[@]} -eq 0 ]]; then
        show_usage
        exit 1
    fi
    
    local command="${COMMAND_ARGS[0]}"
    local -a command_args=("${COMMAND_ARGS[@]:1}")
    
    # Dispatch to command function
    case "$command" in
        # Configuration Management
        generate)
            cmd_generate "${command_args[@]}"
            ;;
        validate)
            cmd_validate "${command_args[@]}"
            ;;
        clean)
            cmd_clean "${command_args[@]}"
            ;;
            
        # Service Management
        up)
            cmd_up "${command_args[@]}"
            ;;
        down)
            cmd_down "${command_args[@]}"
            ;;
        restart)
            # Restart is just down + up
            cmd_down "${command_args[@]}"
            sleep 2
            cmd_up "${command_args[@]}"
            ;;
        logs)
            cmd_logs "${command_args[@]}"
            ;;
        ps)
            cmd_ps "${command_args[@]}"
            ;;
        build)
            if [[ ! -f "$COMPOSE_FILE" ]]; then
                die "Docker Compose file not found. Run 'generate' first."
            fi
            run_docker_compose "$COMPOSE_FILE" build "${command_args[@]}"
            ;;
            
        # Scaling Management
        scale)
            cmd_scale "${command_args[@]}"
            ;;
            
        # Setup & Templates
        init)
            cmd_init "${command_args[@]}"
            ;;
        template)
            cmd_template "${command_args[@]}"
            ;;
            
        # Monitoring & Debug
        status)
            cmd_status "${command_args[@]}"
            ;;
        health)
            # TODO: Implement health check
            print_warning "Health check not yet implemented"
            ;;
        metrics)
            # TODO: Implement metrics display
            print_warning "Metrics display not yet implemented"
            ;;
        docs)
            # TODO: Implement documentation generation
            print_warning "Documentation generation not yet implemented"
            ;;
            
        # Testing
        test)
            # TODO: Implement test runner
            print_warning "Test runner not yet implemented"
            ;;
            
        # Help
        help)
            if [[ ${#command_args[@]} -gt 0 ]]; then
                show_command_help "${command_args[0]}"
            else
                show_usage
            fi
            ;;
            
        *)
            die "Unknown command: $command"
            ;;
    esac
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Initialize and run
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Ensure we have a clean environment
    init_utils
    
    # Run main function with all arguments
    main "$@"
fi