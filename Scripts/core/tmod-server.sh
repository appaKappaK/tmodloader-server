#!/bin/bash
# tmod-server.sh - Server control (start/stop/restart) - FIXED PATHS
export SCRIPT_VERSION="2.5.0"

# FIXED: Use consistent method for script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="$SCRIPT_DIR/tmod-core.sh"

if [[ -f "$CORE_SCRIPT" ]]; then
     
    # shellcheck disable=SC1090
    source "$CORE_SCRIPT" || {
        echo "Error: Failed to load core functions from $CORE_SCRIPT"
        exit 1
    }
else
    echo "Error: Cannot find core functions at: $CORE_SCRIPT"
    exit 1
fi

print_divider() {
    printf '%s\n' '------------------------------------------------------------'
}

start_server() {
    if is_server_up; then
        echo "Info: Server is already running"
        return 0
    fi

    echo "Starting server..."
    log_it "Starting tModLoader server"

    if start_server_screen; then
        echo "OK: Server started successfully"
        return 0
    else
        echo "Error: Failed to start server"
        return 1
    fi
}

stop_server() {
    if ! is_server_up; then
        echo "Server not running"
        return 0
    fi

    echo "Stopping server..."
    log_it "Stopping server"

    # Try graceful shutdown first
    screen -S tmodloader_server -p 0 -X stuff "exit\n" 2>/dev/null
    sleep 5

    # Force kill if still running
    if is_server_up; then
        kill_server_hard
        sleep 2
    fi

    if is_server_up; then
        echo "Error: Failed to stop server"
        log_it "Server stop failed" "ERROR"
        return 1
    else
        echo "OK: Server stopped"
        log_it "Server stopped successfully"
        return 0
    fi
}

restart_server() {
    echo "Restarting server..."
    log_it "Restarting server"

    stop_server
    sleep 3
    start_server
}

show_status() {
    print_divider
    echo "tModLoader Server Status"
    print_divider
    
    if is_server_up; then
        echo "Status: ONLINE"
        
        local info
        info=$(get_server_info)
        local cpu mem uptime
        read -r cpu mem uptime <<< "$info"
        
        echo "CPU: ${cpu}%"
        echo "Memory: ${mem}%"
        echo "Uptime: ${uptime} minutes"
        
        local mod_count
        mod_count=$(get_mod_list | wc -l)
        echo "Mods: $mod_count loaded"
        
        # Show recent activity
        echo ""
        echo "Recent log entries:"
        print_divider
        if [[ -f "$LOG_DIR/server.log" ]]; then
            tail -3 "$LOG_DIR/server.log" | sed 's/^/  /'
        else
            echo "  No server log file found"
        fi
    else
        echo "Status: OFFLINE"
        echo ""
        echo "Use: $0 start"
    fi
    print_divider
}

# Simple help
show_help() {
    cat << EOF
tModLoader Server Control

Usage: $0 [command]

Commands:
  start    - Start the server
  stop     - Stop the server  
  restart  - Restart the server
  status   - Show server status
  help     - Show this help

Examples:
  $0 start
  $0 status
  $0 restart
EOF
}

# Main execution
init_tmod

case "${1:-help}" in
    start)   start_server ;;
    stop)    stop_server ;;
    restart) restart_server ;;
    status)  show_status ;;
    help|*)  show_help ;;
esac
