#!/bin/bash
# tmod-core.sh - Enhanced core functions library
export TMOD_VERSION="2.5.0"

# Resolve the project root from this shared core script so copied/renamed
# installs work in place without hardcoded paths.
TMOD_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMOD_DEFAULT_BASE_DIR="$(cd "$TMOD_CORE_DIR/../.." && pwd)"
if [[ ! -d "$TMOD_DEFAULT_BASE_DIR/Scripts" || ! -d "$TMOD_DEFAULT_BASE_DIR/Configs" ]]; then
    TMOD_DEFAULT_BASE_DIR="$HOME/servers/tmodloader"
fi

source_if_exists() {
    local file_path="$1"
    if [[ -f "$file_path" ]]; then
        # shellcheck disable=SC1090
        source "$file_path"
    fi
}

# Load environment variables from the detected project root first.
source_if_exists "$TMOD_DEFAULT_BASE_DIR/Scripts/env.sh"
source_if_exists "$TMOD_DEFAULT_BASE_DIR/Configs/.env"

# Set defaults for anything not configured
BASE_DIR="${BASE_DIR:-$TMOD_DEFAULT_BASE_DIR}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/Logs}"
MODS_DIR="${MODS_DIR:-$BASE_DIR/Mods}"
WORKSHOP_DIR="${WORKSHOP_DIR:-$BASE_DIR/Engine/steamapps/workshop/content/1281930}"

expand_path() {
    local path_value="$1"
    path_value="${path_value/#\~/$HOME}"
    if [[ -n "$path_value" && "$path_value" != /* ]]; then
        echo "$BASE_DIR/${path_value#./}"
    else
        echo "$path_value"
    fi
}

get_steamcmd_path() {
    local configured_path
    configured_path="${STEAMCMD_PATH:-$(server_config_get "steamcmd_path" "./Tools/SteamCMD/steamcmd.sh")}"
    expand_path "$configured_path"
}

prepend_env_path() {
    local var_name="$1"
    local new_path="$2"
    [[ -d "$new_path" ]] || return 0

    local current_value="${!var_name:-}"
    case ":$current_value:" in
        *":$new_path:"*) return 0 ;;
    esac

    if [[ -n "$current_value" ]]; then
        printf -v "$var_name" '%s:%s' "$new_path" "$current_value"
    else
        printf -v "$var_name" '%s' "$new_path"
    fi
    export "${var_name?}"
}

configure_steam_runtime_env() {
    local steamcmd_path steamcmd_root
    steamcmd_path=$(get_steamcmd_path)
    steamcmd_root="$(dirname "$steamcmd_path")"

    export SteamAppId=1281930
    export SteamGameId=1281930

    prepend_env_path LD_LIBRARY_PATH "$BASE_DIR/Engine/Libraries/steamworks.net/20.1.0/runtimes/linux-x64/lib/netstandard2.1"
    prepend_env_path LD_LIBRARY_PATH "$steamcmd_root/linux32"
    prepend_env_path PATH "$steamcmd_root"
}

# Parse the required .NET version from tModLoader.runtimeconfig.json
get_required_dotnet_version() {
    local runtimeconfig="$BASE_DIR/Engine/tModLoader.runtimeconfig.json"
    [[ -f "$runtimeconfig" ]] || return 1
    grep -o '"version": "[^"]*"' "$runtimeconfig" | head -1 | grep -o '[0-9][0-9.]*'
}

# Return 0 if the given dotnet binary has the required runtime for tModLoader
dotnet_has_runtime() {
    local dotnet_exe="$1"
    local required_version
    required_version=$(get_required_dotnet_version) || return 1
    "$dotnet_exe" --list-runtimes 2>/dev/null | grep -q "Microsoft.NETCore.App $required_version"
}

has_engine_install_files() {
    [[ -f "$BASE_DIR/Engine/tModLoader.dll" ]] \
        && [[ -f "$BASE_DIR/Engine/tModLoader.runtimeconfig.json" ]] \
        && [[ -f "$BASE_DIR/Engine/LaunchUtils/InstallDotNet.sh" ]]
}

# Find the actual tModLoader binary
find_tmodloader_binary() {
    # Check common binary locations in order of preference
    local binary_paths=(
        # Absolute paths from root
        "$BASE_DIR/tModLoaderServer"
        "$BASE_DIR/tModLoaderServer.bin.x86_64"
        "$BASE_DIR/Engine/tModLoaderServer"
        "$BASE_DIR/Engine/tModLoaderServer.bin.x86_64"
        "$BASE_DIR/dotnet/dotnet $BASE_DIR/tModLoader.dll"
        "$BASE_DIR/Engine/dotnet/dotnet $BASE_DIR/Engine/tModLoader.dll"
        
        # Relative paths from engine directory (where we'll be running)
        "./tModLoaderServer"
        "./tModLoaderServer.bin.x86_64" 
        "./dotnet/dotnet ./tModLoader.dll"
    )
    
    for binary_path in "${binary_paths[@]}"; do
        # Handle dotnet case separately with better validation
        if [[ "$binary_path" == *"dotnet"* ]]; then
            local dotnet_exe="${binary_path%% *}"
            local dll_file="${binary_path##* }"
            
            # Resolve relative paths if needed
            if [[ "$dotnet_exe" == ./* ]]; then
                dotnet_exe="$BASE_DIR/Engine/${dotnet_exe#./}"
            fi
            if [[ "$dll_file" == ./* ]]; then
                dll_file="$BASE_DIR/Engine/${dll_file#./}"
            fi
            
            if [[ -x "$dotnet_exe" && -f "$dll_file" ]]; then
                # Validate the dotnet + dll combination actually works
                if "$dotnet_exe" --info >/dev/null 2>&1; then
                    echo "$binary_path"
                    return 0
                fi
            fi
        else
            local check_path="$binary_path"
            # Resolve relative paths if needed
            if [[ "$check_path" == ./* ]]; then
                check_path="$BASE_DIR/Engine/${check_path#./}"
            fi
            
            if [[ -x "$check_path" ]]; then
                echo "$binary_path"
                return 0
            fi
        fi
    done
    
    # Check system/user dotnet installs as final fallback - validate they have the right runtime
    local dll_path="$BASE_DIR/Engine/tModLoader.dll"
    if [[ -f "$dll_path" ]]; then
        local sys_dotnet
        sys_dotnet=$(command -v dotnet 2>/dev/null)
        for candidate in "$sys_dotnet" "$HOME/.dotnet/dotnet"; do
            if [[ -n "$candidate" && -x "$candidate" ]] && dotnet_has_runtime "$candidate"; then
                echo "$candidate $dll_path"
                return 0
            fi
        done
    fi

    # Nothing found
    echo "Searched locations:" >&2
    for path in "${binary_paths[@]}"; do
        echo "  - $path" >&2
    done
    echo "  - system/user dotnet + $BASE_DIR/Engine/tModLoader.dll (wrong runtime version)" >&2

    return 1
}

# Make sure dirs exist
mkdir -p "$LOG_DIR" "$MODS_DIR"

# Simple logging - no overthinking
# Always writes to log file; prints to stdout only for WARN/ERROR/CRITICAL
# or when TMOD_DEBUG=1 (set by passing --debug to any script).
log_it() {
    local msg="$1"
    local level="${2:-INFO}"
    local line
    line="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $msg"
    echo "$line" >> "$LOG_DIR/tmod.log"
    case "$level" in
        WARN|ERROR|CRITICAL)
            echo "$line" ;;
        *)
            [[ "${TMOD_DEBUG:-0}" == "1" ]] && echo "$line" ;;
    esac
}


# Return the first detected server PID, regardless of whether tModLoader is
# running via the binary or through dotnet.
get_server_pid() {
    local config_path="$BASE_DIR/Configs/serverconfig.txt"
    local pid

    pid=$(pgrep -f -- "-config $config_path" | head -n1 || true)
    if [[ -n "$pid" ]]; then
        echo "$pid"
        return 0
    fi

    return 1
}

# Check if server is running
is_server_up() {
    # Just check if a tModLoader process is running
    if get_server_pid >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Get basic server stats: cpu mem uptime_minutes
get_server_info() {
    local pid
    pid=$(get_server_pid)
    [[ -z "$pid" ]] && { echo "not_running"; return 1; }
    
    # Read CPU and memory into separate variables
    local cpu mem
    read -r cpu mem < <(ps -p "$pid" -o %cpu,%mem --no-headers 2>/dev/null || echo "0.0 0.0")
    
    # Calculate uptime
    local uptime_sec
    uptime_sec=$(($(date +%s) - $(stat -c %Y "/proc/$pid" 2>/dev/null || echo 0)))
    local uptime_min
    uptime_min=$((uptime_sec / 60))
    
    echo "$cpu $mem $uptime_min"
}

# Get current player count by scanning the full server log
# Scans the full log for join/leave events so players who joined more than
# 100 lines ago are not lost.  Returns 0 if the log is absent.
get_player_count() {
    local log_file="$LOG_DIR/server.log"

    if [[ ! -f "$log_file" ]]; then
        echo "0"
        return 0
    fi

    local joins leaves current_players
    joins=$(grep -c "has joined" "$log_file" 2>/dev/null || echo 0)
    leaves=$(grep -c "has left"  "$log_file" 2>/dev/null || echo 0)

    # Sanitize: ensure we have valid single integers
    joins=${joins//[^0-9]/}
    leaves=${leaves//[^0-9]/}
    [[ -z "$joins"  ]] && joins=0
    [[ -z "$leaves" ]] && leaves=0

    current_players=$((joins - leaves))
    [[ $current_players -lt 0 ]] && current_players=0

    echo "$current_players"
}

# Read a key=value from serverconfig.txt (ignores inline comments and whitespace)
server_config_get() {
    local key="$1"
    local default="${2:-}"
    local config="$BASE_DIR/Configs/serverconfig.txt"
    local val
    val=$(grep -m1 "^[[:space:]]*${key}=" "$config" 2>/dev/null \
        | cut -d'=' -f2- \
        | sed 's/[[:space:]]*#.*//' \
        | xargs)
    val="${val:-$default}"
    # Expand leading ~ to $HOME
    echo "${val/#\~/$HOME}"
}

server_config_set() {
    local key="$1"
    local value="$2"
    local config="$BASE_DIR/Configs/serverconfig.txt"

    mkdir -p "$(dirname "$config")"
    [[ ! -f "$config" ]] && touch "$config"

    if grep -q "^${key}=" "$config" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$config"
    else
        echo "${key}=${value}" >> "$config"
    fi
}

# Rotate logs based on serverconfig.txt thresholds
# log_max_size  - rotate logs larger than this  (default: 10M)
# log_keep_days - delete compressed logs older than N days (default: 14)
rotate_logs() {
    local max_size keep_days
    max_size=$(server_config_get "log_max_size"  "10M")
    keep_days=$(server_config_get "log_keep_days" "14")

    # Rotate oversized logs (worldgen.log excluded — one-time file)
    while IFS= read -r log; do
        local ts base
        ts=$(date '+%Y%m%d_%H%M%S')
        base="${log%.log}"
        mv "$log" "${base}_${ts}.log.old"
        gzip "${base}_${ts}.log.old"
    done < <(find "$LOG_DIR" -maxdepth 1 -name "*.log" \
        -not -name "worldgen.log" \
        -size "+${max_size}" 2>/dev/null)

    # Delete old compressed logs
    find "$LOG_DIR" -maxdepth 1 -name "*.log.old.gz" -mtime "+${keep_days}" -delete 2>/dev/null
}

# Kill server processes - make sure it's dead
kill_server_hard() {
    screen -S tmodloader_server -X quit 2>/dev/null
    pkill -f "tModLoader" 2>/dev/null
    sleep 2
    pkill -9 -f "tModLoader" 2>/dev/null
}

# Install the correct .NET runtime for tModLoader into engine/dotnet/ if needed
ensure_dotnet_runtime() {
    local dotnet_dir="$BASE_DIR/Engine/dotnet"

    # Already installed and has the right runtime
    if [[ -x "$dotnet_dir/dotnet" ]] && dotnet_has_runtime "$dotnet_dir/dotnet"; then
        return 0
    fi

    local required_version
    required_version=$(get_required_dotnet_version)
    if [[ -z "$required_version" ]]; then
        log_it "Cannot determine required .NET version from runtimeconfig.json" "ERROR"
        return 1
    fi

    local install_script="$BASE_DIR/Engine/LaunchUtils/InstallDotNet.sh"
    if [[ ! -f "$install_script" ]]; then
        log_it "InstallDotNet.sh not found at $install_script" "ERROR"
        return 1
    fi

    log_it "Installing .NET $required_version to $dotnet_dir (this may take a few minutes)..." "INFO"
    (
        export dotnet_dir
        export dotnet_version="$required_version"
        export _uname; _uname=$(uname)
        export _arch; _arch=$(uname -m)
        bash "$install_script"
    ) >> "$LOG_DIR/dotnet-install.log" 2>&1

    if [[ -x "$dotnet_dir/dotnet" ]]; then
        log_it "Successfully installed .NET $required_version" "INFO"
        return 0
    fi

    log_it "Failed to install .NET $required_version - check $LOG_DIR/dotnet-install.log" "ERROR"
    return 1
}

# Start server in a detached screen session
start_server_screen() {
    # Check if server is already running
    if is_server_up; then
        log_it "Server is already running" "WARN"
        return 0  # Return success since server IS running
    fi
    
    # Clean up any orphaned screen sessions
    screen -S tmodloader_server -X quit 2>/dev/null
    
    # CRITICAL: Change to engine directory for proper assembly loading
    cd "$BASE_DIR/Engine" || {
        log_it "Failed to change to engine directory: $BASE_DIR/Engine" "ERROR"
        return 1
    }
    
    # STEAM WORKSHOP CONFIGURATION
    configure_steam_runtime_env
    log_it "Steam workshop configured for base dir: $BASE_DIR" "INFO"

    # Ensure the correct .NET runtime is installed before searching for binary
    ensure_dotnet_runtime || log_it "Could not auto-install .NET runtime - will try existing installs" "WARN"

    # Get the correct binary path
    local tmod_binary
    tmod_binary=$(find_tmodloader_binary 2>/dev/null)
    if [[ -z "$tmod_binary" ]]; then
        log_it "tModLoader binary not found - cannot start server" "ERROR"
        return 1
    fi
    
    log_it "Starting tModLoader with: $tmod_binary" "INFO"
    
    # Ensure log directory exists
    mkdir -p "$LOG_DIR"
    
    # Handle dotnet case vs direct binary
    if [[ "$tmod_binary" == *"dotnet"* ]]; then
        # Use the actual paths found by find_tmodloader_binary
        local dotnet_exe="${tmod_binary%% *}"
        local dll_file="${tmod_binary##* }"
        
        # Validate discovered paths exist, fallback to hardcoded if not
        if [[ ! -x "$dotnet_exe" ]]; then
            log_it "Discovered dotnet not executable, trying fallback: $dotnet_exe" "WARN"
            # Fallback to relative paths from engine directory
            dotnet_exe="./dotnet/dotnet"
        fi
        
        if [[ ! -f "$dll_file" ]]; then
            log_it "Discovered DLL not found, trying fallback: $dll_file" "WARN"
            # Fallback to relative paths from engine directory
            dll_file="./tModLoader.dll"
        fi
        
        # Final validation before starting
        if [[ ! -x "$dotnet_exe" ]]; then
            log_it "Dotnet executable not found or not executable: $dotnet_exe" "ERROR"
            return 1
        fi
        
        if [[ ! -f "$dll_file" ]]; then
            log_it "tModLoader DLL not found: $dll_file" "ERROR"
            return 1
        fi
        
        log_it "Using dotnet: $dotnet_exe with DLL: $dll_file" "INFO"
        
        # Start server in screen - no fallback
        if screen -dmS tmodloader_server \
            "$dotnet_exe" "$dll_file" \
            -server \
            -logpath "$LOG_DIR" \
            -config "$BASE_DIR/Configs/serverconfig.txt" \
            -tmlsavedirectory "$BASE_DIR" 2>/dev/null; then
            log_it "Server started in screen session from engine directory" "INFO"
        else
            log_it "Failed to start server in screen session" "ERROR"
            return 1
        fi
    else
        # Direct binary execution
        # Validate the discovered binary exists
        if [[ ! -x "$tmod_binary" ]]; then
            log_it "Discovered binary not executable: $tmod_binary" "ERROR"
            return 1
        fi
        
        # Start server in screen - no fallback
        if screen -dmS tmodloader_server \
            "$tmod_binary" \
            -server \
            -config "$BASE_DIR/Configs/serverconfig.txt" \
            -tmlsavedirectory "$BASE_DIR" 2>/dev/null; then
            log_it "Server started in screen session" "INFO"
        else
            log_it "Failed to start server in screen session" "ERROR"
            return 1
        fi
    fi
    
    sleep 5  # Wait for process to start
    
    # Check if server process started successfully
    if is_server_up; then
        log_it "Server startup completed successfully" "INFO"
        return 0
    else
        log_it "Server failed to start - no process detected" "ERROR"
        return 1
    fi
}

# Get mod list from directory
get_mod_list() {
    find "$MODS_DIR" -maxdepth 1 -name "*.tmod" -exec basename {} .tmod \; | sort
}

# Get latest workshop mods, keyed by mod name
get_latest_workshop_mods() {
    declare -gA latest_mods
    local modfile modname version
    
    # Validate workshop directory exists
    if [[ ! -d "$WORKSHOP_DIR" ]]; then
        log_it "Workshop directory not found: $WORKSHOP_DIR" "WARN"
        return 1
    fi
    
    while IFS= read -r modfile; do
        [[ ! -f "$modfile" ]] && continue
        modname=$(basename "$modfile" .tmod)
        version=$(basename "$(dirname "$modfile")")
        
        if [[ -z "${latest_mods[$modname]}" || "$version" > "${latest_mods[$modname]#*:}" ]]; then
            latest_mods["$modname"]="$version:$modfile"
        fi
    done < <(find "$WORKSHOP_DIR" -type f -name "*.tmod" 2>/dev/null)
    
    log_it "Found ${#latest_mods[@]} mods in workshop"
    return 0
}

# Version comparison: returns true if v1 > v2 (uses sort -V)
version_gt() {
    local v1=$1
    local v2=$2
    [[ "$(printf "%s\n%s" "$v1" "$v2" | sort -V | tail -n1)" == "$v1" && "$v1" != "$v2" ]]
}

# Extract mod name from a .tmod filepath
get_mod_name() {
    local mod_file="$1"
    [[ ! -f "$mod_file" ]] && return 1

    local filename
    filename=$(basename "$mod_file" .tmod)
    if [[ -n "$filename" && "$filename" != "*" ]]; then
        echo "$filename"
        return 0
    fi

    return 1
}

# Extract version from a .tmod filepath (reads parent dir name)
get_mod_version() {
    local mod_file="$1"
    [[ ! -f "$mod_file" ]] && return 1
    
    # Extract version from directory structure: .../workshop/content/1281930/version/modname.tmod
    local version_dir
    version_dir=$(dirname "$mod_file")
    local version
    version=$(basename "$version_dir")
    
    # Validate it looks like a version (starts with digit)
    if [[ "$version" =~ ^[0-9] ]]; then
        echo "$version"
        return 0
    fi
    
    return 1
}

# Check if a version string is from 2023 or later (server-compatible)
is_compatible_version() {
    local version="$1"
    local year
    
    # This extracts the part of the string before the first dot (the year).
    year="${version%%.*}"

    # Check if the year is a number and is greater than or equal to 2022.
    [[ "$year" =~ ^[0-9]+$ ]] && (( year >= 2023 ))
}

# Validate that all installed .tmod files are non-empty
validate_mod_files() {
    local corrupt_count=0
    local corrupt_files=()
    
    while IFS= read -r modfile; do
        if [[ ! -s "$modfile" ]]; then
            corrupt_files+=("$(basename "$modfile")")
            ((corrupt_count++))
        fi
    done < <(find "$MODS_DIR" -maxdepth 1 -name "*.tmod" 2>/dev/null)
    
    if (( corrupt_count > 0 )); then
        log_it "Found $corrupt_count corrupt mod files: ${corrupt_files[*]}" "ERROR"

        return 1
    fi
    
    return 0
}

# Write enabled.json from the current mods directory
update_enabled_mods() {
    # Args: names of mods that were just newly synced.
    # Only these brand-new mods get auto-enabled.
    # Mods already on disk but absent from enabled.json were intentionally disabled — leave them alone.
    local new_mods=("$@")
    local enabled_file="$MODS_DIR/enabled.json"

    # Load current enabled list
    declare -A currently_enabled
    if [[ -f "$enabled_file" ]] && command -v jq >/dev/null 2>&1; then
        while IFS= read -r name; do
            [[ -n "$name" ]] && currently_enabled["$name"]=1
        done < <(jq -r '.[]' "$enabled_file" 2>/dev/null)
    fi

    # Get all installed mods for cleanup (prune removed mods from enabled list)
    local mods=()
    mapfile -t mods < <(get_mod_list)
    declare -A installed_set
    for mod in "${mods[@]}"; do installed_set["$mod"]=1; done

    local new_enabled=()
    # Keep mods that were enabled before and are still installed
    for mod in "${!currently_enabled[@]}"; do
        [[ -v "installed_set[$mod]" ]] && new_enabled+=("$mod")
    done
    # Auto-enable only newly synced mods that weren't previously tracked
    for mod in "${new_mods[@]}"; do
        if [[ ! -v "currently_enabled[$mod]" ]]; then
            new_enabled+=("$mod")
        fi
    done

    # Backup and write
    [[ -f "$enabled_file" ]] && cp "$enabled_file" "${enabled_file}.bak"

    if command -v jq >/dev/null 2>&1; then
        printf '%s\n' "${new_enabled[@]}" \
            | jq -R -s -c 'split("\n") | del(.[] | select(. == ""))' \
            > "$enabled_file"
    else
        {
            echo "["
            for ((i=0; i<${#new_enabled[@]}; i++)); do
                printf '  "%s"' "${new_enabled[i]}"
                [[ $i -lt $((${#new_enabled[@]} - 1)) ]] && echo "," || echo ""
            done
            echo "]"
        } > "$enabled_file"
    fi

    log_it "Updated enabled.json with ${#new_enabled[@]} mods"
}

# Scan server log for mod load errors and append to mod_errors.log
check_mod_errors() {
    local log_file="$LOG_DIR/server.log"

    if [[ ! -f "$log_file" ]]; then
        echo "  ⚠️  No server log found — start the server first."
        return 0
    fi

    echo "  🔍 Scanning server.log for mod errors..."
    echo

    # Patterns that indicate mod problems
    local hits
    hits=$(grep -E \
        "\[tML\]: An error occurred|ModSortingException|Missing mod:|Disabling Mod:|failed to load|Could not load" \
        "$log_file" 2>/dev/null \
        | grep -v "^\[20[0-9][0-9]-.*\[INFO\]" \
        | tail -30)

    if [[ -z "$hits" ]]; then
        echo "  ✅ No mod errors found in server.log"
        return 0
    fi

    local error_count=0
    while IFS= read -r line; do
        echo "  $line"
        (( error_count++ ))
    done <<< "$hits"

    echo
    echo "  ❌ $error_count line(s) flagged — see above"
    log_it "check_mod_errors: $error_count lines flagged" "WARN"
    return 1
}

# Initialize tmod environment - creates dirs, rotates logs, checks binary
init_tmod() {

    mkdir -p "$LOG_DIR" "$MODS_DIR" "$BASE_DIR/Backups"
    rotate_logs

    # Validate BASE_DIR exists
    if [[ ! -d "$BASE_DIR" ]]; then
        log_it "tModLoader directory not found: $BASE_DIR" "ERROR"
        return 1
    fi

    # Check for tModLoader binary - WARN only, do not hard-fail.
    # Scripts like backup, whitelist, and diagnostics must be able to run
    # even when the binary is absent (e.g. before the engine is installed).
    local tmod_binary
    tmod_binary=$(find_tmodloader_binary 2>/dev/null || true)
    if [[ -z "$tmod_binary" ]]; then
        if has_engine_install_files; then
            log_it "tModLoader engine files detected - local .NET runtime will be installed on first server start" "INFO"
        else
            log_it "tModLoader binary not found - server start/stop features unavailable" "WARN"
        fi
    fi

    # Validate workshop directory if workshop functions will be used
    if [[ ! -d "$WORKSHOP_DIR" ]]; then
        log_it "Workshop directory not found: $WORKSHOP_DIR (workshop features disabled)" "WARN"
    fi

    log_it "tModLoader core initialized at $BASE_DIR${tmod_binary:+ with binary: $tmod_binary}"
    return 0
}
