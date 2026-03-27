#!/bin/bash
# tmod-monitor.sh - Enhanced server monitoring with health checks and alerts
export SCRIPT_VERSION="2.5.0"

# Get the script directory reliably
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="$SCRIPT_DIR/tmod-core.sh"  

# Check if core script exists before sourcing
if [[ -f "$CORE_SCRIPT" ]]; then
     
    # shellcheck disable=SC1090
    source "$CORE_SCRIPT" || {
        echo "❌ Failed to load core functions from $CORE_SCRIPT"
        exit 1
    }
else
    echo "❌ Cannot find core functions at: $CORE_SCRIPT"
    exit 1
fi

# Monitoring configuration
HEALTH_CHECK_INTERVAL=60
CPU_THRESHOLD=80
MEMORY_THRESHOLD=80
DISK_THRESHOLD=90

# Enhanced logging for monitoring
log_monitor() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$timestamp] [$level] $message" | tee -a "$LOG_DIR/monitor.log"
}



# Get enhanced server stats (unique to monitor)
get_enhanced_server_stats() {
    local pid
    pid=$(get_server_pid)

    if [[ -z "$pid" ]]; then
        echo "Process not found"
        return 1
    fi

    # CPU and Memory usage
    local cpu_mem
    cpu_mem=$(ps -p "$pid" -o %cpu,%mem --no-headers 2>/dev/null || echo "0.0 0.0")

    # Disk usage
    local disk_usage
    disk_usage=$(df "$BASE_DIR" | awk 'NR==2 {print $5}' | sed 's/%//')

    # Uptime calculation
    local start_time
    start_time=$(stat -c %Y "/proc/$pid" 2>/dev/null || echo 0)
    local uptime_seconds=$(($(date +%s) - start_time))
    local uptime_formatted
    uptime_formatted=$(printf "%dd %02dh %02dm" \
        $((uptime_seconds/86400)) \
        $((uptime_seconds%86400/3600)) \
        $((uptime_seconds%3600/60)))

    echo "$cpu_mem $disk_usage $uptime_formatted"
}

# Health check with enhanced alerts (unique to monitor)
perform_health_check() {
    local stats alert_msg=""

    if ! is_server_up; then
        log_monitor "Server is not running!" "CRITICAL"
        return 1
    fi

    stats=$(get_enhanced_server_stats)
    if [[ "$stats" == "Process not found" ]]; then
        log_monitor "Server process monitoring failed" "ERROR"
        return 1
    fi

    # Parse stats
    local cpu mem disk uptime
    read -r cpu mem disk uptime <<< "$stats"

    # Remove decimal points for comparison
    local cpu_int=${cpu%.*}
    local mem_int=${mem%.*}

    # Check thresholds
    if (( cpu_int > CPU_THRESHOLD )); then
        alert_msg+="🔥 High CPU: ${cpu}% "
    fi

    if (( mem_int > MEMORY_THRESHOLD )); then
        alert_msg+="💾 High Memory: ${mem}% "
    fi

    if (( disk > DISK_THRESHOLD )); then
        alert_msg+="💿 High Disk: ${disk}% "
    fi

    # Log current stats
    log_monitor "Health Check - CPU: ${cpu}%, Mem: ${mem}%, Disk: ${disk}%, Uptime: $uptime" "INFO"

    # Send alerts if needed
    if [[ -n "$alert_msg" ]]; then
        log_monitor "Resource warning: $alert_msg" "WARN"
    fi

    return 0
}

# Comprehensive status dashboard (unique to monitor)
show_status() {
    clear
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🎮 tModLoader Server Status Dashboard"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local status_icon status_text
    if is_server_up; then
        status_icon="🟢"
        status_text="ONLINE"
    else
        status_icon="🔴"
        status_text="OFFLINE"
    fi

    echo "📊 Server Status: $status_icon $status_text"
    echo "📅 Last Check: $(date '+%Y-%m-%d %H:%M:%S')"

    if is_server_up; then
        local stats
        stats=$(get_enhanced_server_stats)
        
        if [[ "$stats" != "Process not found" ]]; then
            local cpu mem disk uptime
            read -r cpu mem disk uptime <<< "$stats"

            echo "⚡ CPU Usage: ${cpu}%"
            echo "💾 Memory Usage: ${mem}%"
            echo "💿 Disk Usage: ${disk}%"
            echo "⏱️  Uptime: $uptime"
            echo "👥 Players Online: $(get_player_count)"

            # Show mod count
            local mod_count
            mod_count=$(get_mod_list | wc -l)
            echo "📦 Mods Loaded: $mod_count"

            # Screen session info
            local screen_info
            screen_info=$(screen -list | grep tmodloader_server || echo 'Not found')
            echo "📺 Screen Session: $screen_info"
        fi

        # Recent log entries
        echo
        echo "📋 Recent Activity (last 5 lines):"
        echo "┌────────────────────────────────────────────────────────────┐"
        if [[ -f "$LOG_DIR/server.log" ]]; then
            tail -5 "$LOG_DIR/server.log" | sed 's/^/│ /' | cut -c1-60
        else
            echo "│ No log file found"
        fi
        echo "└────────────────────────────────────────────────────────────┘"
    else
        echo "❌ Server is not running"
        echo
        echo "💡 To start the server: ./tmod-server.sh start"
        echo "💡 To check logs: tail -f $LOG_DIR/server.log"
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Continuous monitoring mode (unique to monitor)
monitor_continuously() {
    log_monitor "Starting enhanced continuous monitoring mode" "INFO"

    local check_counter=0
    
    while true; do
        # Standard health check
        perform_health_check
        
        # Enhanced mod error checking every 3 minutes
        ((check_counter++))
        if [[ $((check_counter % 3)) -eq 0 ]]; then
            if ! check_mod_errors >/dev/null 2>&1; then
                echo "  [$(date '+%H:%M:%S')] ERROR: Mod errors detected - check logs"
            fi
        fi
        
        # Display current status in monitoring mode
        if is_server_up; then
            local mon_stats
            mon_stats=$(get_server_info)  # ← Use the working function
            if [[ "$mon_stats" != "not_running" ]]; then
                local mon_cpu mon_mem mon_uptime
                read -r mon_cpu mon_mem mon_uptime <<< "$mon_stats"
                local players
                players=$(get_player_count)
                local disk_usage
                disk_usage=$(df "$BASE_DIR" 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//' || echo "0")
                echo "[$(date '+%H:%M:%S')] CPU: ${mon_cpu}% | Mem: ${mon_mem}% | Disk: ${disk_usage}% | Up: ${mon_uptime}m | Players: $players"
            fi
        else
            echo "[$(date '+%H:%M:%S')] Server offline"
        fi
        
        sleep "$HEALTH_CHECK_INTERVAL"
    done
}

# Show monitoring logs
show_logs() {
    if [[ -f "$LOG_DIR/monitor.log" ]]; then
        echo "📋 Monitor Logs (last 20 entries):"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        tail -20 "$LOG_DIR/monitor.log"
    else
        echo "📋 No monitor logs found"
    fi
}

# Show help
show_help() {
    cat << 'EOF'
🔧 tModLoader Enhanced Server Monitor

Monitor server health, performance, and send intelligent alerts

Usage: ./tmod-monitor.sh [command]

Commands:
  status      Show current server status dashboard
  monitor     Start continuous monitoring with alerts  
  check       Perform single health check
  logs        Show recent monitor logs
  help        Show this help message

Examples:
  ./tmod-monitor.sh status     # One-time status check
  ./tmod-monitor.sh monitor    # Continuous monitoring
  ./tmod-monitor.sh logs       # View monitor history

Features:
  ✅ Real-time server health monitoring
  ✅ Discord alerts for critical issues
  ✅ Resource usage tracking (CPU/Memory/Disk)  
  ✅ Player count tracking
  ✅ Mod error detection and alerting
  ✅ Configurable alert thresholds

Configuration:
  Edit thresholds at top of script:
  - CPU_THRESHOLD=80 (%)
  - MEMORY_THRESHOLD=80 (%)
  - DISK_THRESHOLD=90 (%)
  - HEALTH_CHECK_INTERVAL=60 (seconds)
EOF
}

# Main execution
init_tmod

case "${1:-status}" in
    status)  show_status ;;
    monitor) monitor_continuously ;;
    check)   
        if perform_health_check; then
            echo "✅ Health check passed"
        else
            echo "❌ Health check failed"
            exit 1
        fi
        ;;
    logs)    show_logs ;;
    help|*)  show_help ;;
esac
