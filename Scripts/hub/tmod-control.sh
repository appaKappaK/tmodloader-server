#!/bin/bash
# tmod-control.sh - Enhanced unified control system with advanced management
export SCRIPT_VERSION="2.6.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Correct path to tmod-core.sh (it's in ../core relative to hub directory)
CORE_SCRIPT="$SCRIPT_DIR/../core/tmod-core.sh"

if [[ -f "$CORE_SCRIPT" ]]; then
     
    # shellcheck disable=SC1090
    source "$CORE_SCRIPT"
else
    echo "ERROR: Cannot find tmod-core.sh at $CORE_SCRIPT" >&2
    exit 1
fi

# Enhanced control system configuration
MAIN_LOG="$LOG_DIR/control.log"

# Enhanced logging for control system
log_control() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local line="[$timestamp] [$level] $message"
    echo "$line" >> "$MAIN_LOG"
    case "$level" in
        WARN|ERROR|CRITICAL)
            echo "$line" ;;
        *)
            [[ "${TMOD_DEBUG:-0}" == "1" ]] && echo "$line" ;;
    esac
}

print_divider() {
    printf '%s\n' '------------------------------------------------------------'
}

# Validate script dependencies
check_dependencies() {
    local missing_scripts=()
    local scripts=(
        "$SCRIPT_DIR/../core/tmod-server.sh:Server control script"
        "$SCRIPT_DIR/../backup/tmod-backup.sh:Backup manager"
        "$SCRIPT_DIR/../core/tmod-monitor.sh:Monitoring system"
        "$SCRIPT_DIR/../steam/tmod-workshop.sh:Workshop manager"
    )
    
    for script_info in "${scripts[@]}"; do
        local script_path="${script_info%:*}"
        local script_desc="${script_info#*:}"
        
        if [[ ! -f "$script_path" ]]; then
            missing_scripts+=("$script_desc ($script_path)")
        elif [[ ! -x "$script_path" ]]; then
            chmod +x "$script_path" 2>/dev/null || missing_scripts+=("$script_desc (not executable)")
        fi
    done
    
    if (( ${#missing_scripts[@]} > 0 )); then
        echo "Error: Missing or invalid scripts:"
        printf '   %s\n' "${missing_scripts[@]}"
        return 1
    fi
    
    return 0
}

launch_go_tui() {
    local tui_bin="$BASE_DIR/bin/tmodloader-ui"
    if [[ -x "$tui_bin" ]]; then
        cd "$BASE_DIR" || return 1
        exec "$tui_bin"
    fi

    if command -v go >/dev/null 2>&1 && [[ -f "$BASE_DIR/go.mod" ]]; then
        cd "$BASE_DIR" || return 1
        exec go run ./cmd/tmodloader-ui
    fi

    return 1
}

# Enhanced server control functions
start_server() {
    if is_server_up; then
        echo "Info: Server is already running"
        return 0
    fi
    
    echo "Starting tModLoader server..."
    log_control "Starting server via enhanced control system" "INFO"
    
    if "$SCRIPT_DIR/../core/tmod-server.sh" start; then
        echo "OK: Server start initiated successfully"
        return 0
    else
        echo "Error: Failed to start server"
        log_control "Server start failed" "ERROR"
        return 1
    fi
}

stop_server() {
    if ! is_server_up; then
        echo "Info: Server is not running"
        return 0
    fi
    
    echo "Stopping tModLoader server..."
    log_control "Stopping server via control system" "INFO"
    
    # Create automatic backup before stopping
    echo "Creating pre-shutdown backup..."
    if "$SCRIPT_DIR/../backup/tmod-backup.sh" worlds >/dev/null 2>&1; then
        echo "OK: Pre-shutdown backup completed"
    else
        echo "Warning: Pre-shutdown backup failed (continuing with shutdown)"
    fi
    
    if "$SCRIPT_DIR/../core/tmod-server.sh" stop; then
        echo "OK: Server stopped successfully"
        return 0
    else
        echo "Error: Failed to stop server"
        log_control "Server stop failed" "ERROR"
        return 1
    fi
}

restart_server() {
    echo "Restarting tModLoader server..."
    log_control "Restarting server via control system" "INFO"
    
    if "$SCRIPT_DIR/../core/tmod-server.sh" restart; then
        echo "OK: Server restart completed"
        return 0
    else
        echo "Error: Failed to restart server"
        log_control "Server restart failed" "ERROR"
        return 1
    fi
}

# Enhanced status with comprehensive overview
quick_status() {
    print_divider
    echo "tModLoader Status"
    print_divider
    
    # Server status with detailed info
    if is_server_up; then
        echo "Server: ONLINE"
        
        local info
        info=$(get_server_info)
        local cpu mem uptime
        read -r cpu mem uptime <<< "$info"
        echo "CPU: ${cpu}% | Memory: ${mem}% | Uptime: ${uptime}m"
        
        local mod_count
        mod_count=$(get_mod_list | wc -l)
        echo "Mods: $mod_count loaded"

        local player_count
        player_count=$(get_player_count)
        echo "Players: $player_count online"
        
        # Check for mod errors
        if check_mod_errors >/dev/null 2>&1; then
            echo "Mod Status: OK"
        else
            echo "Mod Status: Issues detected"
        fi
    else
        echo "Server: OFFLINE"
    fi
    
    # System health indicators
    local disk_usage
    disk_usage=$(df "$BASE_DIR" | awk 'NR==2 {print $5}' | sed 's/%//')
    if (( disk_usage > 90 )); then
        echo "Disk: Critical (${disk_usage}%)"
    elif (( disk_usage > 80 )); then
        echo "Disk: High (${disk_usage}%)"
    else
        echo "Disk: OK (${disk_usage}%)"
    fi
    
    # Backup status
    if [[ -x "$SCRIPT_DIR/../backup/tmod-backup.sh" ]]; then
        local world_backups
        world_backups=$(find "$BASE_DIR/Backups/Worlds" -name "worlds_*.tar.gz" 2>/dev/null | wc -l)
        echo "Backups: $world_backups world backups available"
    fi
    
    print_divider
}

# Legacy shell UI removed. Interactive entrypoints now launch only the Go control room.

show_interactive_menu() {
    local mode="${1:-interactive}"

    case "$mode" in
        ""|interactive|menu|tui|go)
            if launch_go_tui; then
                return 0
            fi

            echo "Error: Go control room is not available."
            echo "Tip: Build it with 'make tui-build' or run it from source with 'make tui-run'."
            echo "Tip: Install Go locally if you want 'bash Scripts/hub/tmod-control.sh' to launch from source."
            return 1
            ;;
        classic|palette|legacy|plain|fzf|dialog)
            echo "Error: The legacy shell UI has been removed."
            echo "Tip: Use './tmod-control.sh interactive' or './tmod-control.sh tui' for the Go control room."
            return 1
            ;;
        *)
            echo "Error: Unknown interactive mode: $mode"
            echo "Tip: Use './tmod-control.sh interactive' or './tmod-control.sh tui'."
            return 1
            ;;
    esac
}

# Enhanced maintenance with comprehensive tasks
run_maintenance() {
    echo "Running maintenance tasks..."
    log_control "Starting maintenance sequence" "INFO"
    
    local tasks_completed=0
    local tasks_failed=0
    local start_time
    start_time=$(date +%s)
    
    print_divider
    echo "Maintenance Task Progress"
    print_divider
    
    # Task 1: Create maintenance backup
    echo "[1/5] Creating maintenance backup..."
    if [[ -x "$SCRIPT_DIR/../backup/tmod-backup.sh" ]] && "$SCRIPT_DIR/../backup/tmod-backup.sh" worlds >/dev/null 2>&1; then
        echo "    OK: Maintenance backup completed"
        ((tasks_completed++))
    else
        echo "    Error: Maintenance backup failed"
        ((tasks_failed++))
    fi
    
    # Task 2: Clean old backups
    echo "[2/5] Cleaning old backups..."
    if [[ -x "$SCRIPT_DIR/../backup/tmod-backup.sh" ]] && "$SCRIPT_DIR/../backup/tmod-backup.sh" cleanup >/dev/null 2>&1; then
        echo "    OK: Old backups cleaned"
        ((tasks_completed++))
    else
        echo "    Error: Backup cleanup failed"
        ((tasks_failed++))
    fi
    
    # Task 3: Rotate logs
    echo "[3/5] Rotating logs..."
    if rotate_logs; then
        echo "    OK: Log rotation completed"
        ((tasks_completed++))
    else
        echo "    Error: Log rotation failed"
        ((tasks_failed++))
    fi
    
    # Task 4: Sync mods
    echo "[4/5] Syncing mods..."
    if [[ -x "$SCRIPT_DIR/../steam/tmod-workshop.sh" ]] && "$SCRIPT_DIR/../steam/tmod-workshop.sh" sync --yes >/dev/null 2>&1; then
        echo "    OK: Mod sync completed"
        ((tasks_completed++))
    else
        echo "    Error: Mod sync failed"
        ((tasks_failed++))
    fi
    
    # Task 5: Check mod errors
    echo "[5/5] Checking for mod errors..."
    if check_mod_errors >/dev/null 2>&1; then
        echo "    OK: No mod errors found"
        ((tasks_completed++))
    else
        echo "    Warning: Mod errors detected (check logs)"
        ((tasks_failed++))
    fi
    
    # Calculate maintenance time
    local total_time
    total_time=$(($(date +%s) - start_time))
    local time_formatted
    time_formatted=$(printf "%dm %02ds" $((total_time/60)) $((total_time%60)))
    
    print_divider
    echo "Maintenance Summary"
    echo "Completed: $tasks_completed/5 tasks"
    echo "Failed: $tasks_failed/5 tasks"
    echo "Duration: $time_formatted"
    print_divider
    
    local total_tasks=5
    log_control "Maintenance completed: $tasks_completed/$total_tasks successful in $time_formatted" "INFO"
    
    if (( tasks_failed == 0 )); then
        echo "OK: All maintenance tasks completed successfully"
    else
        echo "Warning: Maintenance completed with some issues"
    fi
}

# Quick inline system diagnostics (full diagnostics use tmod-diagnostics.sh)
show_system_diagnostics() {
    print_divider
    echo "System Diagnostics Report"
    print_divider
    
    # Check script dependencies
    echo "Script Dependencies:"
    if check_dependencies; then
        echo "   OK: All management scripts available and executable"
    else
        echo "   Error: Some management scripts missing or not executable"
    fi
    echo
    
    # Directory structure check
    echo "Directory Structure:"
    local dirs
    dirs=("$BASE_DIR" "$LOG_DIR" "$MODS_DIR" "$BASE_DIR/Configs" "$BASE_DIR/Worlds")
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            echo "   OK: $dir"
        else
            echo "   Missing: $dir"
        fi
    done
    echo
    
    # Process information
    echo "Process Information:"
    if is_server_up; then
        local pid
        pid=$(get_server_pid)
        echo "   OK: Server PID: $pid"
        echo "   Process info: $(ps -p "$pid" -o pid,ppid,cmd --no-headers 2>/dev/null || echo "Process details unavailable")"
    else
        echo "   Error: No server process running"
    fi
    echo
    
    # Network and screen sessions
    echo "Screen Sessions:"
    local screen_sessions
    screen_sessions=$(screen -list 2>/dev/null | grep -c tmodloader || echo "0")
    if (( screen_sessions > 0 )); then
        echo "   OK: tModLoader screen sessions: $screen_sessions"
        screen -list | grep tmodloader | sed 's/^/   /'
    else
        echo "   Error: No tModLoader screen sessions found"
    fi
    echo
    
    # Recent activity analysis
    echo "Recent Activity:"
    if [[ -f "$LOG_DIR/server.log" ]]; then
        local log_size="?"
        log_size=$(stat --format="%s" "$LOG_DIR/server.log" 2>/dev/null | numfmt --to=iec || echo "?")
        local last_modified
        last_modified=$(date -r "$LOG_DIR/server.log" '+%Y-%m-%d %H:%M')
        echo "   Server log: $log_size (last modified: $last_modified)"
    
        local recent_errors
        recent_errors=$(tail -100 "$LOG_DIR/server.log" | grep -c "ERROR" || echo "0")
        local recent_warnings
        recent_warnings=$(tail -100 "$LOG_DIR/server.log" | grep -c "WARN" || echo "0")
        echo "   Recent errors: $recent_errors, warnings: $recent_warnings"
    else
        echo "   Error: No server log file found"
    fi
    
    print_divider
}

# Emergency shutdown with comprehensive safety
emergency_shutdown() {
    print_divider
    echo "EMERGENCY SHUTDOWN INITIATED"
    print_divider
    log_control "Emergency shutdown initiated" "CRITICAL"
    
    # Create emergency backup if possible
    if [[ -x "$SCRIPT_DIR/../backup/tmod-backup.sh" ]]; then
        echo "Creating emergency backup..."
        if "$SCRIPT_DIR/../backup/tmod-backup.sh" worlds >/dev/null 2>&1; then
            echo "OK: Emergency backup completed"
            log_control "Emergency backup completed" "SUCCESS"
        else
            echo "Warning: Emergency backup failed"
            log_control "Emergency backup failed" "WARN"
        fi
    fi
    
    # Force kill all related processes
    echo "Terminating server processes..."
    pkill -f "tModLoader.dll" 2>/dev/null || true
    pkill -f "dotnet.*tModLoader" 2>/dev/null || true
    screen -S tmodloader_server -X quit 2>/dev/null || true
    
    # Wait and force kill if necessary
    sleep 2
    pkill -9 -f "tModLoader.dll" 2>/dev/null || true
    
    echo "OK: Emergency shutdown completed"
    log_control "Emergency shutdown completed" "INFO"
    print_divider
}

# Show enhanced help
show_help() {
    cat << 'EOF'
tModLoader Unified Control System

Central command center for all server operations with advanced management features

Usage: ./tmod-control.sh [category] [command] [options]

Server Control:
  server start          Start the server with pre-checks
  server stop           Stop the server with automatic backup
  server restart        Restart the server with validation
  server status         Show detailed server status

Workshop Management:
  workshop download     Download mods from Steam Workshop
  workshop sync [--yes] Sync workshop mods to server
  workshop list         List downloaded workshop mods with compatibility info
  workshop archive [--yes] Archive old mod versions
  workshop cleanup      Clean up workshop downloads
  workshop status       Workshop system status
  workshop init         Initialize workshop system
  workshop ids          Show/edit mod IDs configuration

Monitoring & Performance:
  monitor status        Show monitoring dashboard
  monitor start         Start continuous monitoring
  monitor logs          View monitoring logs

Mod Load Management:
  mods list              Show installed mods with enabled/disabled status
  mods enable  <name>    Enable a mod (or 'all')
  mods disable <name>    Disable a mod (or 'all')
  mods pick              Interactive mod toggle picker
  mods add [--yes] <url|id>  Add a Workshop URL or ID and auto-clean placeholders if confirmed
  mods ids               Show queued Workshop IDs or URLs from mod_ids.txt
  mods clear [--yes]     Clear queued Workshop IDs from mod_ids.txt

Maintenance & Utilities:
  maintenance           Run comprehensive maintenance tasks
  emergency             Emergency shutdown with backup
  diagnostics           Run full diagnostics script
  scripts               Show all scripts status
  health                Comprehensive system health check
  logs                  Show recent system logs

Quick Commands:
  start                 Start server (shortcut)
  stop                  Stop server (shortcut)  
  restart               Restart server (shortcut)
  status                Quick status overview
  backup                Auto backup (shortcut)
  interactive           Launch the Go control room
  tui                   Alias for the Go control room
  help                  Show this help

Examples:
  ./tmod-control.sh start                    # Quick start
  ./tmod-control.sh workshop sync --yes      # Sync mods from workshop
  ./tmod-control.sh mods pick                # Interactive mod toggle menu
  ./tmod-control.sh mods add 2824688804      # Queue a Workshop mod by ID
  ./tmod-control.sh mods list                # See enabled/disabled status
  ./tmod-control.sh mods enable CalamityMod  # Enable a specific mod
  ./tmod-control.sh backup auto              # Complete backup
  ./tmod-control.sh monitor start            # Start monitoring
  ./tmod-control.sh workshop download        # Download workshop mods
  ./tmod-control.sh tui                      # Launch the Go control room
  ./tmod-control.sh interactive              # Accepted alias for the Go control room
  ./tmod-control.sh maintenance              # Run maintenance

Interactive Mode:
  ./tmod-control.sh tui
  ./tmod-control.sh interactive

  Interactive requests now open only the Go control room.
  If no built binary is present, the shell entrypoint will try 'go run ./cmd/tmodloader-ui' from the repo root.
  If Go is not installed, build the UI first with 'make tui-build'.

Automation Examples:
  # Daily maintenance at 3 AM
  0 3 * * * $SCRIPT_DIR/tmod-control.sh maintenance

  # Hourly health check
  0 * * * * $SCRIPT_DIR/tmod-control.sh health

  # Weekly server restart on Sundays at 4 AM
  0 4 * * 0 $SCRIPT_DIR/tmod-control.sh restart
  
  # Workshop mod sync daily at 6 AM
  0 6 * * * $SCRIPT_DIR/tmod-control.sh workshop sync --yes


Features:
  - Unified control of all server operations
  - Persistent Go TUI as the only interactive control room
  - Manifest-driven addon action packs from Addons/*/addon.json
  - Comprehensive maintenance automation
  - Emergency procedures with safety backups
  - System health monitoring and diagnostics
  - Dependency validation and error handling
  - Advanced backup integration
  - Performance monitoring integration
  - Steam Workshop management integration
  - Automated log rotation and cleanup

Dependencies:
  - All tmod-* management scripts in same directory
  - Screen for server management
  - jq for enhanced JSON formatting (optional)
  - Standard GNU utilities (find, tar, gzip, etc.)
EOF
}

# Main execution with enhanced error handling
main() {
    # Strip --debug from args and export so all child scripts inherit it
    local filtered_args=()
    for arg in "$@"; do
        if [[ "$arg" == "--debug" ]]; then
            export TMOD_DEBUG=1
        else
            filtered_args+=("$arg")
        fi
    done
    set -- "${filtered_args[@]}"

    # Initialize system
    mkdir -p "$LOG_DIR"

    # Validate script dependencies - skip for read-only / informational commands
    local cmd="${1:-interactive}"
    local skip_dep_check=false
    case "$cmd" in
        status|logs|help|interactive|menu|tui|--help|-h|"") skip_dep_check=true ;;
    esac

    if [[ "$skip_dep_check" == "false" ]] && ! check_dependencies; then
        echo "Error: Critical dependencies missing. Please ensure all tmod-* scripts are present."
        echo "Tip: Run './tmod-control.sh scripts' to see detailed script status."
        exit 1
    fi

    # Log startup
    log_control "Enhanced control system started" "INFO"

    # Parse command line arguments
    case "${1:-interactive}" in
        # Server control category
        server)
            case "${2:-help}" in
                start)   start_server ;;
                stop)    stop_server ;;
                restart) restart_server ;;
                status)  "$SCRIPT_DIR/../core/tmod-server.sh" status ;;
                *)       echo "Server commands: start, stop, restart, status" ;;
            esac
            ;;
        
        # Backup system category
        backup)
            if [[ -x "$SCRIPT_DIR/../backup/tmod-backup.sh" ]]; then
                if [[ -z "$2" ]]; then
                    exec "$SCRIPT_DIR/../backup/tmod-backup.sh" auto
                else
                    shift
                    exec "$SCRIPT_DIR/../backup/tmod-backup.sh" "$@"
                fi
            else
                echo "Error: Backup script not available"
                exit 1
            fi
            ;;
        
        # Monitoring category
        monitor)
            if [[ -x "$SCRIPT_DIR/../core/tmod-monitor.sh" ]]; then
                case "${2:-status}" in
                    status) exec "$SCRIPT_DIR/../core/tmod-monitor.sh" status ;;
                    start)  exec "$SCRIPT_DIR/../core/tmod-monitor.sh" monitor ;;
                    logs)   exec "$SCRIPT_DIR/../core/tmod-monitor.sh" logs ;;
                    *)      exec "$SCRIPT_DIR/../core/tmod-monitor.sh" help ;;
                esac
            else
                echo "Error: Monitoring script not available"
                exit 1
            fi
            ;;
        
        # Workshop management
        workshop)
            if [[ -x "$SCRIPT_DIR/../steam/tmod-workshop.sh" ]]; then
                case "${2:-help}" in
                    download) exec "$SCRIPT_DIR/../steam/tmod-workshop.sh" download "${@:3}" ;;
                    sync)     exec "$SCRIPT_DIR/../steam/tmod-workshop.sh" sync "${@:3}" ;;
                    list)     exec "$SCRIPT_DIR/../steam/tmod-workshop.sh" list "${@:3}" ;;
                    archive)  exec "$SCRIPT_DIR/../steam/tmod-workshop.sh" archive "${@:3}" ;;
                    cleanup)  exec "$SCRIPT_DIR/../steam/tmod-workshop.sh" cleanup "${@:3}" ;;
                    status)   exec "$SCRIPT_DIR/../steam/tmod-workshop.sh" status "${@:3}" ;;
                    init)     exec "$SCRIPT_DIR/../steam/tmod-workshop.sh" init "${@:3}" ;;
                    *)        exec "$SCRIPT_DIR/../steam/tmod-workshop.sh" help ;;
                esac
            else
                echo "Error: Workshop script not available"
                exit 1
            fi
            ;;
        
        # Mod load management
        mods)
            if [[ -x "$SCRIPT_DIR/../steam/tmod-workshop.sh" ]]; then
                shift
                exec "$SCRIPT_DIR/../steam/tmod-workshop.sh" mods "$@"
            else
                echo "Error: Workshop script not available"
                exit 1
            fi
            ;;

        # Quick shortcuts
        start)      start_server ;;
        stop)       stop_server ;;
        restart)    restart_server ;;
        status)     quick_status ;;
        
        # Utility commands
        maintenance)    run_maintenance ;;
        emergency)      emergency_shutdown ;;
        diagnostics)
            if [[ -x "$SCRIPT_DIR/../diag/tmod-diagnostics.sh" ]]; then
                shift
                exec "$SCRIPT_DIR/../diag/tmod-diagnostics.sh" "${@:-full}"
            else
                show_system_diagnostics
            fi
            ;;
        health)         show_system_diagnostics ;;
        scripts)        show_system_diagnostics ;;
        logs)           
            if [[ -f "$LOG_DIR/server.log" ]]; then
                tail -20 "$LOG_DIR/server.log"
            else
                echo "No server logs found"
            fi
            ;;
        
        # Interactive mode
        interactive|menu) show_interactive_menu "${2:-interactive}" ;;
        tui)             show_interactive_menu "tui" ;;
        
        # Help
        help|--help|-h) show_help ;;
        
        # Default - show interactive menu
        "")             show_interactive_menu "interactive" ;;
        
        # Unknown command
        *)
            echo "Error: Unknown command: $1"
            echo "Tip: Use './tmod-control.sh help' for usage information"
            echo "Tip: Use './tmod-control.sh interactive' for the control room"
            exit 1
            ;;
    esac
}

# Initialize and run
init_tmod
main "$@"
