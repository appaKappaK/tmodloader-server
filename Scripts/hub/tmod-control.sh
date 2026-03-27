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
        echo "❌ Missing or invalid scripts:"
        printf '   %s\n' "${missing_scripts[@]}"
        return 1
    fi
    
    return 0
}

launch_go_tui() {
    local mode="${1:-interactive}"

    case "${TMOD_FORCE_LEGACY_UI:-0}" in
        1|true|TRUE|yes|YES) return 1 ;;
    esac

    case "$mode" in
        classic|legacy|plain|palette|fzf|dialog) return 1 ;;
    esac

    local tui_bin="$BASE_DIR/bin/tmodloader-ui"
    if [[ -x "$tui_bin" ]]; then
        cd "$BASE_DIR" || return 1
        exec "$tui_bin"
    fi

    if command -v go >/dev/null 2>&1 && [[ -f "$BASE_DIR/go.mod" ]]; then
        cd "$BASE_DIR" || return 1
        exec go run .
    fi

    return 1
}

# Enhanced server control functions
start_server() {
    if is_server_up; then
        echo "ℹ️ Server is already running"
        return 0
    fi
    
    echo "🚀 Starting tModLoader server..."
    log_control "Starting server via enhanced control system" "INFO"
    
    if "$SCRIPT_DIR/../core/tmod-server.sh" start; then
        echo "✅ Server start initiated successfully"
        return 0
    else
        echo "❌ Failed to start server"
        log_control "Server start failed" "ERROR"
        return 1
    fi
}

stop_server() {
    if ! is_server_up; then
        echo "ℹ️ Server is not running"
        return 0
    fi
    
    echo "🛑 Stopping tModLoader server..."
    log_control "Stopping server via control system" "INFO"
    
    # Create automatic backup before stopping
    echo "📦 Creating pre-shutdown backup..."
    if "$SCRIPT_DIR/../backup/tmod-backup.sh" worlds >/dev/null 2>&1; then
        echo "✅ Pre-shutdown backup completed"
    else
        echo "⚠️ Pre-shutdown backup failed (continuing with shutdown)"
    fi
    
    if "$SCRIPT_DIR/../core/tmod-server.sh" stop; then
        echo "✅ Server stopped successfully"
        return 0
    else
        echo "❌ Failed to stop server"
        log_control "Server stop failed" "ERROR"
        return 1
    fi
}

restart_server() {
    echo "🔄 Restarting tModLoader server..."
    log_control "Restarting server via control system" "INFO"
    
    if "$SCRIPT_DIR/../core/tmod-server.sh" restart; then
        echo "✅ Server restart completed"
        return 0
    else
        echo "❌ Failed to restart server"
        log_control "Server restart failed" "ERROR"
        return 1
    fi
}

# Enhanced status with comprehensive overview
quick_status() {
    echo "🎮 tModLoader Enhanced Status Overview"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Server status with detailed info
    if is_server_up; then
        echo "Server: 🟢 ONLINE"
        
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
            echo "Mod Status: ✅ No errors"
        else
            echo "Mod Status: ⚠️ Errors detected"
        fi
    else
        echo "Server: 🔴 OFFLINE"
    fi
    
    # System health indicators
    local disk_usage
    disk_usage=$(df "$BASE_DIR" | awk 'NR==2 {print $5}' | sed 's/%//')
    if (( disk_usage > 90 )); then
        echo "Disk: ❌ Critical (${disk_usage}%)"
    elif (( disk_usage > 80 )); then
        echo "Disk: ⚠️ High (${disk_usage}%)"
    else
        echo "Disk: ✅ OK (${disk_usage}%)"
    fi
    
    # Backup status
    if [[ -x "$SCRIPT_DIR/../backup/tmod-backup.sh" ]]; then
        local world_backups
        world_backups=$(find "$BASE_DIR/Backups/Worlds" -name "worlds_*.tar.gz" 2>/dev/null | wc -l)
        echo "Backups: $world_backups world backups available"
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ─── World management helpers ─────────────────────────────────────────────────

# World picker page — lists worlds, user selects one, updates serverconfig.txt
# Pass "start" as $1 to also start the server after selecting.
_page_world_picker() {
    local and_start="${1:-}"
    local worlds_dir="$BASE_DIR/Worlds"
    local title="Server  /  Select World"
    [[ "$and_start" == "start" ]] && title="Server  /  Select World & Start"

    local world_files=()
    mapfile -t world_files < <(find "$worlds_dir" -maxdepth 1 -name "*.wld" 2>/dev/null | sort)

    if [[ ${#world_files[@]} -eq 0 ]]; then
        _header "$title"
        _gap
        echo "  No worlds found in $worlds_dir"
        echo "  Use 'Create New World' to generate one first."
        _pause
        return
    fi

    local active_world
    active_world=$(basename "$(server_config_get "world" "" 2>/dev/null)" .wld 2>/dev/null)

    local -a labels=()
    local wld
    for wld in "${world_files[@]}"; do
        local name size mtime marker=""
        name=$(basename "$wld" .wld)
        size=$(du -sh "$wld" 2>/dev/null | cut -f1)
        mtime=$(date -r "$wld" '+%Y-%m-%d %H:%M' 2>/dev/null \
             || stat -c '%y' "$wld" 2>/dev/null | cut -c1-16)
        [[ "$name" == "$active_world" ]] && marker="  ◄ active"
        labels+=("$(printf '%-28s  %6s  %s%s' "$name" "$size" "$mtime" "$marker")")
    done

    local picked_idx
    if ! _pick_index "$title" "Select world" labels picked_idx; then
        return
    fi

    local selected="${world_files[$picked_idx]}"
    local selected_name
    selected_name=$(basename "$selected" .wld)

    server_config_set "world"     "$BASE_DIR/Worlds/${selected_name}.wld"
    server_config_set "worldname" "$selected_name"

    echo "  ✅ Active world set to: $selected_name"
    log_control "Active world changed to: $selected_name" "INFO"

    if [[ "$and_start" == "start" ]]; then
        echo
        start_server
    fi
    _pause
}

# World importer — copy a pre-uploaded .wld into Worlds/, rename, set active
_page_world_importer() {
    _header "Server  /  Import World"
    _gap
    echo "  Transfer your .wld to the server first (SCP / SFTP / rsync),"
    echo "  then paste the full path below."
    echo
    echo "  Example:  scp MyWorld.wld plex@server:~/MyWorld.wld"
    _gap
    read -p "  Path to .wld file: " -r src_path
    echo

    # Expand ~ if typed
    src_path="${src_path/#\~/$HOME}"

    if [[ -z "$src_path" ]]; then
        echo "  Cancelled."; sleep 1; return
    fi

    if [[ ! -f "$src_path" ]]; then
        echo "  ❌ File not found: $src_path"; _pause; return
    fi

    if [[ "${src_path##*.}" != "wld" ]]; then
        echo "  ❌ Not a .wld file: $(basename "$src_path")"; _pause; return
    fi

    local src_name
    src_name=$(basename "$src_path" .wld)

    read -p "  World name (Enter to keep '$src_name'): " -r new_name
    echo
    [[ -z "$new_name" ]] && new_name="$src_name"
    new_name="${new_name//[\/.]/_}"

    local dest="$BASE_DIR/Worlds/${new_name}.wld"

    if [[ -f "$dest" ]]; then
        echo "  ⚠️  '$new_name' already exists in Worlds/"
        read -p "  Overwrite? Type YES to confirm: " -r confirm
        echo
        [[ "$confirm" != "YES" ]] && { echo "  Cancelled."; sleep 1; return; }
    fi

    echo "  Copying..."
    if cp "$src_path" "$dest"; then
        local size
        size=$(du -sh "$dest" 2>/dev/null | cut -f1)
        echo "  ✅ Imported: $new_name  ($size)"
        log_control "World imported: $new_name (from $src_path)" "INFO"
    else
        echo "  ❌ Copy failed — check permissions."; _pause; return
    fi

    echo
    read -p "  Set '$new_name' as active world? (yes/no): " -r set_active
    echo
    if [[ "$set_active" == "yes" ]]; then
        server_config_set "world"     "$BASE_DIR/Worlds/${new_name}.wld"
        server_config_set "worldname" "$new_name"
        echo "  ✅ Active world set to: $new_name"
        log_control "Active world set to: $new_name" "INFO"
        echo
        read -p "  Start server with '$new_name' now? (yes/no): " -r do_start
        echo
        [[ "$do_start" == "yes" ]] && start_server
    fi

    _pause
}

# World creator page — prompts for config, generates world via tModLoader autocreate
_page_world_creator() {
    _header "Server  /  Create World"
    _gap

    # ── World name ──────────────────────────────────────────────────────────────
    read -p "  World name: " -r world_name
    echo
    if [[ -z "$world_name" ]]; then
        echo "  Cancelled."
        sleep 1
        return
    fi

    # Sanitise — no slashes, no dots
    world_name="${world_name//[\/.]/_}"

    if [[ -f "$BASE_DIR/Worlds/${world_name}.wld" ]]; then
        echo "  ⚠️  '$world_name' already exists."
        read -p "  Overwrite? Type YES to confirm: " -r confirm
        [[ "$confirm" != "YES" ]] && { echo "  Cancelled."; sleep 1; return; }
    fi

    # ── Size ────────────────────────────────────────────────────────────────────
    echo "  World size:"
    _item 1 "Small"
    _item 2 "Medium"
    _item 3 "Large"
    _gap
    read -p "  Select [1-3] (default 2): " -r size_choice
    echo
    local autocreate_size
    case "$size_choice" in
        1) autocreate_size=1 ;;
        3) autocreate_size=3 ;;
        *) autocreate_size=2 ;;
    esac

    # ── Difficulty ──────────────────────────────────────────────────────────────
    echo "  Difficulty:"
    _item 0 "Classic"
    _item 1 "Expert"
    _item 2 "Master"
    _item 3 "Journey"
    _gap
    read -p "  Select [0-3] (default 0): " -r diff_choice
    echo
    local difficulty
    case "$diff_choice" in
        1) difficulty=1 ;;
        2) difficulty=2 ;;
        3) difficulty=3 ;;
        *) difficulty=0 ;;
    esac

    # ── Seed ────────────────────────────────────────────────────────────────────
    read -p "  Seed (leave blank for random): " -r seed_input
    echo

    # ── Summary + confirm ───────────────────────────────────────────────────────
    local size_name diff_name
    case "$autocreate_size" in 1) size_name="Small" ;; 2) size_name="Medium" ;; 3) size_name="Large" ;; esac
    case "$difficulty"      in 0) diff_name="Classic" ;; 1) diff_name="Expert" ;; 2) diff_name="Master" ;; 3) diff_name="Journey" ;; esac

    echo "  ── Summary ─────────────────────────────────────────────"
    printf "  %-12s %s\n" "Name:"       "$world_name"
    printf "  %-12s %s\n" "Size:"       "$size_name"
    printf "  %-12s %s\n" "Difficulty:" "$diff_name"
    [[ -n "$seed_input" ]] && printf "  %-12s %s\n" "Seed:" "$seed_input"
    echo "  ────────────────────────────────────────────────────────"
    _gap
    read -p "  Generate this world? Type YES to confirm: " -r confirm
    echo
    if [[ "$confirm" != "YES" ]]; then
        echo "  Cancelled."
        sleep 1
        return
    fi

    # ── Find binary ─────────────────────────────────────────────────────────────
    local tmod_binary
    tmod_binary=$(find_tmodloader_binary 2>/dev/null)
    if [[ -z "$tmod_binary" ]]; then
        echo "  ❌ tModLoader binary not found — cannot generate world"
        log_control "World creation failed: binary not found" "ERROR"
        _pause
        return 1
    fi

    # ── Build arg list ──────────────────────────────────────────────────────────
    local gen_args=(
        -server
        -logpath      "$LOG_DIR"
        -tmlsavedirectory "$BASE_DIR"
        -world        "$BASE_DIR/Worlds/${world_name}.wld"
        -autocreate   "$autocreate_size"
        -worldname    "$world_name"
        -difficulty   "$difficulty"
    )
    [[ -n "$seed_input" ]] && gen_args+=(-seed "$seed_input")

    # ── Launch in temp screen session ───────────────────────────────────────────
    local gen_log="$LOG_DIR/worldgen.log"
    : > "$gen_log"

    mkdir -p "$BASE_DIR/Worlds"
    cd "$BASE_DIR/Engine" 2>/dev/null || true

    configure_steam_runtime_env

    if [[ "$tmod_binary" == *"dotnet"* ]]; then
        local dotnet_exe="${tmod_binary%% *}"
        local dll_file="${tmod_binary##* }"
        screen -L -Logfile "$gen_log" -dmS tmod_worldgen \
            "$dotnet_exe" "$dll_file" "${gen_args[@]}" 2>/dev/null
    else
        screen -L -Logfile "$gen_log" -dmS tmod_worldgen \
            "$tmod_binary" "${gen_args[@]}" 2>/dev/null
    fi

    echo "  🌍 Generating '$world_name'...  (Ctrl+C to cancel, 5 min timeout)"
    echo "  ────────────────────────────────────────────────────────"

    # ── Monitor for completion ──────────────────────────────────────────────────
    # tModLoader prints "Listening on port" when the server is ready — at that
    # point world generation is complete and we can shut down the gen session.
    local timeout=300
    local elapsed=0
    local done=false

    while (( elapsed < timeout )); do
        if grep -qi "listening on port\|server started" "$gen_log" 2>/dev/null; then
            done=true
            break
        fi

        # Show a simple elapsed counter in place
        printf "  ⏳ %ds elapsed...\r" "$elapsed"

        sleep 3
        (( elapsed += 3 ))

        # If the screen session already exited on its own, stop waiting
        if ! screen -list 2>/dev/null | grep -q "tmod_worldgen"; then
            break
        fi
    done

    # Kill the worldgen server — we only needed it to generate the file
    screen -S tmod_worldgen -X quit 2>/dev/null
    sleep 1
    echo

    # ── Result ──────────────────────────────────────────────────────────────────
    if [[ "$done" == "true" ]] || [[ -f "$BASE_DIR/Worlds/${world_name}.wld" ]]; then
        echo "  ✅ World '$world_name' created successfully!"
        log_control "World created: $world_name (${size_name}, ${diff_name})" "INFO"

        _gap
        read -p "  Set '$world_name' as active world? (yes/no): " -r set_active
        echo
        if [[ "$set_active" == "yes" ]]; then
            server_config_set "world"     "$BASE_DIR/Worlds/${world_name}.wld"
            server_config_set "worldname" "$world_name"
            echo "  ✅ Active world set to: $world_name"
            log_control "Active world set to: $world_name" "INFO"
        fi
    else
        echo "  ❌ World generation failed or timed out after ${elapsed}s"
        echo "  Check $gen_log for details"
        log_control "World generation failed/timed out: $world_name" "ERROR"
    fi

    _pause
}

# ─── Shared UI helpers ────────────────────────────────────────────────────────
_SEP="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

_use_fzf_ui() {
    local mode="${TMOD_UI_MODE:-auto}"
    case "$mode" in
        classic|legacy|plain) return 1 ;;
        auto|fzf)
            [[ -t 0 && -t 1 ]] || return 1
            command -v fzf >/dev/null 2>&1
            ;;
        *) return 1 ;;
    esac
}

_use_dialog_ui() {
    local mode="${TMOD_UI_MODE:-auto}"
    case "$mode" in
        classic|legacy|plain|fzf) return 1 ;;
        auto|dialog)
            [[ -t 0 && -t 1 ]] || return 1
            command -v dialog >/dev/null 2>&1
            ;;
        *) return 1 ;;
    esac
}

_status_summary_line() {
    local state="OFFLINE"
    is_server_up && state="ONLINE"

    local mod_count
    mod_count=$(get_mod_list | wc -l)

    local active_world
    active_world=$(basename "$(server_config_get "world" "" 2>/dev/null)" .wld 2>/dev/null)
    [[ -z "$active_world" ]] && active_world="none"

    local disk_pct
    disk_pct=$(df "$BASE_DIR" | awk 'NR==2 {print $5}')

    local world_backups=0
    if [[ -d "$BASE_DIR/Backups/Worlds" ]]; then
        world_backups=$(find "$BASE_DIR/Backups/Worlds" -name "worlds_*.tar.gz" 2>/dev/null | wc -l)
    fi

    printf 'State: %s | World: %s | Mods: %s | World Backups: %s | Disk: %s' \
        "$state" "$active_world" "$mod_count" "$world_backups" "$disk_pct"
}

_prompt_add_mods() {
    local ws="$SCRIPT_DIR/../steam/tmod-workshop.sh"
    local added=0

    if [[ ! -x "$ws" ]]; then
        _unavailable "tmod-workshop.sh"
        return 1
    fi

    echo "  Paste Workshop URLs or IDs — blank line when done."
    echo "  (Multiple URLs concatenated on one line are fine)"
    echo

    while true; do
        local input ids
        read -p "  URL(s) or ID(s): " -r input
        [[ -z "$input" ]] && break

        ids=$(echo "$input" | grep -oP '(?<=[?&]id=)[0-9]+')
        if [[ -n "$ids" ]]; then
            while IFS= read -r id; do
                "$ws" mods add "$id" 2>&1 | grep -v "^\[20[0-9][0-9]-" && (( added++ )) || true
            done <<< "$ids"
        else
            "$ws" mods add "$input" 2>&1 | grep -v "^\[20[0-9][0-9]-" && (( added++ )) || true
        fi
    done

    if (( added > 0 )); then
        echo
        if _confirm_action "Mods" "Download and sync $added mod(s) now?"; then
            "$ws" download && "$ws" sync --yes
        fi
    fi
}

_menu_choice() {
    local title="$1"
    local prompt="$2"
    local out_var="$3"
    shift 3

    local -n _out_ref="$out_var"
    _out_ref=""

    if _use_dialog_ui; then
        local dialog_prompt
        dialog_prompt="${prompt}"$'\n\n'"$(_status_summary_line)"
        local item_count=$(( $# / 2 ))
        local menu_height=$item_count
        (( menu_height < 10 )) && menu_height=10
        (( menu_height > 18 )) && menu_height=18

        local selected
        selected=$(dialog --clear --stdout \
            --title "tModLoader / $title" \
            --cancel-label "Back" \
            --menu "$dialog_prompt" 22 96 "$menu_height" "$@")
        local status=$?
        clear
        [[ $status -eq 0 ]] || return 1
        _out_ref="$selected"
        return 0
    fi

    local -a tags=()
    local -a descriptions=()
    while (( $# >= 2 )); do
        tags+=("$1")
        descriptions+=("$2")
        shift 2
    done

    while true; do
        _header "$title"
        _gap
        local idx
        for idx in "${!tags[@]}"; do
            _item "${tags[$idx]}" "${descriptions[$idx]}"
        done
        _gap
        echo "$_SEP"
        read -p "  Select: " -r input
        echo

        case "$input" in
            $'\033') return 1 ;;
        esac

        for idx in "${!tags[@]}"; do
            if [[ "$input" == "${tags[$idx]}" ]]; then
                _out_ref="$input"
                return 0
            fi
        done

        echo "  Invalid option."
        sleep 1
    done
}

_prompt_text() {
    local title="$1"
    local prompt="$2"
    local out_var="$3"
    local initial_value="${4:-}"
    local -n _out_ref="$out_var"

    _out_ref=""

    if _use_dialog_ui; then
        local input
        input=$(dialog --clear --stdout \
            --title "tModLoader / $title" \
            --inputbox "$prompt" 10 90 "$initial_value")
        local status=$?
        clear
        [[ $status -eq 0 ]] || return 1
        _out_ref="$input"
        return 0
    fi

    read -p "  $prompt" -r _out_ref
}

_confirm_action() {
    local title="$1"
    local prompt="$2"
    local rendered_prompt
    rendered_prompt=$(printf '%b' "$prompt")

    if _use_dialog_ui; then
        dialog --clear --title "tModLoader / $title" --yesno "$rendered_prompt" 10 90
        local status=$?
        clear
        return $status
    fi

    local reply
    read -p "  $rendered_prompt [y/N]: " -r reply
    [[ "$reply" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]
}

_show_log_tail() {
    local file_path="$1"
    local title="$2"
    local lines="${3:-50}"

    if _use_dialog_ui; then
        local temp_view
        temp_view=$(mktemp)
        if [[ -f "$file_path" ]]; then
            tail -n "$lines" "$file_path" > "$temp_view"
        else
            printf 'No log found: %s\n' "$file_path" > "$temp_view"
        fi
        dialog --clear --title "tModLoader / $title" --textbox "$temp_view" 24 110
        local status=$?
        rm -f "$temp_view"
        clear
        return $status
    fi

    echo "  ── $title ─────────────────────────────────────────"
    if [[ -f "$file_path" ]]; then
        tail -n "$lines" "$file_path"
    else
        echo "  No log found: $file_path"
    fi
}

_follow_log_file() {
    local file_path="$1"
    local title="$2"

    if _use_dialog_ui; then
        if [[ -f "$file_path" ]]; then
            dialog --clear --title "tModLoader / $title" --tailbox "$file_path" 24 110
        else
            dialog --clear --title "tModLoader / $title" --msgbox "No log found:\n$file_path" 10 90
        fi
        clear
        return 0
    fi

    echo "  ── Following $title — Ctrl+C to stop ──────────────────────"
    if [[ -f "$file_path" ]]; then
        tail -f "$file_path"
    else
        echo "  No log found: $file_path"
    fi
}

_attach_server_console() {
    if screen -list 2>/dev/null | grep -q "tmodloader_server"; then
        echo "  Attaching to server console — Ctrl+A D to detach..."
        sleep 1
        screen -r tmodloader_server
    else
        echo "  ❌ No server screen session found (is the server running?)"
    fi
}

_status_bar() {
    # ── Line 1: server state ───────────────────────────────────────────────────
    local status_icon status_text status_color
    if is_server_up; then
        status_icon="🟢"; status_text="ONLINE";  status_color="\e[32m"
    else
        status_icon="🔴"; status_text="OFFLINE"; status_color="\e[31m"
    fi

    local mod_count enabled_count mod_display
    mod_count=$(get_mod_list | wc -l)
    local _enabled_json="$MODS_DIR/enabled.json"
    if [[ -f "$_enabled_json" ]] && command -v jq >/dev/null 2>&1; then
        enabled_count=$(jq 'length' "$_enabled_json" 2>/dev/null || echo "$mod_count")
    else
        enabled_count="$mod_count"
    fi
    if (( enabled_count == mod_count )); then
        mod_display="${mod_count}"
    else
        mod_display="${enabled_count}/${mod_count}"
    fi

    local line1="  ${status_icon} "
    if is_server_up; then
        local info uptime_min uptime_fmt players
        info=$(get_server_info)
        read -r _ _ uptime_min <<< "$info"
        if (( uptime_min >= 60 )); then
            uptime_fmt=$(printf "%dh %02dm" $((uptime_min/60)) $((uptime_min%60)))
        else
            uptime_fmt="${uptime_min}m"
        fi
        players=$(get_player_count)
        local player_label="players"
        (( players == 1 )) && player_label="player"
        echo -e "${line1}${status_color}${status_text}\e[0m  ⏱ ${uptime_fmt}  👥 ${players} ${player_label}  🧩 ${mod_display} mods"
    else
        echo -e "${line1}${status_color}${status_text}\e[0m  🧩 ${mod_display} mods"
    fi

    # ── Line 2: storage + world ────────────────────────────────────────────────
    local disk_used disk_total disk_pct mods_size worlds_size active_world
    read -r disk_used disk_total disk_pct < <(df -h "$BASE_DIR" \
        | awk 'NR==2 {gsub(/%/,"",$5); print $3, $2, $5}')

    mods_size=$(find "$MODS_DIR" -maxdepth 1 -name "*.tmod" -exec du -shc {} + 2>/dev/null | tail -1 | cut -f1)
    [[ -z "$mods_size" ]] && mods_size="0B"
    worlds_size=$(du -sh "$BASE_DIR/Worlds" 2>/dev/null | cut -f1)
    [[ -z "$worlds_size" ]] && worlds_size="0B"
    active_world=$(basename "$(server_config_get "world" "" 2>/dev/null)" .wld 2>/dev/null)

    local world_label="🌍 no world set"
    [[ -n "$active_world" ]] && world_label="🌍 ${active_world}"

    echo "  ${world_label}  📦 Mods: ${mods_size}  🗺  Worlds: ${worlds_size}  💿 ${disk_used}/${disk_total} (${disk_pct}%)"
}

_header() {
    local title="$1"
    echo "$_SEP"
    echo "  🎮 tModLoader  /  $title"
    echo "$_SEP"
    _status_bar
    echo "$_SEP"
}

_item()  { printf "  %2s)  %s\n" "$1" "$2"; }
_gap()   { echo; }
_pause() { echo; read -p "  Press Enter to continue..." -r; }
_back()  { _item 0 "← Back"; }

_pick_index() {
    local title="$1"
    local prompt="$2"
    local labels_name="$3"
    local out_var="$4"
    local -n _labels_ref="$labels_name"
    local -n _out_ref="$out_var"

    _out_ref=""
    (( ${#_labels_ref[@]} > 0 )) || return 1

    if _use_fzf_ui; then
        local selected
        selected=$(printf '%s\n' "${_labels_ref[@]}" \
            | fzf \
                --height=80% \
                --layout=reverse \
                --border \
                --prompt="${prompt}> " \
                --header="$title")
        [[ -z "$selected" ]] && return 1
        local idx
        for idx in "${!_labels_ref[@]}"; do
            if [[ "${_labels_ref[$idx]}" == "$selected" ]]; then
                _out_ref="$idx"
                return 0
            fi
        done
        return 1
    fi

    if _use_dialog_ui; then
        local -a menu_items=()
        local idx
        for idx in "${!_labels_ref[@]}"; do
            menu_items+=("$idx" "${_labels_ref[$idx]}")
        done

        local selected
        selected=$(dialog --clear --stdout \
            --title "tModLoader / $title" \
            --cancel-label "Back" \
            --menu "$prompt"$'\n\n'"$(_status_summary_line)" 22 110 16 \
            "${menu_items[@]}")
        local status=$?
        clear
        [[ $status -eq 0 ]] || return 1
        _out_ref="$selected"
        return 0
    fi

    local query=""
    local input
    local filtered=()

    while true; do
        _header "$title"
        [[ -n "$query" ]] && { echo "  Filter: $query"; _gap; }

        filtered=()
        local idx
        for idx in "${!_labels_ref[@]}"; do
            local label_lc="${_labels_ref[$idx],,}"
            local query_lc="${query,,}"
            if [[ -z "$query" || "$label_lc" == *"$query_lc"* ]]; then
                filtered+=("$idx")
            fi
        done

        if (( ${#filtered[@]} == 0 )); then
            echo "  No matches."
        else
            local shown=0
            local actual_idx
            for actual_idx in "${filtered[@]}"; do
                printf "  %2d)  %s\n" "$((shown + 1))" "${_labels_ref[$actual_idx]}"
                (( shown++ ))
                if (( shown >= 20 )) && (( ${#filtered[@]} > shown )); then
                    echo "  … refine your filter to narrow the list"
                    break
                fi
            done
        fi

        _gap
        echo "$_SEP"
        read -p "  $prompt (number, text filter, / clear, 0 cancel): " -r input
        echo

        case "$input" in
            0|$'\033') return 1 ;;
            /) query="" ;;
            "")
                if (( ${#filtered[@]} == 1 )); then
                    _out_ref="${filtered[0]}"
                    return 0
                fi
                ;;
            *)
                if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= ${#filtered[@]} )); then
                    _out_ref="${filtered[$((input - 1))]}"
                    return 0
                else
                    query="$input"
                fi
                ;;
        esac
    done
}

_pick_backup_archive() {
    local title="$1"
    local out_var="$2"
    local -n _out_ref="$out_var"
    local backup_root="$BASE_DIR/Backups"
    local -a all_backups=()
    local -a labels=()

    mapfile -t all_backups < <(
        find "$backup_root" -maxdepth 2 -name "*.tar.gz" 2>/dev/null \
            | sort -t/ -k1,1r -k2,2r
    )

    if (( ${#all_backups[@]} == 0 )); then
        echo "  No backups found."
        return 1
    fi

    local f
    for f in "${all_backups[@]}"; do
        local sz rel
        sz=$(du -h "$f" 2>/dev/null | cut -f1)
        rel="${f#"$backup_root"/}"
        labels+=("$(printf '%-48s  %6s' "$rel" "$sz")")
    done

    local picked_idx
    if ! _pick_index "$title" "Select backup" labels picked_idx; then
        return 1
    fi

    _out_ref="${all_backups[$picked_idx]}"
}

_restore_backup_interactive() {
    local bs="$SCRIPT_DIR/../backup/tmod-backup.sh"
    local picked
    if _pick_backup_archive "Restore Backup" picked; then
        "$bs" restore "$picked"
    fi
}

_verify_backup_interactive() {
    local bs="$SCRIPT_DIR/../backup/tmod-backup.sh"
    local picked
    if _pick_backup_archive "Verify Backup" picked; then
        "$bs" verify "$picked"
    fi
}

_unavailable() {
    echo "  ❌ Script not available: $1"
    _pause
}

# ─── Pages ────────────────────────────────────────────────────────────────────

_page_server() {
    while true; do
        local choice
        if ! _menu_choice "Server" "Choose a server action." choice \
            "1" "Show Status" \
            "2" "Start Server" \
            "3" "Stop Server" \
            "4" "Restart Server" \
            "5" "Select Active World" \
            "6" "Start with World Select" \
            "7" "Create New World" \
            "8" "Import World (from uploaded .wld file)" \
            "0" "Back"; then
            return
        fi
        case "$choice" in
            1) quick_status;                       _pause ;;
            2) start_server;                       _pause ;;
            3) stop_server;                        _pause ;;
            4) restart_server;                     _pause ;;
            5) _page_world_picker ;;
            6) _page_world_picker "start" ;;
            7) _page_world_creator ;;
            8) _page_world_importer ;;
            0) return ;;
            $'\033') return ;;
            *) echo "  Invalid option."; sleep 1 ;;
        esac
    done
}

_page_mods() {
    local ws="$SCRIPT_DIR/../steam/tmod-workshop.sh"
    while true; do
        local choice
        if ! _menu_choice "Mods" "Choose a mod or workshop action." choice \
            "1" "Add Mod by URL or ID" \
            "2" "Show mod_ids.txt (queued mods with names)" \
            "3" "Clear mod_ids.txt (fresh start)" \
            "4" "Mod Picker (interactive toggle)" \
            "5" "Enable a Mod" \
            "6" "Disable a Mod" \
            "7" "List Mods (enabled/disabled)" \
            "8" "List Installed Mods" \
            "9" "Check for Errors" \
            "10" "Workshop Status" \
            "11" "List Workshop Downloads" \
            "12" "Archive Old Versions" \
            "13" "Cleanup Downloads" \
            "14" "Mod Configs (edit per-mod settings)" \
            "0" "Back"; then
            return
        fi
        case "$choice" in
            1) if [[ -x "$ws" ]]; then _prompt_add_mods; else _unavailable "tmod-workshop.sh"; fi; _pause ;;
            2) if [[ -x "$ws" ]]; then "$ws" mods ids;      else _unavailable "tmod-workshop.sh"; fi; _pause ;;
            3) if [[ -x "$ws" ]]; then "$ws" mods clear;    else _unavailable "tmod-workshop.sh"; fi; _pause ;;
            4) if [[ -x "$ws" ]]; then "$ws" mods pick;     else _unavailable "tmod-workshop.sh"; fi; _pause ;;
            5) if [[ -x "$ws" ]]; then
                   local m
                   if _prompt_text "Mods" "Mod name to enable (or 'all'):" m && [[ -n "$m" ]]; then
                       "$ws" mods enable "$m"
                   else
                       echo "  No input."
                   fi
               else _unavailable "tmod-workshop.sh"; fi; _pause ;;
            6) if [[ -x "$ws" ]]; then
                   local m
                   if _prompt_text "Mods" "Mod name to disable (or 'all'):" m && [[ -n "$m" ]]; then
                       "$ws" mods disable "$m"
                   else
                       echo "  No input."
                   fi
               else _unavailable "tmod-workshop.sh"; fi; _pause ;;
            7) if [[ -x "$ws" ]]; then "$ws" mods list;     else _unavailable "tmod-workshop.sh"; fi; _pause ;;
            8) get_mod_list;                                                                           _pause ;;
            9) check_mod_errors;                                                                       _pause ;;
            10) if [[ -x "$ws" ]]; then "$ws" status;  else _unavailable "tmod-workshop.sh"; fi; _pause ;;
            11) if [[ -x "$ws" ]]; then "$ws" list;    else _unavailable "tmod-workshop.sh"; fi; _pause ;;
            12) if [[ -x "$ws" ]]; then "$ws" archive; else _unavailable "tmod-workshop.sh"; fi; _pause ;;
            13) if [[ -x "$ws" ]]; then "$ws" cleanup; else _unavailable "tmod-workshop.sh"; fi; _pause ;;
            14) _page_mod_configs ;;
            0) return ;;
            $'\033') return ;;
            *) echo "  Invalid option."; sleep 1 ;;
        esac
    done
}

_page_mod_configs() {
    while true; do
        _header "Mod Configs"
        _gap

        # Scan for config files:
        #   - any file directly inside ModConfigs/
        #   - *.json / *.toml / *.cfg / *.ini inside mod-created subdirs
        #     (skip known system dirs: backups engine logs Mods scripts Worlds ModConfigs)
        local -a cfg_files=()
        mapfile -t cfg_files < <(
            {
                find "$BASE_DIR/ModConfigs" -maxdepth 1 -type f 2>/dev/null
                find "$BASE_DIR" -mindepth 2 -maxdepth 2 -type f \
                    \( -name "*.json" -o -name "*.toml" -o -name "*.cfg" -o -name "*.ini" \) \
                    -not -path "$BASE_DIR/Backups/*" \
                    -not -path "$BASE_DIR/Engine/*" \
                    -not -path "$BASE_DIR/Logs/*" \
                    -not -path "$BASE_DIR/Mods/*" \
                    -not -path "$BASE_DIR/Scripts/*" \
                    -not -path "$BASE_DIR/Worlds/*" \
                    -not -path "$BASE_DIR/ModConfigs/*" \
                    2>/dev/null
            } | sort -u
        )

        if [[ ${#cfg_files[@]} -eq 0 ]]; then
            echo "  No config files found under:"
            echo "  $BASE_DIR"
            _pause
            return
        fi

        local -a labels=()
        local f
        for f in "${cfg_files[@]}"; do
            local relpath size mtime
            relpath="${f#"$BASE_DIR"/}"
            size=$(du -sh "$f" 2>/dev/null | cut -f1)
            mtime=$(stat -c '%y' "$f" 2>/dev/null | cut -d. -f1)
            labels+=("$(printf '%-48s  %4s  %s' "$relpath" "$size" "$mtime")")
        done

        local picked_idx
        if ! _pick_index "Mod Configs" "Select config" labels picked_idx; then
            return
        fi

        nano "${cfg_files[$picked_idx]}"
    done
}

_page_backup() {
    local bs="$SCRIPT_DIR/../backup/tmod-backup.sh"
    while true; do
        local choice
        if ! _menu_choice "Backup" "Choose a backup action." choice \
            "1" "Backup Status" \
            "2" "World Backup" \
            "3" "Config Backup" \
            "4" "Full Server Backup" \
            "5" "Auto Backup (all three)" \
            "6" "List Backups" \
            "7" "Restore from Backup" \
            "8" "Verify a Backup" \
            "9" "Cleanup Old Backups" \
            "10" "View Backup Log" \
            "0" "Back"; then
            return
        fi
        case "$choice" in
            1) if [[ -x "$bs" ]]; then "$bs" status;  else _unavailable "tmod-backup.sh"; fi; _pause ;;
            2) if [[ -x "$bs" ]]; then "$bs" worlds;  else _unavailable "tmod-backup.sh"; fi; _pause ;;
            3) if [[ -x "$bs" ]]; then "$bs" configs; else _unavailable "tmod-backup.sh"; fi; _pause ;;
            4) if [[ -x "$bs" ]]; then "$bs" full;    else _unavailable "tmod-backup.sh"; fi; _pause ;;
            5) if [[ -x "$bs" ]]; then "$bs" auto;    else _unavailable "tmod-backup.sh"; fi; _pause ;;
            6) if [[ -x "$bs" ]]; then "$bs" list;    else _unavailable "tmod-backup.sh"; fi; _pause ;;
            7) if [[ -x "$bs" ]]; then _restore_backup_interactive; else _unavailable "tmod-backup.sh"; fi; _pause ;;
            8) if [[ -x "$bs" ]]; then _verify_backup_interactive;  else _unavailable "tmod-backup.sh"; fi; _pause ;;
            9)  if [[ -x "$bs" ]]; then "$bs" cleanup; else _unavailable "tmod-backup.sh"; fi; _pause ;;
            10) _show_log_tail "$LOG_DIR/backup.log" "Backup Log" 30 ;;
            0) return ;;
            $'\033') return ;;
            *) echo "  Invalid option."; sleep 1 ;;
        esac
    done
}


_page_monitoring() {
    local mon="$SCRIPT_DIR/../core/tmod-monitor.sh"
    while true; do
        local choice
        if ! _menu_choice "Monitoring" "Choose a monitoring action." choice \
            "1" "Status Dashboard" \
            "2" "Health Check (single pass)" \
            "3" "Live Monitor (Ctrl+C to stop)" \
            "4" "Follow Server Log (live stream)" \
            "5" "View Server Log (last 50 lines)" \
            "6" "View Monitor Log" \
            "7" "View Control Log" \
            "8" "Attach to Server Console" \
            "0" "Back"; then
            return
        fi
        case "$choice" in
            1) if [[ -x "$mon" ]]; then "$mon" status;  else _unavailable "tmod-monitor.sh"; fi; _pause ;;
            2) if [[ -x "$mon" ]]; then "$mon" check;   else _unavailable "tmod-monitor.sh"; fi; _pause ;;
            3) if [[ -x "$mon" ]]; then "$mon" monitor; else _unavailable "tmod-monitor.sh"; fi ;;
            4) _follow_log_file "$LOG_DIR/server.log" "Server Log" ;;
            5) _show_log_tail "$LOG_DIR/server.log" "Server Log" 50 ;;
            6) if [[ -x "$mon" ]]; then "$mon" logs;    else _unavailable "tmod-monitor.sh"; fi; _pause ;;
            7) _show_log_tail "$MAIN_LOG" "Control Log" 30 ;;
            8) _attach_server_console; _pause ;;
            0) return ;;
            $'\033') return ;;
            *) echo "  Invalid option."; sleep 1 ;;
        esac
    done
}

_update_engine() {
    local steamcmd
    steamcmd="$(get_steamcmd_path)"
    local engine_dir="$BASE_DIR/Engine"
    local steam_user="${STEAM_USERNAME:-}"

    if [[ ! -f "$steamcmd" ]]; then
        echo "  ❌ SteamCMD not found at: $steamcmd"
        return 1
    fi

    if [[ -z "$steam_user" ]]; then
        echo "  ⚠️  tModLoader engine downloads require a Steam account that owns Terraria."
        echo "  💡 For a public no-login install, you can also run: make engine-github"
        echo "  💡 Set STEAM_USERNAME in Scripts/env.sh or enter it now."
        if ! _prompt_text "Maintenance" "Steam username:" steam_user; then
            echo "  Cancelled."
            return 1
        fi
        if [[ -z "$steam_user" ]]; then
            echo "  Cancelled."
            return 1
        fi
    fi

    local current_build
    current_build=$(grep '"buildid"' "$engine_dir/steamapps/appmanifest_1281930.acf" 2>/dev/null | grep -o '[0-9]*' | head -1)
    echo "  Current build: ${current_build:-unknown}"

    if is_server_up; then
        echo "  ⚠️  Server is running. Stop it before updating."
        if ! _confirm_action "Maintenance" "Stop the server and continue with the engine update?"; then
            echo "  Cancelled."
            return 0
        fi
        stop_server
        sleep 2
    fi

    echo "  Updating tModLoader engine (app 1281930)..."
    "$steamcmd" \
        +force_install_dir "$engine_dir" \
        +login "$steam_user" \
        +app_update 1281930 \
        +quit

    if [[ ! -f "$engine_dir/steamapps/appmanifest_1281930.acf" ]]; then
        echo "  ❌ Engine install did not produce appmanifest_1281930.acf"
        echo "  💡 Make sure the Steam account owns Terraria and completed any password/Steam Guard prompt."
        echo "  💡 Or use the GitHub release path instead: make engine-github"
        log_control "Engine update failed: no appmanifest_1281930.acf after SteamCMD run" "ERROR"
        return 1
    fi

    local new_build
    new_build=$(grep '"buildid"' "$engine_dir/steamapps/appmanifest_1281930.acf" 2>/dev/null | grep -o '[0-9]*' | head -1)
    if [[ "$new_build" != "$current_build" ]]; then
        echo "  ✅ Updated: build $current_build → $new_build"
        log_control "Engine updated: build $current_build -> $new_build" "INFO"
    else
        echo "  ✅ Engine is already up to date (build $new_build)"
        log_control "Engine up to date: build $new_build" "INFO"
    fi
}

_page_maintenance() {
    local diag="$SCRIPT_DIR/../diag/tmod-diagnostics.sh"
    while true; do
        local choice
        if ! _menu_choice "Maintenance" "Choose a maintenance action." choice \
            "1" "System Diagnostics" \
            "2" "Run All Maintenance Tasks" \
            "3" "Update Engine" \
            "4" "Emergency Shutdown" \
            "0" "Back"; then
            return
        fi
        case "$choice" in
            1) if [[ -x "$diag" ]]; then "$diag" full; else _unavailable "tmod-diagnostics.sh"; fi; _pause ;;
            2) run_maintenance; _pause ;;
            3) _update_engine; _pause ;;
            4) if _confirm_action "Maintenance" "Force-kill the server immediately?\n\nThis is only for emergencies."; then
                   emergency_shutdown
               else
                   echo "  Cancelled."
               fi
               _pause ;;
            0) return ;;
            $'\033') return ;;
            *) echo "  Invalid option."; sleep 1 ;;
        esac
    done
}

# ─── Main menu ────────────────────────────────────────────────────────────────
show_classic_menu() {
    while true; do
        local choice
        if ! _menu_choice "Main Menu" "Choose an area." choice \
            "1" "Server        start / stop / restart / status" \
            "2" "Mods          add, enable, manage, workshop" \
            "3" "Monitoring    dashboard, logs, console" \
            "4" "Backup        create, restore, verify, cleanup" \
            "5" "Maintenance   diagnostics, emergency shutdown" \
            "0" "Exit"; then
            echo "  Goodbye!"
            log_control "Control system session ended" "INFO"
            exit 0
        fi
        case "$choice" in
            1) _page_server ;;
            2) _page_mods ;;
            3) _page_monitoring ;;
            4) _page_backup ;;
            5) _page_maintenance ;;
            0) echo "  Goodbye!"; log_control "Control system session ended" "INFO"; exit 0 ;;
            $'\033') echo "  Goodbye!"; log_control "Control system session ended" "INFO"; exit 0 ;;
            *) echo "  Invalid option."; sleep 1 ;;
        esac
    done
}

_run_palette_action() {
    local command="$1"
    local mode="$2"

    case "$mode" in
        page)
            eval "$command"
            ;;
        pause)
            eval "$command"
            _pause
            ;;
        exit)
            echo "  Goodbye!"
            log_control "Control system session ended" "INFO"
            exit 0
            ;;
    esac
}

show_command_palette() {
    while true; do
        local -a labels=(
            "Server / Show Status"
            "Server / Start Server"
            "Server / Stop Server"
            "Server / Restart Server"
            "Server / Select Active World"
            "Server / Start with World Select"
            "Server / Create New World"
            "Server / Import World"
            "Mods / Add Mod by URL or ID"
            "Mods / Show queued mod IDs"
            "Mods / Toggle enabled mods"
            "Mods / Edit Mod Configs"
            "Mods / List Installed Mods"
            "Workshop / Status"
            "Workshop / Download Mods"
            "Workshop / Sync Mods"
            "Workshop / List Downloads"
            "Workshop / Archive Old Versions"
            "Monitoring / Status Dashboard"
            "Monitoring / Health Check"
            "Monitoring / Follow Server Log"
            "Monitoring / Attach Server Console"
            "Backup / Status"
            "Backup / Full Server Backup"
            "Backup / Restore Backup"
            "Backup / Verify Backup"
            "Backup / Cleanup Old Backups"
            "Maintenance / Run All Maintenance Tasks"
            "Maintenance / Update Engine"
            "Diagnostics / Full Diagnostics"
            "Logs / View Server Log"
            "Logs / View Control Log"
            "UI / Open Classic Menu"
            "Exit"
        )
        local -a commands=(
            "quick_status"
            "start_server"
            "stop_server"
            "restart_server"
            "_page_world_picker"
            "_page_world_picker start"
            "_page_world_creator"
            "_page_world_importer"
            "_prompt_add_mods"
            "\"$SCRIPT_DIR/../steam/tmod-workshop.sh\" mods ids"
            "\"$SCRIPT_DIR/../steam/tmod-workshop.sh\" mods pick"
            "_page_mod_configs"
            "get_mod_list"
            "\"$SCRIPT_DIR/../steam/tmod-workshop.sh\" status"
            "\"$SCRIPT_DIR/../steam/tmod-workshop.sh\" download"
            "\"$SCRIPT_DIR/../steam/tmod-workshop.sh\" sync"
            "\"$SCRIPT_DIR/../steam/tmod-workshop.sh\" list"
            "\"$SCRIPT_DIR/../steam/tmod-workshop.sh\" archive"
            "\"$SCRIPT_DIR/../core/tmod-monitor.sh\" status"
            "\"$SCRIPT_DIR/../core/tmod-monitor.sh\" check"
            "_follow_log_file \"$LOG_DIR/server.log\" \"Server Log\""
            "_attach_server_console"
            "\"$SCRIPT_DIR/../backup/tmod-backup.sh\" status"
            "\"$SCRIPT_DIR/../backup/tmod-backup.sh\" full"
            "_restore_backup_interactive"
            "_verify_backup_interactive"
            "\"$SCRIPT_DIR/../backup/tmod-backup.sh\" cleanup"
            "run_maintenance"
            "_update_engine"
            "\"$SCRIPT_DIR/../diag/tmod-diagnostics.sh\" full"
            "_show_log_tail \"$LOG_DIR/server.log\" \"Server Log\" 50"
            "_show_log_tail \"$MAIN_LOG\" \"Control Log\" 30"
            "show_classic_menu"
            ""
        )
        local -a modes=(
            "pause"
            "pause"
            "pause"
            "pause"
            "page"
            "page"
            "page"
            "page"
            "pause"
            "pause"
            "pause"
            "page"
            "pause"
            "pause"
            "pause"
            "pause"
            "pause"
            "pause"
            "pause"
            "pause"
            "page"
            "page"
            "pause"
            "pause"
            "pause"
            "pause"
            "pause"
            "pause"
            "pause"
            "pause"
            "page"
            "page"
            "page"
            "exit"
        )

        local picked_idx
        if ! _pick_index "Command Palette" "Select action" labels picked_idx; then
            echo "  Goodbye!"
            log_control "Control system session ended" "INFO"
            exit 0
        fi

        _run_palette_action "${commands[$picked_idx]}" "${modes[$picked_idx]}"
    done
}

show_interactive_menu() {
    local mode="${1:-interactive}"

    case "$mode" in
        classic) show_classic_menu ;;
        palette|legacy|plain|fzf|dialog) show_command_palette ;;
        tui|go)
            if launch_go_tui "interactive"; then
                return 0
            fi
            echo "⚠️ Go TUI unavailable; falling back to the legacy command palette."
            show_command_palette
            ;;
        ""|interactive|menu)
            if launch_go_tui "interactive"; then
                return 0
            fi
            echo "ℹ️ Go TUI not found; using the legacy shell command palette."
            show_command_palette
            ;;
        *)
            if launch_go_tui "$mode"; then
                return 0
            fi
            show_command_palette
            ;;
    esac
}

# Enhanced maintenance with comprehensive tasks
run_maintenance() {
    echo "🔧 Running comprehensive maintenance tasks..."
    log_control "Starting maintenance sequence" "INFO"
    
    local tasks_completed=0
    local tasks_failed=0
    local start_time
    start_time=$(date +%s)
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔄 Maintenance Task Progress:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Task 1: Create maintenance backup
    echo "📦 [1/5] Creating maintenance backup..."
    if [[ -x "$SCRIPT_DIR/../backup/tmod-backup.sh" ]] && "$SCRIPT_DIR/../backup/tmod-backup.sh" worlds >/dev/null 2>&1; then
        echo "    ✅ Maintenance backup completed"
        ((tasks_completed++))
    else
        echo "    ❌ Maintenance backup failed"
        ((tasks_failed++))
    fi
    
    # Task 2: Clean old backups
    echo "🧹 [2/5] Cleaning old backups..."
    if [[ -x "$SCRIPT_DIR/../backup/tmod-backup.sh" ]] && "$SCRIPT_DIR/../backup/tmod-backup.sh" cleanup >/dev/null 2>&1; then
        echo "    ✅ Old backups cleaned"
        ((tasks_completed++))
    else
        echo "    ❌ Backup cleanup failed"
        ((tasks_failed++))
    fi
    
    # Task 3: Rotate logs
    echo "📋 [3/5] Rotating logs..."
    if rotate_logs; then
        echo "    ✅ Log rotation completed"
        ((tasks_completed++))
    else
        echo "    ❌ Log rotation failed"
        ((tasks_failed++))
    fi
    
    # Task 4: Sync mods
    echo "🔄 [4/5] Syncing mods..."
    if [[ -x "$SCRIPT_DIR/../steam/tmod-workshop.sh" ]] && "$SCRIPT_DIR/../steam/tmod-workshop.sh" sync --yes >/dev/null 2>&1; then
        echo "    ✅ Mod sync completed"
        ((tasks_completed++))
    else
        echo "    ❌ Mod sync failed"
        ((tasks_failed++))
    fi
    
    # Task 5: Check mod errors
    echo "🔍 [5/5] Checking for mod errors..."
    if check_mod_errors >/dev/null 2>&1; then
        echo "    ✅ No mod errors found"
        ((tasks_completed++))
    else
        echo "    ⚠️ Mod errors detected (check logs)"
        ((tasks_failed++))
    fi
    
    # Calculate maintenance time
    local total_time
    total_time=$(($(date +%s) - start_time))
    local time_formatted
    time_formatted=$(printf "%dm %02ds" $((total_time/60)) $((total_time%60)))
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 Maintenance Summary:"
    echo "✅ Completed: $tasks_completed/5 tasks"
    echo "❌ Failed: $tasks_failed/5 tasks"
    echo "⏱️  Duration: $time_formatted"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local total_tasks=5
    log_control "Maintenance completed: $tasks_completed/$total_tasks successful in $time_formatted" "INFO"
    
    if (( tasks_failed == 0 )); then
        echo "🎉 All maintenance tasks completed successfully!"
    else
        echo "⚠️ Maintenance completed with some issues"
    fi
}

# Quick inline system diagnostics (full diagnostics use tmod-diagnostics.sh)
show_system_diagnostics() {
    echo "🔧 System Diagnostics Report"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Check script dependencies
    echo "📋 Script Dependencies:"
    if check_dependencies; then
        echo "   ✅ All management scripts available and executable"
    else
        echo "   ❌ Some management scripts missing or not executable"
    fi
    echo
    
    # Directory structure check
    echo "📁 Directory Structure:"
    local dirs
    dirs=("$BASE_DIR" "$LOG_DIR" "$MODS_DIR" "$BASE_DIR/Configs" "$BASE_DIR/Worlds")
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            echo "   ✅ $dir"
        else
            echo "   ❌ Missing: $dir"
        fi
    done
    echo
    
    # Process information
    echo "⚙️ Process Information:"
    if is_server_up; then
        local pid
        pid=$(get_server_pid)
        echo "   ✅ Server PID: $pid"
        echo "   📊 Process info: $(ps -p "$pid" -o pid,ppid,cmd --no-headers 2>/dev/null || echo "Process details unavailable")"
    else
        echo "   ❌ No server process running"
    fi
    echo
    
    # Network and screen sessions
    echo "🖥️ Screen Sessions:"
    local screen_sessions
    screen_sessions=$(screen -list 2>/dev/null | grep -c tmodloader || echo "0")
    if (( screen_sessions > 0 )); then
        echo "   ✅ tModLoader screen sessions: $screen_sessions"
        screen -list | grep tmodloader | sed 's/^/   /'
    else
        echo "   ❌ No tModLoader screen sessions found"
    fi
    echo
    
    # Recent activity analysis
    echo "📈 Recent Activity:"
    if [[ -f "$LOG_DIR/server.log" ]]; then
        local log_size="?"
        log_size=$(stat --format="%s" "$LOG_DIR/server.log" 2>/dev/null | numfmt --to=iec || echo "?")
        local last_modified
        last_modified=$(date -r "$LOG_DIR/server.log" '+%Y-%m-%d %H:%M')
        echo "   📋 Server log: $log_size (last modified: $last_modified)"
    
        local recent_errors
        recent_errors=$(tail -100 "$LOG_DIR/server.log" | grep -c "ERROR" || echo "0")
        local recent_warnings
        recent_warnings=$(tail -100 "$LOG_DIR/server.log" | grep -c "WARN" || echo "0")
        echo "   ⚠️ Recent errors: $recent_errors, warnings: $recent_warnings"
    else
        echo "   ❌ No server log file found"
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Emergency shutdown with comprehensive safety
emergency_shutdown() {
    echo "🚨 EMERGENCY SHUTDOWN INITIATED"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_control "Emergency shutdown initiated" "CRITICAL"
    
    # Create emergency backup if possible
    if [[ -x "$SCRIPT_DIR/../backup/tmod-backup.sh" ]]; then
        echo "📦 Creating emergency backup..."
        if "$SCRIPT_DIR/../backup/tmod-backup.sh" worlds >/dev/null 2>&1; then
            echo "✅ Emergency backup completed"
            log_control "Emergency backup completed" "SUCCESS"
        else
            echo "⚠️ Emergency backup failed"
            log_control "Emergency backup failed" "WARN"
        fi
    fi
    
    # Force kill all related processes
    echo "🔪 Terminating server processes..."
    pkill -f "tModLoader.dll" 2>/dev/null || true
    pkill -f "dotnet.*tModLoader" 2>/dev/null || true
    screen -S tmodloader_server -X quit 2>/dev/null || true
    
    # Wait and force kill if necessary
    sleep 2
    pkill -9 -f "tModLoader.dll" 2>/dev/null || true
    
    echo "✅ Emergency shutdown completed"
    log_control "Emergency shutdown completed" "INFO"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Show enhanced help
show_help() {
    cat << 'EOF'
🎮 tModLoader Enhanced Unified Control System

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
  mods pick              Interactive toggle menu — no file editing needed
  mods add [--yes] <id>  Add Workshop IDs and auto-clean placeholders if confirmed

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
  interactive           Launch Go TUI when available, otherwise legacy palette
  interactive classic   Classic numbered menu
  interactive palette   Force the legacy shell palette
  tui                   Force the Go TUI
  help                  Show this help

Examples:
  ./tmod-control.sh start                    # Quick start
  ./tmod-control.sh workshop sync --yes      # Sync mods from workshop
  ./tmod-control.sh mods pick                # Interactive mod toggle menu
  ./tmod-control.sh mods list                # See enabled/disabled status
  ./tmod-control.sh mods enable CalamityMod  # Enable a specific mod
  ./tmod-control.sh backup auto              # Complete backup
  ./tmod-control.sh monitor start            # Start monitoring
  ./tmod-control.sh workshop download        # Download workshop mods
  ./tmod-control.sh interactive              # Launch Go TUI if available
  ./tmod-control.sh interactive classic      # Launch classic numbered menu
  ./tmod-control.sh tui                      # Force the Go TUI
  ./tmod-control.sh maintenance              # Run maintenance

Interactive Mode:
  ./tmod-control.sh interactive
  ./tmod-control.sh tui
  ./tmod-control.sh interactive classic
  TMOD_FORCE_LEGACY_UI=1 ./tmod-control.sh interactive
  TMOD_UI_MODE=dialog ./tmod-control.sh interactive
  TMOD_UI_MODE=fzf ./tmod-control.sh interactive

  Interactive requests prefer the Go TUI when a built binary or local Go toolchain is available.
  When the Go TUI is unavailable, the legacy shell hub falls back to a dependency-aware command palette:
  - fzf is used for searchable pickers when available
  - dialog is used for boxed menus and log viewers when available
  - plain Bash menus remain as the fallback
  Use TMOD_FORCE_LEGACY_UI=1 or interactive classic if you want the old shell UI on purpose.

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
  ✅ Unified control of all server operations
  ✅ Persistent Go TUI with shell-script backend fallback
  ✅ Comprehensive maintenance automation
  ✅ Emergency procedures with safety backups
  ✅ System health monitoring and diagnostics
  ✅ Dependency validation and error handling
  ✅ Advanced backup integration
  ✅ Performance monitoring integration
  ✅ Steam Workshop management integration
  ✅ Automated log rotation and cleanup

Dependencies:
  - All tmod-* management scripts in same directory
  - Screen for server management
  - fzf for searchable pickers (optional)
  - dialog for boxed menus and log viewers (optional)
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
        echo "❌ Critical dependencies missing. Please ensure all tmod-* scripts are present."
        echo "💡 Run './tmod-control.sh scripts' to see detailed script status."
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
                echo "❌ Backup script not available"
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
                echo "❌ Monitoring script not available"
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
                echo "❌ Workshop script not available"
                exit 1
            fi
            ;;
        
        # Mod load management
        mods)
            if [[ -x "$SCRIPT_DIR/../steam/tmod-workshop.sh" ]]; then
                shift
                exec "$SCRIPT_DIR/../steam/tmod-workshop.sh" mods "$@"
            else
                echo "❌ Workshop script not available"
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
            echo "❌ Unknown command: $1"
            echo "💡 Use './tmod-control.sh help' for usage information"
            echo "💡 Use './tmod-control.sh interactive' for the control room"
            exit 1
            ;;
    esac
}

# Initialize and run
init_tmod
main "$@"
