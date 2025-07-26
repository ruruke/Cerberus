#!/bin/bash

# Cerberus Auto-Scaler
# Automatic scaling based on metrics (CPU, memory, connections)

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

readonly SCALER_DIR="${BUILT_DIR}/scaling"
readonly METRICS_DIR="${SCALER_DIR}/metrics"
readonly COOLDOWN_DIR="${SCALER_DIR}/cooldown"

# Default thresholds
readonly DEFAULT_CPU_THRESHOLD=80
readonly DEFAULT_MEMORY_THRESHOLD=85
readonly DEFAULT_CONNECTIONS_THRESHOLD=1500
readonly DEFAULT_RESPONSE_TIME_THRESHOLD=2000
readonly DEFAULT_CHECK_INTERVAL="30s"
readonly DEFAULT_SCALE_UP_COOLDOWN="5m"
readonly DEFAULT_SCALE_DOWN_COOLDOWN="10m"

# =============================================================================
# METRICS COLLECTION
# =============================================================================

# Get container CPU usage percentage
get_container_cpu_usage() {
    local container_name="$1"
    
    if ! docker stats --no-stream --format "table {{.CPUPerc}}" "$container_name" 2>/dev/null | tail -n1 | tr -d '%'; then
        echo "0"
    fi
}

# Get container memory usage percentage
get_container_memory_usage() {
    local container_name="$1"
    
    if ! docker stats --no-stream --format "table {{.MemPerc}}" "$container_name" 2>/dev/null | tail -n1 | tr -d '%'; then
        echo "0"
    fi
}

# Get HAProxy connection count
get_haproxy_connections() {
    local container_name="$1"
    local stats_url="http://localhost:8404/stats"
    
    # Try to get HAProxy stats
    if docker exec "$container_name" wget -qO- "$stats_url" 2>/dev/null | grep -o 'scur">[0-9]*' | head -1 | cut -d'>' -f2; then
        return 0
    else
        echo "0"
    fi
}

# Get Nginx active connections
get_nginx_connections() {
    local container_name="$1"
    local status_url="http://localhost/nginx_status"
    
    # Try to get Nginx status
    if docker exec "$container_name" wget -qO- "$status_url" 2>/dev/null | grep "Active connections" | awk '{print $3}'; then
        return 0
    else
        echo "0"
    fi
}

# Get service response time (milliseconds)
get_response_time() {
    local service_url="$1"
    
    # Use curl to measure response time
    if curl -w "%{time_total}" -s -o /dev/null "$service_url" 2>/dev/null | awk '{print int($1*1000)}'; then
        return 0
    else
        echo "999999"  # Return high value if can't connect
    fi
}

# Collect all metrics for a service
collect_service_metrics() {
    local service_name="$1"
    local service_type="$2"
    
    local cpu_usage memory_usage connections response_time
    
    cpu_usage=$(get_container_cpu_usage "$service_name")
    memory_usage=$(get_container_memory_usage "$service_name")
    
    case "$service_type" in
        haproxy)
            connections=$(get_haproxy_connections "$service_name")
            ;;
        nginx)
            connections=$(get_nginx_connections "$service_name")
            ;;
        *)
            connections="0"
            ;;
    esac
    
    # Get response time from first available port
    local service_port
    service_port=$(docker port "$service_name" 2>/dev/null | head -1 | cut -d':' -f2 || echo "80")
    response_time=$(get_response_time "http://localhost:${service_port}")
    
    # Store metrics
    local metrics_file="${METRICS_DIR}/${service_name}.json"
    safe_mkdir "${METRICS_DIR}"
    
    cat > "$metrics_file" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "service": "$service_name",
  "type": "$service_type",
  "metrics": {
    "cpu_usage": ${cpu_usage},
    "memory_usage": ${memory_usage},
    "connections": ${connections},
    "response_time": ${response_time}
  }
}
EOF
    
    log_debug "Collected metrics for $service_name: CPU=${cpu_usage}%, MEM=${memory_usage}%, CONN=${connections}, RT=${response_time}ms"
}

# =============================================================================
# SCALING DECISIONS
# =============================================================================

# Check if scaling is needed for a service
check_scaling_needed() {
    local service_name="$1"
    local metrics_file="${METRICS_DIR}/${service_name}.json"
    
    if [[ ! -f "$metrics_file" ]]; then
        log_warn "No metrics found for $service_name"
        return 1
    fi
    
    # Get current metrics
    local cpu_usage memory_usage connections response_time
    cpu_usage=$(jq -r '.metrics.cpu_usage' "$metrics_file" 2>/dev/null || echo "0")
    memory_usage=$(jq -r '.metrics.memory_usage' "$metrics_file" 2>/dev/null || echo "0")
    connections=$(jq -r '.metrics.connections' "$metrics_file" 2>/dev/null || echo "0")
    response_time=$(jq -r '.metrics.response_time' "$metrics_file" 2>/dev/null || echo "0")
    
    # Get thresholds from config
    local cpu_threshold memory_threshold connections_threshold response_time_threshold
    cpu_threshold=$(config_get_int "scaling.metrics.cpu_threshold" $DEFAULT_CPU_THRESHOLD)
    memory_threshold=$(config_get_int "scaling.metrics.memory_threshold" $DEFAULT_MEMORY_THRESHOLD)
    connections_threshold=$(config_get_int "scaling.metrics.connections_threshold" $DEFAULT_CONNECTIONS_THRESHOLD)
    response_time_threshold=$(config_get_int "scaling.metrics.response_time_threshold" $DEFAULT_RESPONSE_TIME_THRESHOLD)
    
    # Check if any metric exceeds threshold
    local scale_needed=false
    local reasons=()
    
    if (( $(echo "$cpu_usage > $cpu_threshold" | bc -l 2>/dev/null || echo "0") )); then
        scale_needed=true
        reasons+=("CPU: ${cpu_usage}% > ${cpu_threshold}%")
    fi
    
    if (( $(echo "$memory_usage > $memory_threshold" | bc -l 2>/dev/null || echo "0") )); then
        scale_needed=true
        reasons+=("Memory: ${memory_usage}% > ${memory_threshold}%")
    fi
    
    if (( connections > connections_threshold )); then
        scale_needed=true
        reasons+=("Connections: $connections > $connections_threshold")
    fi
    
    if (( response_time > response_time_threshold )); then
        scale_needed=true
        reasons+=("Response Time: ${response_time}ms > ${response_time_threshold}ms")
    fi
    
    if [[ "$scale_needed" == "true" ]]; then
        log_info "Scaling needed for $service_name: ${reasons[*]}"
        return 0
    else
        log_debug "No scaling needed for $service_name"
        return 1
    fi
}

# Check cooldown period
check_cooldown() {
    local service_name="$1"
    local action="$2"  # "up" or "down"
    
    local cooldown_file="${COOLDOWN_DIR}/${service_name}_${action}"
    local cooldown_duration
    
    if [[ "$action" == "up" ]]; then
        cooldown_duration=$(config_get_string "scaling.rules.scale_up_cooldown" "$DEFAULT_SCALE_UP_COOLDOWN")
    else
        cooldown_duration=$(config_get_string "scaling.rules.scale_down_cooldown" "$DEFAULT_SCALE_DOWN_COOLDOWN")
    fi
    
    if [[ -f "$cooldown_file" ]]; then
        local last_scale_time
        last_scale_time=$(cat "$cooldown_file" 2>/dev/null || echo "0")
        local current_time
        current_time=$(date +%s)
        local cooldown_seconds
        
        # Convert cooldown duration to seconds
        if [[ "$cooldown_duration" =~ ^([0-9]+)m$ ]]; then
            cooldown_seconds=$((${BASH_REMATCH[1]} * 60))
        elif [[ "$cooldown_duration" =~ ^([0-9]+)s$ ]]; then
            cooldown_seconds=${BASH_REMATCH[1]}
        else
            cooldown_seconds=300  # Default 5 minutes
        fi
        
        if (( current_time - last_scale_time < cooldown_seconds )); then
            log_debug "Cooldown active for $service_name $action: $((cooldown_seconds - (current_time - last_scale_time)))s remaining"
            return 1
        fi
    fi
    
    return 0
}

# Set cooldown marker
set_cooldown() {
    local service_name="$1"
    local action="$2"
    
    safe_mkdir "$COOLDOWN_DIR"
    echo "$(date +%s)" > "${COOLDOWN_DIR}/${service_name}_${action}"
}

# =============================================================================
# SCALING ACTIONS
# =============================================================================

# Get current scale of a service
get_current_scale() {
    local service_name="$1"
    
    # Count running containers with the service name
    docker ps --filter "name=${service_name}" --format "{{.Names}}" 2>/dev/null | wc -l
}

# Scale up a service
scale_up_service() {
    local service_name="$1"
    local current_scale new_scale
    
    current_scale=$(get_current_scale "$service_name")
    new_scale=$((current_scale + 1))
    
    # Get max instances from config
    local max_instances
    max_instances=$(config_get_int "scaling.rules.max_instances" 10)
    
    if (( new_scale > max_instances )); then
        log_warn "Cannot scale $service_name beyond max instances ($max_instances)"
        return 1
    fi
    
    log_info "Scaling up $service_name from $current_scale to $new_scale instances"
    
    # Use docker-compose to scale
    if docker-compose -f "${BUILT_DIR}/docker-compose.yaml" up -d --scale "${service_name}=${new_scale}" 2>/dev/null; then
        log_info "Successfully scaled up $service_name to $new_scale instances"
        set_cooldown "$service_name" "up"
        return 0
    else
        log_error "Failed to scale up $service_name"
        return 1
    fi
}

# Scale down a service
scale_down_service() {
    local service_name="$1"
    local current_scale new_scale
    
    current_scale=$(get_current_scale "$service_name")
    new_scale=$((current_scale - 1))
    
    # Get min instances from config
    local min_instances
    min_instances=$(config_get_int "scaling.rules.min_instances" 1)
    
    if (( new_scale < min_instances )); then
        log_debug "Cannot scale $service_name below min instances ($min_instances)"
        return 1
    fi
    
    log_info "Scaling down $service_name from $current_scale to $new_scale instances"
    
    # Use docker-compose to scale
    if docker-compose -f "${BUILT_DIR}/docker-compose.yaml" up -d --scale "${service_name}=${new_scale}" 2>/dev/null; then
        log_info "Successfully scaled down $service_name to $new_scale instances"
        set_cooldown "$service_name" "down"
        return 0
    else
        log_error "Failed to scale down $service_name"
        return 1
    fi
}

# =============================================================================
# MAIN SCALING LOOP
# =============================================================================

# Run scaling check for all services
run_scaling_check() {
    require_config_loaded
    
    if [[ "$(config_get_bool "scaling.enabled")" != "true" ]]; then
        log_debug "Auto-scaling is disabled"
        return 0
    fi
    
    log_info "Running auto-scaling check..."
    
    # Get all proxy services
    local proxy_count
    proxy_count=$(config_get_array_table_count "proxies")
    
    for ((i=0; i<proxy_count; i++)); do
        local name type
        name=$(config_get_string "proxies.${i}.name")
        type=$(config_get_string "proxies.${i}.type")
        
        log_debug "Checking scaling for $name ($type)"
        
        # Collect metrics
        collect_service_metrics "$name" "$type"
        
        # Check if scaling is needed
        if check_scaling_needed "$name"; then
            # Check cooldown before scaling up
            if check_cooldown "$name" "up"; then
                scale_up_service "$name"
            fi
        else
            # Consider scaling down if metrics are consistently low
            # This is a simplified check - in production you'd want more sophisticated logic
            local current_scale
            current_scale=$(get_current_scale "$name")
            
            if (( current_scale > 1 )) && check_cooldown "$name" "down"; then
                # Simple scale down logic: if metrics are less than 50% of thresholds
                local cpu_usage memory_usage
                cpu_usage=$(jq -r '.metrics.cpu_usage' "${METRICS_DIR}/${name}.json" 2>/dev/null || echo "100")
                memory_usage=$(jq -r '.metrics.memory_usage' "${METRICS_DIR}/${name}.json" 2>/dev/null || echo "100")
                
                local cpu_threshold memory_threshold
                cpu_threshold=$(config_get_int "scaling.metrics.cpu_threshold" $DEFAULT_CPU_THRESHOLD)
                memory_threshold=$(config_get_int "scaling.metrics.memory_threshold" $DEFAULT_MEMORY_THRESHOLD)
                
                if (( $(echo "$cpu_usage < $cpu_threshold / 2" | bc -l 2>/dev/null || echo "0") )) && \
                   (( $(echo "$memory_usage < $memory_threshold / 2" | bc -l 2>/dev/null || echo "0") )); then
                    log_info "Considering scale down for $name: CPU=${cpu_usage}%, MEM=${memory_usage}%"
                    scale_down_service "$name"
                fi
            fi
        fi
    done
}

# Start auto-scaling daemon
start_autoscaler() {
    require_config_loaded
    
    local check_interval
    check_interval=$(config_get_string "scaling.check_interval" "$DEFAULT_CHECK_INTERVAL")
    
    # Convert interval to seconds
    local interval_seconds
    if [[ "$check_interval" =~ ^([0-9]+)m$ ]]; then
        interval_seconds=$((${BASH_REMATCH[1]} * 60))
    elif [[ "$check_interval" =~ ^([0-9]+)s$ ]]; then
        interval_seconds=${BASH_REMATCH[1]}
    else
        interval_seconds=30  # Default 30 seconds
    fi
    
    log_info "Starting auto-scaler with ${interval_seconds}s check interval"
    
    # Create scaling directories
    safe_mkdir "$SCALER_DIR"
    safe_mkdir "$METRICS_DIR"
    safe_mkdir "$COOLDOWN_DIR"
    
    # Main scaling loop
    while true; do
        run_scaling_check
        log_debug "Sleeping for ${interval_seconds}s..."
        sleep "$interval_seconds"
    done
}

# Stop auto-scaling daemon
stop_autoscaler() {
    log_info "Stopping auto-scaler..."
    
    # Find and kill autoscaler processes
    if pgrep -f "auto-scaler.sh" >/dev/null; then
        pkill -f "auto-scaler.sh"
        log_info "Auto-scaler stopped"
    else
        log_info "Auto-scaler not running"
    fi
}

# Get scaling status
get_scaling_status() {
    require_config_loaded
    
    echo "Auto-Scaling Status:"
    echo "==================="
    
    if [[ "$(config_get_bool "scaling.enabled")" == "true" ]]; then
        echo "Status: ENABLED"
    else
        echo "Status: DISABLED"
        return 0
    fi
    
    # Show current metrics and scales
    local proxy_count
    proxy_count=$(config_get_array_table_count "proxies")
    
    for ((i=0; i<proxy_count; i++)); do
        local name type current_scale
        name=$(config_get_string "proxies.${i}.name")
        type=$(config_get_string "proxies.${i}.type")
        current_scale=$(get_current_scale "$name")
        
        echo
        echo "Service: $name ($type)"
        echo "  Current Scale: $current_scale instances"
        
        local metrics_file="${METRICS_DIR}/${name}.json"
        if [[ -f "$metrics_file" ]]; then
            local cpu memory connections response_time timestamp
            cpu=$(jq -r '.metrics.cpu_usage' "$metrics_file" 2>/dev/null || echo "N/A")
            memory=$(jq -r '.metrics.memory_usage' "$metrics_file" 2>/dev/null || echo "N/A")
            connections=$(jq -r '.metrics.connections' "$metrics_file" 2>/dev/null || echo "N/A")
            response_time=$(jq -r '.metrics.response_time' "$metrics_file" 2>/dev/null || echo "N/A")
            timestamp=$(jq -r '.timestamp' "$metrics_file" 2>/dev/null || echo "N/A")
            
            echo "  Last Metrics ($timestamp):"
            echo "    CPU Usage: ${cpu}%"
            echo "    Memory Usage: ${memory}%"
            echo "    Connections: $connections"
            echo "    Response Time: ${response_time}ms"
        else
            echo "  No metrics available"
        fi
    done
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize auto-scaler
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    log_debug "Auto-scaler loaded"
fi