#!/bin/bash
# tmod-diagnostics.sh - Server diagnostics and troubleshooting
export SCRIPT_VERSION="2.5.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="$SCRIPT_DIR/../core/tmod-core.sh"

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

# Diagnostic configuration
DIAGNOSTIC_LOG="$LOG_DIR/diagnostics.log"
TEMP_DIR="/tmp/tmod_diagnostics"
COMPREHENSIVE_MODE=false

# Enhanced logging for diagnostics
log_diagnostic() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$DIAGNOSTIC_LOG"
    log_it "Diagnostics: $message" "$level"
}

# Initialize diagnostics system - single init, no double-call
init_diagnostics() {
    mkdir -p "$TEMP_DIR" "$LOG_DIR"
    [[ ! -f "$DIAGNOSTIC_LOG" ]] && touch "$DIAGNOSTIC_LOG"
    log_diagnostic "Diagnostics system initialized" "INFO"
}

# System information
gather_system_info() {
    echo "🖥️ System Information:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    echo "Hostname: $(hostname)"
    echo "OS: $(lsb_release -d 2>/dev/null | cut -f2 || grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
    echo "Kernel: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "User: $USER (UID: $(id -u))"
    echo "Current Directory: $PWD"
    echo "Shell: $SHELL"
    echo
    echo "💾 Memory: $(free -h | awk '/^Mem:/ {printf "%s used / %s total", $3, $2}')"
    echo "💿 Disk (server): $(df -h "$BASE_DIR" | awk 'NR==2 {printf "%s used / %s total (%s)", $3, $2, $5}')"
    echo "⚡ Load Average: $(uptime | awk -F'load average:' '{print $2}' | sed 's/^[[:space:]]*//')"
    echo "🕐 Uptime: $(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F', load' '{print $1}')"

    if command -v ip >/dev/null; then
        local ip_addr
        ip_addr=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
        [[ -n "$ip_addr" ]] && echo "🌐 IP Address: $ip_addr"
    fi

    log_diagnostic "System information gathered" "INFO"
}

# Directory structure check
check_directory_structure() {
    echo
    echo "📁 Directory Structure Analysis:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local status_count=0
    local error_count=0

    if [[ -d "$BASE_DIR" ]]; then
        echo "✅ Base directory: $BASE_DIR"
        echo "   📝 Permissions: $(stat -c "%A %U %G" "$BASE_DIR" 2>/dev/null || echo "unknown")"
        echo "   📊 Size: $(du -sh "$BASE_DIR" 2>/dev/null | cut -f1)"
        ((status_count++))
    else
        echo "❌ Base directory missing: $BASE_DIR"
        ((error_count++))
        log_diagnostic "Base directory missing: $BASE_DIR" "ERROR"
        return 1
    fi

    # Required directories under BASE_DIR
    local required_dirs=(
        "Engine:tModLoader engine files"
        "Logs:Server and script logs"
        "Worlds:World save files"
        "Mods:Mod files"
        "Configs:Server configuration"
        "Backups:Backup storage"
    )

    echo
    echo "📋 Required Directories:"
    for dir_info in "${required_dirs[@]}"; do
        local dir_name="${dir_info%:*}"
        local dir_desc="${dir_info#*:}"
        local dir_path="$BASE_DIR/$dir_name"

        if [[ -d "$dir_path" ]]; then
            local item_count dir_size
            item_count=$(find "$dir_path" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
            dir_size=$(du -sh "$dir_path" 2>/dev/null | cut -f1)
            echo "   ✅ $dir_name/ - $dir_desc ($item_count items, $dir_size)"
            ((status_count++))
        else
            echo "   ❌ $dir_name/ - Missing: $dir_desc"
            ((error_count++))
            log_diagnostic "Missing directory: $dir_path" "WARN"
        fi
    done

    # Scripts subdirectory structure
    local scripts_base="$BASE_DIR/Scripts"
    echo
    echo "📋 Scripts Directory Structure:"
    local script_dirs=(
        "core:Core functions and server control"
        "hub:Unified control system"
        "backup:Backup management"
        "steam:Workshop and dependency tools"
        "diag:Diagnostics"
    )

    for dir_info in "${script_dirs[@]}"; do
        local dir_name="${dir_info%:*}"
        local dir_desc="${dir_info#*:}"
        local dir_path="$scripts_base/$dir_name"

        if [[ -d "$dir_path" ]]; then
            local item_count
            item_count=$(find "$dir_path" -mindepth 1 -maxdepth 1 -name "*.sh" 2>/dev/null | wc -l)
            echo "   ✅ scripts/$dir_name/ - $dir_desc ($item_count scripts)"
            ((status_count++))
        else
            echo "   ❌ scripts/$dir_name/ - Missing: $dir_desc"
            ((error_count++))
            log_diagnostic "Missing scripts directory: $dir_path" "WARN"
        fi
    done

    # Optional directories
    local optional_dirs=(
        "ModConfigs:Mod configuration files"
        "Players:Player data files"
    )

    echo
    echo "📋 Optional Directories:"
    for dir_info in "${optional_dirs[@]}"; do
        local dir_name="${dir_info%:*}"
        local dir_desc="${dir_info#*:}"
        local dir_path="$BASE_DIR/$dir_name"

        if [[ -d "$dir_path" ]]; then
            local item_count
            item_count=$(find "$dir_path" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
            echo "   ✅ $dir_name/ - $dir_desc ($item_count items)"
        else
            echo "   ⚠️ $dir_name/ - Not found: $dir_desc"
        fi
    done

    echo
    echo "📊 Directory Summary: $status_count found, $error_count missing"
    log_diagnostic "Directory check: $status_count found, $error_count missing" "INFO"

    return "$([[ $error_count -eq 0 ]] && echo 0 || echo 1)"
}

# Binary detection and validation
check_tmodloader_binaries() {
    echo
    echo "🔧 tModLoader Binary Analysis:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local binary_found=false
    local tmod_binary

    if tmod_binary=$(find_tmodloader_binary); then
        echo "✅ tModLoader binary detected: $tmod_binary"
        binary_found=true

        if [[ "$tmod_binary" == *"dotnet"* ]]; then
            local dotnet_exe="${tmod_binary%% *}"
            local dll_file="${tmod_binary##* }"

            echo "   🔍 Type: .NET Core application"
            echo "   📍 Dotnet: $dotnet_exe"
            echo "   📍 DLL: $dll_file"

            if [[ -x "$dotnet_exe" ]]; then
                echo "   ✅ Dotnet executable is valid"
                if "$dotnet_exe" --info >/dev/null 2>&1; then
                    echo "   ✅ Dotnet runtime functional"
                    local dotnet_version
                    dotnet_version=$("$dotnet_exe" --version 2>/dev/null)
                    [[ -n "$dotnet_version" ]] && echo "   📋 Dotnet version: $dotnet_version"
                else
                    echo "   ❌ Dotnet runtime test failed"
                    log_diagnostic "Dotnet runtime test failed" "ERROR"
                fi
            else
                echo "   ❌ Dotnet executable not found or not executable"
                log_diagnostic "Dotnet executable invalid: $dotnet_exe" "ERROR"
            fi

            if [[ -f "$dll_file" ]]; then
                echo "   ✅ tModLoader.dll exists"
                echo "   📊 DLL size: $(du -h "$dll_file" | cut -f1)"
                echo "   📅 Modified: $(date -r "$dll_file" '+%Y-%m-%d %H:%M:%S')"
            else
                echo "   ❌ tModLoader.dll not found: $dll_file"
                log_diagnostic "tModLoader.dll missing: $dll_file" "ERROR"
            fi
        else
            echo "   🔍 Type: Native executable"
            if [[ -x "$tmod_binary" ]]; then
                echo "   ✅ Binary is executable"
                echo "   📊 Size: $(du -h "$tmod_binary" | cut -f1)"
                echo "   📅 Modified: $(date -r "$tmod_binary" '+%Y-%m-%d %H:%M:%S')"
            else
                echo "   ❌ Binary not executable"
                log_diagnostic "Binary not executable: $tmod_binary" "ERROR"
            fi
        fi
    else
        local engine_dll="$BASE_DIR/Engine/tModLoader.dll"
        local runtimeconfig="$BASE_DIR/Engine/tModLoader.runtimeconfig.json"
        local install_script="$BASE_DIR/Engine/LaunchUtils/InstallDotNet.sh"

        if [[ -f "$engine_dll" && -f "$runtimeconfig" && -f "$install_script" ]]; then
            echo "✅ tModLoader engine files detected"
            echo "   🔍 Type: Fresh engine install awaiting runtime bootstrap"
            echo "   📍 DLL: $engine_dll"
            echo "   📍 Runtime config: $runtimeconfig"
            echo "   📍 Dotnet installer: $install_script"
            echo "   ℹ️ Local Engine/dotnet/ runtime is not installed yet"
            echo "   💡 The toolkit will install the required .NET runtime automatically on first server start"
            binary_found=true
            log_diagnostic "Fresh engine install detected - runtime will bootstrap on first start" "INFO"
        else
            echo "❌ No tModLoader binary found"
            echo "💡 Searched locations:"
            echo "   📍 $BASE_DIR/tModLoaderServer"
            echo "   📍 $BASE_DIR/tModLoaderServer.bin.x86_64"
            echo "   📍 $BASE_DIR/Engine/tModLoaderServer"
            echo "   📍 $BASE_DIR/Engine/dotnet + $BASE_DIR/Engine/tModLoader.dll"
            log_diagnostic "No tModLoader binary found" "ERROR"
        fi
    fi

    log_diagnostic "Binary check completed - Found: $binary_found" "INFO"
    return "$([[ "$binary_found" == "true" ]] && echo 0 || echo 1)"
}

# Configuration files check
check_configuration_files() {
    echo
    echo "📋 Configuration Files Analysis:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local config_errors=0

    # Server configuration
    local server_config="$BASE_DIR/Configs/serverconfig.txt"
    if [[ -f "$server_config" ]]; then
        echo "✅ Server config: $server_config"
        echo "   📊 Size: $(du -h "$server_config" | cut -f1)"
        echo "   📅 Modified: $(date -r "$server_config" '+%Y-%m-%d %H:%M:%S')"
        echo "   📝 Lines: $(wc -l < "$server_config")"

        echo "   🔍 Required settings check:"
        local required_settings=("world" "worldname" "port" "maxplayers")
        for setting in "${required_settings[@]}"; do
            if grep -q "^$setting=" "$server_config" 2>/dev/null; then
                local value
                value=$(grep "^$setting=" "$server_config" | cut -d'=' -f2-)
                echo "     ✅ $setting=$value"
            else
                echo "     ⚠️ $setting not found or commented out"
                log_diagnostic "Config missing setting: $setting" "WARN"
            fi
        done

        if grep -q "^password=" "$server_config" 2>/dev/null; then
            local password
            password=$(grep "^password=" "$server_config" | cut -d'=' -f2-)
            if [[ -n "$password" && ${#password} -ge 8 ]]; then
                echo "     ✅ password=<secure> (${#password} characters)"
            elif [[ -n "$password" ]]; then
                echo "     ⚠️ password=<weak> (${#password} characters - recommend 8+)"
                log_diagnostic "Weak server password detected" "WARN"
            else
                echo "     ℹ️ password=<none> (public server)"
            fi
        fi

        # In comprehensive mode also show the full config content
        if [[ "$COMPREHENSIVE_MODE" == "true" ]]; then
            echo
            echo "   📄 Full config contents:"
            sed 's/^/     /' "$server_config"
        fi
    else
        echo "❌ Server config missing: $server_config"
        echo "💡 Create config with: ./tmod-control.sh init"
        ((config_errors++))
        log_diagnostic "Server config missing: $server_config" "ERROR"
    fi

    # Environment configuration - correct path
    local env_config="$BASE_DIR/Scripts/env.sh"
    echo
    if [[ -f "$env_config" ]]; then
        echo "✅ Environment config: $env_config"
        local env_vars=("DISCORD_WEBHOOK_URL" "STEAM_API_KEY" "STEAM_USERNAME")
        echo "   🔍 Environment variables:"
        for var in "${env_vars[@]}"; do
            if grep -q "^export $var=" "$env_config" 2>/dev/null; then
                local value
                value=$(grep "^export $var=" "$env_config" | cut -d'=' -f2- | tr -d '"')
                if [[ -n "$value" && "$value" != "your_"* ]]; then
                    echo "     ✅ $var=<configured>"
                else
                    echo "     ⚠️ $var=<placeholder>"
                fi
            else
                echo "     ⚠️ $var not found"
            fi
        done
    else
        echo "ℹ️ Environment config not found: $env_config"
        echo "💡 Optional file for Discord/Steam API integration"
    fi

    # Mod configuration
    echo
    echo "📦 Mod Configuration:"
    local mod_count
    mod_count=$(find "$BASE_DIR/Mods" -maxdepth 1 -name "*.tmod" 2>/dev/null | wc -l)
    echo "   📊 Installed mods: $mod_count"

    if [[ $mod_count -gt 0 ]]; then
        local enabled_file="$BASE_DIR/Mods/enabled.json"
        if [[ -f "$enabled_file" ]]; then
            echo "   ✅ Enabled mods list: $enabled_file"
            local enabled_count
            enabled_count=$(jq -r '. | length' "$enabled_file" 2>/dev/null || echo "unknown")
            echo "   📝 Enabled count: $enabled_count"
        else
            echo "   ⚠️ No enabled.json found (will be auto-generated)"
        fi

        echo "   🔍 Checking for mod errors..."
        if check_mod_errors >/dev/null 2>&1; then
            echo "   ✅ No mod errors detected"
        else
            echo "   ⚠️ Mod errors detected in logs"
            ((config_errors++))
            log_diagnostic "Mod errors detected" "WARN"
        fi
    fi

    log_diagnostic "Configuration check completed - Errors: $config_errors" "INFO"
    return "$([[ $config_errors -eq 0 ]] && echo 0 || echo 1)"
}

# System dependencies check
check_system_dependencies() {
    echo
    echo "🔗 System Dependencies Analysis:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local missing_deps=()
    local optional_deps=()

    local required=(
        "bash:Shell (4.0+)"
        "screen:Session management"
        "curl:HTTP requests"
        "grep:Text processing"
        "sed:Text processing"
        "awk:Text processing"
        "tar:Archive management"
        "gzip:Compression"
        "dotnet:.NET runtime"
    )

    echo "📋 Required Dependencies:"
    for dep_info in "${required[@]}"; do
        local dep="${dep_info%:*}"
        local desc="${dep_info#*:}"

        if command -v "$dep" >/dev/null 2>&1; then
            local version=""
            case "$dep" in
                bash)   version=$($dep --version | head -1 | awk '{print $4}') ;;
                screen) version=$($dep -v 2>&1 | head -1 | awk '{print $3}') ;;
                curl)   version=$($dep --version | head -1 | awk '{print $2}') ;;
                dotnet) version=$($dep --version 2>/dev/null) ;;
            esac
            echo "   ✅ $dep - $desc ${version:+($version)}"
        else
            echo "   ❌ $dep - $desc"
            missing_deps+=("$dep")
            log_diagnostic "Missing required dependency: $dep" "ERROR"
        fi
    done

    local optional=(
        "jq:JSON processing (enhanced features)"
        "pigz:Parallel compression (faster backups)"
        "rsync:Efficient file syncing"
        "steamcmd:Steam Workshop integration"
        "unzip:Mod file inspection"
        "htop:Process monitoring"
        "ncdu:Disk usage analysis"
    )

    echo
    echo "📋 Optional Dependencies:"
    for dep_info in "${optional[@]}"; do
        local dep="${dep_info%:*}"
        local desc="${dep_info#*:}"

        if command -v "$dep" >/dev/null 2>&1; then
            echo "   ✅ $dep - $desc"
        else
            echo "   ⚠️ $dep - $desc (install for enhanced features)"
            optional_deps+=("$dep")
        fi
    done

    if (( ${#missing_deps[@]} > 0 )); then
        echo
        echo "💡 Install missing dependencies:"
        echo "   sudo apt update && sudo apt install ${missing_deps[*]}"
    fi

    if (( ${#optional_deps[@]} > 0 )); then
        echo
        echo "💡 Install optional dependencies for enhanced features:"
        echo "   sudo apt install ${optional_deps[*]}"
    fi

    log_diagnostic "Dependency check: ${#missing_deps[@]} missing, ${#optional_deps[@]} optional missing" "INFO"
    return "$([[ ${#missing_deps[@]} -eq 0 ]] && echo 0 || echo 1)"
}

# Process and service analysis
check_processes_and_services() {
    echo
    echo "⚙️ Process and Service Analysis:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if is_server_up; then
        echo "✅ tModLoader server is running"

        local pid
        pid=$(pgrep -f "tModLoader" | head -1)
        if [[ -n "$pid" ]]; then
            echo "   📊 PID: $pid"
            local process_info
            process_info=$(ps -p "$pid" -o pid,ppid,vsz,rss,pcpu,pmem,etime --no-headers 2>/dev/null)
            if [[ -n "$process_info" ]]; then
                echo "   📋 Process details:"
                echo "      $(echo "$process_info" | awk '{printf "VSZ: %sMB, RSS: %sMB, CPU: %s%%, MEM: %s%%, Runtime: %s", $3/1024, $4/1024, $5, $6, $7}')"
            fi

            local server_info
            server_info=$(get_server_info)
            if [[ "$server_info" != "not_running" ]]; then
                local cpu mem uptime
                read -r cpu mem uptime <<< "$server_info"
                echo "   📈 CPU: ${cpu}% | Memory: ${mem}% | Uptime: ${uptime}m"
            fi

            # Comprehensive mode: dump full ps snapshot
            if [[ "$COMPREHENSIVE_MODE" == "true" ]]; then
                echo
                echo "   📋 Full process snapshot:"
                ps -p "$pid" -o pid,ppid,user,vsz,rss,pcpu,pmem,etime,cmd --no-headers 2>/dev/null \
                    | sed 's/^/      /'
            fi
        fi
    else
        echo "⚠️ tModLoader server is not running"

        local orphaned
        orphaned=$(pgrep -f "tModLoader\|dotnet.*tModLoader" | wc -l)
        if [[ $orphaned -gt 0 ]]; then
            echo "   ⚠️ Found $orphaned potentially orphaned tModLoader processes"
            pgrep -f "tModLoader\|dotnet.*tModLoader" | while read -r pid; do
                echo "      PID $pid: $(ps -p "$pid" -o cmd --no-headers 2>/dev/null || echo 'Process not found')"
            done
        fi
    fi

    echo
    echo "🖥️ Screen Sessions:"
    if command -v screen >/dev/null 2>&1; then
        local screen_count
        screen_count=$(screen -list 2>/dev/null | grep -c "tmodloader" || echo "0")
        if [[ $screen_count -gt 0 ]]; then
            echo "   ✅ Found $screen_count tModLoader screen session(s)"
            screen -list 2>/dev/null | grep "tmodloader" | sed 's/^/      /'
        else
            echo "   ℹ️ No tModLoader screen sessions found"
        fi

        if screen -dmS test_diagnostic_$$ echo "test" 2>/dev/null; then
            echo "   ✅ Screen functionality working"
            screen -S "test_diagnostic_$$" -X quit 2>/dev/null
        else
            echo "   ❌ Screen functionality failed"
            log_diagnostic "Screen functionality test failed" "ERROR"
        fi
    else
        echo "   ❌ Screen not available"
    fi

    echo
    echo "📊 System Resource Status:"

    local memory_info total_mem used_mem mem_percent
    memory_info=$(free -m)
    total_mem=$(echo "$memory_info" | awk '/^Mem:/ {print $2}')
    used_mem=$(echo "$memory_info" | awk '/^Mem:/ {print $3}')
    mem_percent=$((used_mem * 100 / total_mem))

    if [[ $mem_percent -lt 70 ]]; then
        echo "   ✅ Memory usage: ${mem_percent}% (${used_mem}MB/${total_mem}MB)"
    elif [[ $mem_percent -lt 85 ]]; then
        echo "   ⚠️ Memory usage: ${mem_percent}% (${used_mem}MB/${total_mem}MB) - High"
    else
        echo "   ❌ Memory usage: ${mem_percent}% (${used_mem}MB/${total_mem}MB) - Critical"
        log_diagnostic "High memory usage: ${mem_percent}%" "WARN"
    fi

    local load_avg cpu_count load_percent
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | tr -d ' ')
    cpu_count=$(nproc)
    load_percent=$(echo "$load_avg $cpu_count" | awk '{printf "%.0f", ($1/$2)*100}')

    if [[ $load_percent -lt 70 ]]; then
        echo "   ✅ Load average: $load_avg (${load_percent}% of $cpu_count cores)"
    elif [[ $load_percent -lt 100 ]]; then
        echo "   ⚠️ Load average: $load_avg (${load_percent}% of $cpu_count cores) - High"
    else
        echo "   ❌ Load average: $load_avg (${load_percent}% of $cpu_count cores) - Overloaded"
        log_diagnostic "High system load: $load_avg" "WARN"
    fi
}

# Network connectivity tests
check_network_connectivity() {
    echo
    echo "🌐 Network Connectivity Analysis:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    echo "📡 Basic Connectivity:"
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        echo "   ✅ Internet connectivity (8.8.8.8)"
    else
        echo "   ❌ No internet connectivity"
        log_diagnostic "No internet connectivity" "ERROR"
    fi

    echo
    echo "🎮 Gaming Service Connectivity:"
    local services=(
        "steamcommunity.com:443:Steam Community"
        "api.steampowered.com:443:Steam API"
        "terraria.org:443:Terraria Official"
    )

    for service_info in "${services[@]}"; do
        local host="${service_info%%:*}"
        local port="${service_info#*:}"; port="${port%:*}"
        local desc="${service_info##*:}"

        if timeout 5 bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
            echo "   ✅ $desc ($host:$port)"
        else
            echo "   ⚠️ $desc ($host:$port) - Cannot connect"
        fi
    done

    if [[ -n "${DISCORD_WEBHOOK_URL:-}" ]]; then
        echo
        echo "💬 Discord Integration:"
        if curl -sf --max-time 10 "$DISCORD_WEBHOOK_URL" >/dev/null 2>&1; then
            echo "   ✅ Discord webhook accessible"
        else
            echo "   ⚠️ Discord webhook not accessible"
            log_diagnostic "Discord webhook connectivity failed" "WARN"
        fi
    fi

    echo
    echo "🔌 Port Availability:"
    local server_port="7777"
    if [[ -f "$BASE_DIR/Configs/serverconfig.txt" ]]; then
        local config_port
        config_port=$(grep "^port=" "$BASE_DIR/Configs/serverconfig.txt" 2>/dev/null | cut -d'=' -f2)
        [[ -n "$config_port" ]] && server_port="$config_port"
    fi

    echo "   🔍 Checking server port: $server_port"
    if ss -tuln 2>/dev/null | grep -q ":$server_port " || netstat -tuln 2>/dev/null | grep -q ":$server_port "; then
        echo "   ✅ Port $server_port is in use (server likely running)"
    else
        echo "   ℹ️ Port $server_port is available (server not running or different port)"
    fi
}

# Log file analysis
analyze_logs() {
    echo
    echo "📋 Log File Analysis:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local log_files=(
        "$LOG_DIR/server.log:Server Log"
        "$LOG_DIR/tmod.log:Management Log"
        "$LOG_DIR/backup.log:Backup Log"
        "$LOG_DIR/monitor.log:Monitor Log"
        "$LOG_DIR/workshop.log:Workshop Log"
        "$LOG_DIR/dependency.log:Dependency Log"
        "$DIAGNOSTIC_LOG:Diagnostic Log"
    )

    for log_info in "${log_files[@]}"; do
        local log_file="${log_info%:*}"
        local log_desc="${log_info#*:}"

        if [[ -f "$log_file" ]]; then
            local log_size log_lines last_modified
            log_size=$(du -h "$log_file" | cut -f1)
            log_lines=$(wc -l < "$log_file")
            last_modified=$(date -r "$log_file" '+%Y-%m-%d %H:%M:%S')
            echo "   ✅ $log_desc: $log_size ($log_lines lines, modified: $last_modified)"

            if [[ "$COMPREHENSIVE_MODE" == "true" ]]; then
                local error_count warn_count
                error_count=$(tail -100 "$log_file" | grep -ci "error\|fail\|critical" 2>/dev/null || echo 0)
                warn_count=$(tail -100 "$log_file" | grep -ci "warn\|warning" 2>/dev/null || echo 0)
                if [[ $error_count -gt 0 || $warn_count -gt 0 ]]; then
                    echo "      📊 Recent issues: $error_count errors, $warn_count warnings"
                fi
            fi
        else
            echo "   ⚠️ $log_desc: Not found ($log_file)"
        fi
    done

    echo
    echo "💾 Log Storage Analysis:"
    local log_dir_size
    log_dir_size=$(du -sh "$LOG_DIR" 2>/dev/null | cut -f1)
    echo "   📊 Total log directory size: $log_dir_size"

    find "$LOG_DIR" -name "*.log" -size +50M 2>/dev/null | while read -r large_log; do
        local size
        size=$(du -h "$large_log" | cut -f1)
        echo "   ⚠️ Large log file: $(basename "$large_log") ($size)"
        log_diagnostic "Large log file detected: $large_log ($size)" "WARN"
    done
}

# Script system check - matches actual directory structure
check_script_system() {
    echo
    echo "📜 Script Management System Analysis:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local script_errors=0
    local script_warnings=0
    local scripts_base="$BASE_DIR/Scripts"

    # Actual scripts keyed by relative path from scripts/
    local all_scripts=(
        "core/tmod-core.sh:Core Functions Library"
        "core/tmod-server.sh:Server Control"
        "core/tmod-monitor.sh:Monitoring System"
        "hub/tmod-control.sh:Unified Control System"
        "backup/tmod-backup.sh:Backup System"
        "steam/tmod-workshop.sh:Workshop Manager"
        "steam/tmod-deps.sh:Dependency Manager"
        "diag/tmod-diagnostics.sh:Diagnostics"
    )

    echo "📋 Management Scripts:"
    for script_info in "${all_scripts[@]}"; do
        local rel_path="${script_info%:*}"
        local desc="${script_info#*:}"
        local script_path="$scripts_base/$rel_path"
        local script_name
        script_name=$(basename "$rel_path")

        if [[ -f "$script_path" ]]; then
            if [[ -x "$script_path" ]]; then
                echo "   ✅ $rel_path - $desc"

                if [[ "$COMPREHENSIVE_MODE" == "true" ]]; then
                    if bash -n "$script_path" 2>/dev/null; then
                        echo "      ✅ Syntax valid"
                    else
                        echo "      ❌ Syntax errors detected"
                        ((script_errors++))
                        log_diagnostic "Syntax error in script: $script_name" "ERROR"
                    fi
                fi
            else
                echo "   ⚠️ $rel_path - Not executable"
                ((script_warnings++))
                log_diagnostic "Script not executable: $script_name" "WARN"
            fi
        else
            echo "   ❌ $rel_path - Missing"
            ((script_errors++))
            log_diagnostic "Missing script: $script_name" "ERROR"
        fi
    done

    # Config files
    echo
    echo "📋 Configuration Files:"

    local env_file="$scripts_base/env.sh"
    if [[ -f "$env_file" ]]; then
        echo "   ✅ env.sh - Environment configuration"
        if bash -n "$env_file" 2>/dev/null; then
            echo "      ✅ Syntax valid"
        else
            echo "      ❌ Syntax errors detected"
            ((script_errors++))
            log_diagnostic "Syntax error in env.sh" "ERROR"
        fi
    else
        echo "   ⚠️ env.sh - Not found (optional)"
    fi

    local mod_ids_file="$scripts_base/steam/mod_ids.txt"
    if [[ -f "$mod_ids_file" ]]; then
        local mod_count
        mod_count=$(grep -vc "^[[:space:]]*#\|^[[:space:]]*$" "$mod_ids_file" 2>/dev/null || echo 0)
        echo "   ✅ steam/mod_ids.txt - Workshop mod IDs ($mod_count configured)"
    else
        echo "   ⚠️ steam/mod_ids.txt - Not found (required for workshop features)"
    fi

    echo
    echo "📊 Script System Summary: $script_errors errors, $script_warnings warnings"
    log_diagnostic "Script system check: $script_errors errors, $script_warnings warnings" "INFO"
    return "$([[ $script_errors -eq 0 ]] && echo 0 || echo 1)"
}

# Security and permissions analysis
check_security() {
    echo
    echo "🔒 Security and Permissions Analysis:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local security_issues=0

    echo "👤 User Security:"
    if [[ $EUID -eq 0 ]]; then
        echo "   ⚠️ Running as root - security risk"
        ((security_issues++))
        log_diagnostic "Running diagnostics as root user" "WARN"
    else
        echo "   ✅ Running as non-root user: $USER"
    fi

    echo
    echo "📁 File Permissions:"
    local sensitive_files=(
        "$BASE_DIR/Scripts/env.sh:600:Environment config"
        "$BASE_DIR/Configs/serverconfig.txt:644:Server config"
    )

    for file_info in "${sensitive_files[@]}"; do
        local file_path="${file_info%%:*}"
        local rest="${file_info#*:}"
        local expected_perms="${rest%:*}"
        local file_desc="${rest#*:}"

        if [[ -f "$file_path" ]]; then
            local actual_perms
            actual_perms=$(stat -c%a "$file_path")
            if [[ "$actual_perms" == "$expected_perms" ]]; then
                echo "   ✅ $file_desc: $actual_perms (secure)"
            else
                echo "   ⚠️ $file_desc: $actual_perms (expected: $expected_perms)"
                ((security_issues++))
                log_diagnostic "Incorrect permissions: $file_path ($actual_perms, expected $expected_perms)" "WARN"
            fi
        fi
    done

    echo
    echo "🔧 Script Permissions:"
    local non_exec_count=0
    while IFS= read -r script; do
        echo "   ⚠️ Not executable: $(basename "$script")"
        ((security_issues++))
        ((non_exec_count++))
        log_diagnostic "Script not executable: $script" "WARN"
    done < <(find "$BASE_DIR/Scripts" -name "tmod-*.sh" -not -executable 2>/dev/null)
    [[ $non_exec_count -eq 0 ]] && echo "   ✅ All scripts are executable"

    echo
    echo "🌐 World-Writable Files Check:"
    local writable_files
    writable_files=$(find "$BASE_DIR" -type f -perm -002 2>/dev/null | head -5)
    if [[ -n "$writable_files" ]]; then
        echo "   ⚠️ Found world-writable files (security risk):"
        while IFS= read -r line; do
            echo "      $line"
        done <<< "$writable_files"
        ((security_issues++))
        log_diagnostic "World-writable files found in $BASE_DIR" "WARN"
    else
        echo "   ✅ No world-writable files found"
    fi

    echo
    echo "💾 Backup Security:"
    if [[ -d "$BASE_DIR/Backups" ]]; then
        local backup_perms
        backup_perms=$(stat -c%a "$BASE_DIR/Backups")
        if [[ "$backup_perms" == "755" || "$backup_perms" == "750" ]]; then
            echo "   ✅ Backup directory permissions: $backup_perms"
        else
            echo "   ⚠️ Backup directory permissions: $backup_perms (recommend 755)"
        fi
    fi

    echo
    echo "📊 Security Summary: $security_issues issues found"
    log_diagnostic "Security check: $security_issues issues found" "INFO"
    return "$([[ $security_issues -eq 0 ]] && echo 0 || echo 1)"
}

# Performance analysis
performance_analysis() {
    echo
    echo "📈 Performance Analysis and Recommendations:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    echo "💿 Storage Performance:"
    local disk_info
    disk_info=$(df -h "$BASE_DIR" | awk 'NR==2 {print $2, $3, $4, $5}')
    echo "   📊 Disk usage: $disk_info"

    local device
    device=$(df "$BASE_DIR" | awk 'NR==2 {print $1}' | sed 's/[0-9]*$//')
    if [[ -f "/sys/block/$(basename "$device")/queue/rotational" ]]; then
        local rotational
        rotational=$(cat "/sys/block/$(basename "$device")/queue/rotational" 2>/dev/null)
        if [[ "$rotational" == "0" ]]; then
            echo "   ✅ Storage type: SSD"
        else
            echo "   ⚠️ Storage type: HDD (consider SSD for better performance)"
        fi
    fi

    echo
    echo "💾 Memory:"
    local total_mem_gb
    total_mem_gb=$(free -g | awk '/^Mem:/ {print $2}')
    if [[ $total_mem_gb -ge 4 ]]; then
        echo "   ✅ System memory: ${total_mem_gb}GB (sufficient)"
    elif [[ $total_mem_gb -ge 2 ]]; then
        echo "   ⚠️ System memory: ${total_mem_gb}GB (minimum - recommend 4GB+)"
    else
        echo "   ❌ System memory: ${total_mem_gb}GB (insufficient - recommend 4GB+)"
        log_diagnostic "Insufficient system memory: ${total_mem_gb}GB" "WARN"
    fi

    if is_server_up; then
        local server_mem
        server_mem=$(ps -p "$(pgrep -f tModLoader | head -1)" -o rss --no-headers 2>/dev/null)
        if [[ -n "$server_mem" ]]; then
            local server_mem_mb=$((server_mem / 1024))
            echo "   📊 Server memory usage: ${server_mem_mb}MB"
            [[ $server_mem_mb -gt 2048 ]] && echo "   ⚠️ High server memory usage - consider optimization"
        fi
    fi

    echo
    echo "📦 Mod Performance:"
    local mod_count
    mod_count=$(find "$BASE_DIR/Mods" -maxdepth 1 -name "*.tmod" 2>/dev/null | wc -l)
    if [[ $mod_count -gt 50 ]]; then
        echo "   ⚠️ High mod count: $mod_count (may impact performance)"
    elif [[ $mod_count -gt 20 ]]; then
        echo "   ⚠️ Moderate mod count: $mod_count (monitor performance)"
    else
        echo "   ✅ Mod count: $mod_count"
    fi

    echo
    echo "💾 Backup Performance:"
    if command -v pigz >/dev/null; then
        echo "   ✅ Parallel compression available (pigz)"
    else
        echo "   ⚠️ Using standard gzip - install pigz for faster backups"
    fi

    echo
    echo "🌐 Network:"
    local server_port="7777"
    if [[ -f "$BASE_DIR/Configs/serverconfig.txt" ]]; then
        local config_port
        config_port=$(grep "^port=" "$BASE_DIR/Configs/serverconfig.txt" 2>/dev/null | cut -d'=' -f2)
        [[ -n "$config_port" ]] && server_port="$config_port"
    fi
    echo "   📊 Server port: $server_port"
    echo "   💡 Ensure port $server_port is forwarded for external access"
}

# Generate diagnostic report to file
generate_report() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local report_file
    report_file="$TEMP_DIR/diagnostic_report_$(date +%Y%m%d_%H%M%S).txt"

    echo
    echo "📄 Generating Comprehensive Diagnostic Report..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    {
        echo "tModLoader Server Diagnostic Report"
        echo "Generated: $timestamp"
        echo "System: $(hostname) ($(whoami))"
        echo "========================================"
        echo

        gather_system_info
        check_directory_structure
        check_tmodloader_binaries
        check_configuration_files
        check_system_dependencies
        check_processes_and_services
        check_network_connectivity
        analyze_logs
        check_script_system
        check_security
        performance_analysis

        echo
        echo "========================================"
        echo "Report completed: $(date '+%Y-%m-%d %H:%M:%S')"

    } | tee "$report_file"

    echo
    echo "✅ Diagnostic report saved: $report_file"
    echo "💡 Share this report when seeking support"

    log_diagnostic "Diagnostic report generated: $report_file" "INFO"
}

# Quick diagnostic
quick_diagnostic() {
    echo "🚀 Quick Diagnostic Mode"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    gather_system_info
    check_directory_structure
    check_tmodloader_binaries

    echo
    if is_server_up; then
        echo "✅ Quick Check: Server is running and basic structure is OK"
    else
        echo "⚠️ Quick Check: Server is not running - run full diagnostic for details"
    fi
}

# Auto-fix common issues
auto_fix() {
    echo "🔧 Auto-Fix Mode - Attempting to resolve common issues..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local fixes_applied=0

    # Create missing BASE_DIR subdirectories
    local required_dirs=("Engine" "Logs" "Worlds" "Mods" "Configs" "Backups")
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$BASE_DIR/$dir" ]]; then
            echo "🔧 Creating missing directory: $BASE_DIR/$dir"
            mkdir -p "$BASE_DIR/$dir"
            ((fixes_applied++))
        fi
    done

    # Create missing scripts subdirectories
    local script_dirs=("core" "hub" "backup" "steam" "diag")
    for dir in "${script_dirs[@]}"; do
        if [[ ! -d "$BASE_DIR/Scripts/$dir" ]]; then
            echo "🔧 Creating missing scripts directory: scripts/$dir"
            mkdir -p "$BASE_DIR/Scripts/$dir"
            ((fixes_applied++))
        fi
    done

    # Fix script permissions
    local fixed_perms=0
    while IFS= read -r script; do
        echo "🔧 Making script executable: $(basename "$script")"
        chmod +x "$script"
        ((fixes_applied++))
        ((fixed_perms++))
    done < <(find "$BASE_DIR/Scripts" -name "tmod-*.sh" -not -executable 2>/dev/null)
    [[ $fixed_perms -gt 0 ]] && echo "   ✅ Fixed permissions on $fixed_perms scripts"

    # Create basic server config if missing
    if [[ ! -f "$BASE_DIR/Configs/serverconfig.txt" ]]; then
        echo "🔧 Creating basic server configuration"
        mkdir -p "$BASE_DIR/Configs"
        if [[ -f "$BASE_DIR/Configs/serverconfig.example.txt" ]]; then
            cp "$BASE_DIR/Configs/serverconfig.example.txt" "$BASE_DIR/Configs/serverconfig.txt"
        else
            cat > "$BASE_DIR/Configs/serverconfig.txt" << 'EOF'
port=7777
maxplayers=8
language=en
upnp=1
steamcmd_path=./Tools/SteamCMD/steamcmd.sh
log_max_size=10M
log_keep_days=14
EOF
        fi
        ((fixes_applied++))
    fi

    echo
    if [[ $fixes_applied -gt 0 ]]; then
        echo "✅ Applied $fixes_applied fixes"
        log_diagnostic "Auto-fix applied $fixes_applied fixes" "INFO"
    else
        echo "ℹ️ No common issues found to fix automatically"
    fi
}

show_help() {
    cat << 'EOF'
🔧 tModLoader System Diagnostics

Usage: ./tmod-diagnostics.sh [command] [options]

Commands:
  full          Complete diagnostic scan (default)
  quick         Quick essential checks only
  report        Generate diagnostic report file
  fix           Attempt to auto-fix common issues
  system        System information only
  directories   Directory structure check only
  binaries      Binary and executable check only
  config        Configuration files check only
  dependencies  System dependencies check only
  processes     Process and service analysis only
  network       Network connectivity tests only
  logs          Log file analysis only
  scripts       Script system check only
  security      Security and permissions analysis only
  performance   Performance analysis only
  help          Show this help message

Options:
  --comprehensive   Enable detailed analysis mode
  --quiet           Suppress stderr output
  --no-log          Disable diagnostic logging

Examples:
  ./tmod-diagnostics.sh              # Full diagnostic
  ./tmod-diagnostics.sh quick        # Quick check
  ./tmod-diagnostics.sh report       # Generate report file
  ./tmod-diagnostics.sh fix          # Auto-fix issues
  ./tmod-diagnostics.sh --comprehensive full
EOF
}

# Cleanup temp files on exit
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Parse flags first
while [[ $# -gt 0 ]]; do
    case $1 in
        --comprehensive) COMPREHENSIVE_MODE=true; shift ;;
        --quiet)         exec 2>/dev/null; shift ;;
        --no-log)        DIAGNOSTIC_LOG="/dev/null"; shift ;;
        *)               break ;;
    esac
done

# Single init call
init_tmod
init_diagnostics

# Main execution
case "${1:-full}" in
    full)
        echo "🔍 tModLoader System Diagnostics"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        gather_system_info
        check_directory_structure
        check_tmodloader_binaries
        check_configuration_files
        check_system_dependencies
        check_processes_and_services
        check_network_connectivity
        analyze_logs
        check_script_system
        check_security
        performance_analysis
        echo
        echo "🏁 Diagnostic scan completed"
        log_diagnostic "Full diagnostic scan completed" "INFO"
        ;;
    quick)        quick_diagnostic ;;
    report)       COMPREHENSIVE_MODE=true; generate_report ;;
    fix)          auto_fix ;;
    system)       gather_system_info ;;
    directories)  check_directory_structure ;;
    binaries)     check_tmodloader_binaries ;;
    config)       check_configuration_files ;;
    dependencies) check_system_dependencies ;;
    processes)    check_processes_and_services ;;
    network)      check_network_connectivity ;;
    logs)         analyze_logs ;;
    scripts)      check_script_system ;;
    security)     check_security ;;
    performance)  performance_analysis ;;
    help|--help|-h) show_help ;;
    *)
        echo "❌ Unknown command: $1"
        echo "Use 'help' for usage information"
        exit 1
        ;;
esac
