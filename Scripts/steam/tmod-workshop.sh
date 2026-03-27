#!/bin/bash
# tmod-workshop.sh - Steam Workshop mod management and downloading
export SCRIPT_VERSION="2.5.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="$SCRIPT_DIR/../core/tmod-core.sh"

# Load core functions with proper error handling
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

# Workshop configuration
STEAMCMD_PATH="$(get_steamcmd_path)"
STEAM_USERNAME="${STEAM_USERNAME:-}"
MOD_IDS_FILE="$BASE_DIR/Scripts/steam/mod_ids.txt"
WORKSHOP_DOWNLOAD_DIR="${WORKSHOP_DIR:-$BASE_DIR/Engine/steamapps/workshop/content/1281930}"
ARCHIVE_DIR="$BASE_DIR/Mods/archived_mods"

get_workshop_login_user() {
    if [[ -n "$STEAM_USERNAME" ]]; then
        echo "$STEAM_USERNAME"
    else
        echo "anonymous"
    fi
}

get_workshop_login_label() {
    if [[ -n "$STEAM_USERNAME" ]]; then
        echo "logged-in ($STEAM_USERNAME)"
    else
        echo "anonymous fallback"
    fi
}

# Enhanced logging for workshop operations
log_workshop() {
    local message
    message="$1"
    local level
    level="${2:-INFO}"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$timestamp] [$level] $message" | tee -a "$LOG_DIR/workshop.log"
}

# ─── Steam API helpers ────────────────────────────────────────────────────────

validate_steamid() {
    [[ "$1" =~ ^7656119[0-9]{10}$ ]] && return 0 || return 1
}

# Validate workshop configuration
validate_workshop_config() {
    local errors=0
    
    # Check SteamCMD
    if [[ ! -f "$STEAMCMD_PATH" ]]; then
        echo "❌ SteamCMD not found at: $STEAMCMD_PATH"
        echo "💡 Install SteamCMD or set STEAMCMD_PATH environment variable"
        ((errors++))
    fi
    
    # Steam username is optional for Workshop downloads. Anonymous works, but
    # a real account may be more resilient for larger download batches.
    if [[ -z "$STEAM_USERNAME" ]]; then
        echo "ℹ️ Steam username not set"
        echo "💡 Workshop downloads will use anonymous login"
        echo "💡 Set STEAM_USERNAME in your shell or Scripts/env.sh if you want logged-in downloads"
    fi
    
    # Check mod IDs file
    if [[ ! -f "$MOD_IDS_FILE" ]]; then
        echo "⚠️ Mod IDs file not found: $MOD_IDS_FILE"
        echo "💡 Creating example mod_ids.txt file..."
        create_example_mod_ids_file
    fi
    
    return $errors
}

# Create example mod IDs file
create_example_mod_ids_file() {
    local example_file="$BASE_DIR/Scripts/steam/mod_ids.example.txt"
    if [[ -f "$example_file" ]]; then
        cp "$example_file" "$MOD_IDS_FILE"
        echo "📄 Created mod_ids.txt from mod_ids.example.txt"
    else
        cat > "$MOD_IDS_FILE" << 'EOF'
# tModLoader Workshop Mod IDs
# Add Steam Workshop mod IDs here (one per line)
# Lines starting with # are comments
#
# Example mods:
# 2563309347  # Calamity Mod
# 2565639705  # Thorium Mod
# 2568564996  # Magic Storage

# Add your mod IDs below:

EOF
        echo "📄 Created example mod_ids.txt file"
    fi
    echo "💡 Edit $MOD_IDS_FILE to add your desired mod IDs"
}

# Download mods from Steam Workshop
download_mods() {
    echo "🔄 Starting Steam Workshop mod download..."
    log_workshop "Starting mod download process" "INFO"

    # Validate configuration
    if ! validate_workshop_config; then
        echo "❌ Configuration validation failed"
        return 1
    fi

    # Build list of mod IDs upfront so we know total count and can show progress
    local mod_ids=()
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        local id
        id=$(echo "$line" | sed 's/#.*$//' | tr -d '[:space:]')
        [[ -n "$id" ]] && mod_ids+=("$id")
    done < "$MOD_IDS_FILE"

    local mod_count=${#mod_ids[@]}
    if [[ $mod_count -eq 0 ]]; then
        echo "❌ No mod IDs found in $MOD_IDS_FILE"
        return 1
    fi

    # Count already-downloaded mods upfront
    local already=0
    local install_base="$BASE_DIR/Engine"
    local steam_login_user
    steam_login_user="$(get_workshop_login_user)"
    local steam_login_label
    steam_login_label="$(get_workshop_login_label)"
    for id in "${mod_ids[@]}"; do
        local mod_dir="$WORKSHOP_DOWNLOAD_DIR/$id"
        if [[ -d "$mod_dir" ]] && [[ -n "$(ls -A "$mod_dir" 2>/dev/null)" ]]; then
            (( already++ ))
        fi
    done
    local to_download=$(( mod_count - already ))

    echo "📋 $mod_count mods in list  |  $already already downloaded  |  $to_download to fetch"
    echo "👤 Steam Login: $steam_login_label"
    echo "📥 Download Dir: $WORKSHOP_DOWNLOAD_DIR"
    echo

    # Progress bar helper: _bar current total
    _bar() {
        local cur=$1 tot=$2
        local pct=$(( tot > 0 ? cur * 100 / tot : 100 ))
        local filled=$(( cur * 30 / (tot > 0 ? tot : 1) ))
        local empty=$(( 30 - filled ))
        local bar=""
        local i
        for (( i=0; i<filled; i++ )); do bar+="█"; done
        for (( i=0; i<empty;  i++ )); do bar+="░"; done
        printf "  [%s] %3d%%  %d/%d mods\r" "$bar" "$pct" "$cur" "$tot"
    }

    local downloaded=0 skipped=0 failed=0 idx=0
    local start_time
    start_time=$(date +%s)
    mkdir -p "$WORKSHOP_DOWNLOAD_DIR"

    for mod_id in "${mod_ids[@]}"; do
        (( idx++ ))

        local mod_dir="$WORKSHOP_DOWNLOAD_DIR/$mod_id"

        # Skip mods that are already fully downloaded
        if [[ -d "$mod_dir" ]] && [[ -n "$(ls -A "$mod_dir" 2>/dev/null)" ]]; then
            (( skipped++ ))
            _bar "$idx" "$mod_count"
            continue
        fi

        # Show progress line above the bar
        echo -e "\n  📥 [$idx/$mod_count] Downloading $mod_id..."

        local steamcmd_output
        steamcmd_output=$(mktemp)

        if "$STEAMCMD_PATH" \
            +force_install_dir "$install_base" \
            +login "$steam_login_user" \
            +workshop_download_item 1281930 "$mod_id" \
            +quit > "$steamcmd_output" 2>&1; then

            (( downloaded++ ))
            _bar "$idx" "$mod_count"
            log_workshop "Downloaded mod: $mod_id" "INFO"

            # Rate limit guard between successful downloads
            sleep 5

        else
            # Check if it looks like a rate limit vs a real failure
            if grep -qi "rate limit\|too many\|try again" "$steamcmd_output" 2>/dev/null; then
                echo "  ⚠️  Rate limited on $mod_id — pausing 60s before continuing..."
                log_workshop "Rate limited on $mod_id, sleeping 60s" "WARN"
                sleep 60
                # Retry once after the cooldown
                if "$STEAMCMD_PATH" \
                    +force_install_dir "$install_base" \
                    +login "$steam_login_user" \
                    +workshop_download_item 1281930 "$mod_id" \
                    +quit >> "$steamcmd_output" 2>&1; then
                    (( downloaded++ ))
                    log_workshop "Downloaded mod after retry: $mod_id" "INFO"
                else
                    echo "  ❌ Still failed after retry: $mod_id"
                    log_workshop "Failed mod (rate limit retry): $mod_id" "ERROR"
                    (( failed++ ))
                fi
            else
                echo "  ❌ Failed: $mod_id"
                log_workshop "Failed mod: $mod_id" "ERROR"
                (( failed++ ))
                sleep 10
            fi
            _bar "$idx" "$mod_count"
        fi

        rm -f "$steamcmd_output"
    done

    # Final newline after the progress bar
    echo -e "\n"

    local duration=$(( $(date +%s) - start_time ))
    local time_fmt
    time_fmt=$(printf "%dm %02ds" $((duration/60)) $((duration%60)))

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 Download Summary:"
    echo "  ✅ Downloaded : $downloaded"
    echo "  ⏭️  Skipped   : $skipped  (already present)"
    echo "  ❌ Failed     : $failed"
    echo "  ⏱️  Time      : $time_fmt"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    log_workshop "Download complete: $downloaded new, $skipped skipped, $failed failed in $time_fmt" "INFO"
    
    if [[ $downloaded -gt 0 ]]; then
        echo "💡 Run './tmod-workshop.sh sync' to copy mods to server directory"
        return 0
    else
        return 1
    fi
}

# Sync downloaded mods to server mods directory - FINDS LATEST COMPATIBLE VERSION
sync_downloaded_mods() {
    echo "🔄 Syncing downloaded mods to server..."
    log_workshop "Starting mod sync from workshop to server" "INFO"

    if [[ ! -d "$WORKSHOP_DOWNLOAD_DIR" ]]; then
        echo "❌ Workshop download directory not found: $WORKSHOP_DOWNLOAD_DIR"
        return 1
    fi
    WORKSHOP_DIR="$WORKSHOP_DOWNLOAD_DIR"

    # Derive version cap from the highest version folder present in the workshop cache.
    # SteamCMD downloads exactly the versions the server can handle, so the max present
    # IS the server's API version — no hardcoded constant needed.
    local MAX_ALLOWED_VERSION
    # Fixed: Use -print0 with xargs -0 to handle filenames with special characters
    MAX_ALLOWED_VERSION=$(find "$WORKSHOP_DIR" -mindepth 2 -maxdepth 2 -type d -print0 \
        | xargs -0 -I{} basename {} 2>/dev/null \
        | grep -E '^[0-9]{4}\.[0-9]+$' \
        | sort -V | tail -1)
    MAX_ALLOWED_VERSION="${MAX_ALLOWED_VERSION:-2025.6}"

    declare -A compatible_mods

    # Silently find the latest compatible version of each mod
    echo "🔍 Scanning workshop cache (≤ v$MAX_ALLOWED_VERSION)..."
    while IFS= read -r -d '' mod_file; do
        [[ "$mod_file" != *.tmod ]] && continue

        local mod_name version
        if ! mod_name="$(get_mod_name "$mod_file")" || [[ -z "$mod_name" ]]; then continue; fi
        if ! version="$(get_mod_version "$mod_file")" || [[ -z "$version" ]]; then continue; fi

        # Skip versions newer than what the server supports
        if version_gt "$version" "$MAX_ALLOWED_VERSION"; then continue; fi

        # Keep the latest compatible version for each mod
        local current_best="${compatible_mods[$mod_name]}"
        if [[ -z "$current_best" ]] || version_gt "$version" "${current_best%:*}"; then
            compatible_mods["$mod_name"]="$version:$mod_file"
        fi

    done < <(find "$WORKSHOP_DIR" -type f -name "*.tmod" -print0)

    # PREVIEW PHASE: only print mods that need syncing; count the rest
    local to_sync=()
    local preview_sync_count=0
    local preview_skip_updated_count=0
    local found_count=0

    for mod_name in "${!compatible_mods[@]}"; do
        (( found_count++ ))
        local mod_info mod_file version target_file
        mod_info="${compatible_mods[$mod_name]}"
        version="${mod_info%:*}"
        mod_file="${mod_info#*:}"
        target_file="$MODS_DIR/$mod_name.tmod"

        [[ ! -f "$mod_file" ]] && continue

        if [[ -f "$target_file" && ! "$mod_file" -nt "$target_file" ]]; then
            (( preview_skip_updated_count++ ))
        else
            to_sync+=("$mod_name|$version|$mod_file|$target_file")
            (( preview_sync_count++ ))
        fi
    done

    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [[ $preview_sync_count -gt 0 ]]; then
        echo "📋 To Sync:"
        for entry in "${to_sync[@]}"; do
            IFS='|' read -r n v _ _ <<< "$entry"
            echo "  ✅ $n  ($v)"
        done
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
    echo "📊 $found_count mods found  ·  ✅ $preview_sync_count to sync  ·  ⏭️ $preview_skip_updated_count up to date"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [[ $found_count -eq 0 ]]; then
        echo "❌ No mods found in workshop cache"
        return 1
    fi

    if [[ $preview_sync_count -eq 0 ]]; then
        echo "✅ All mods up to date — nothing to sync"
        return 0
    fi

    # CONFIRMATION PROMPT
    read -p "❓ Proceed with syncing $preview_sync_count mods? [y/N]: " -r REPLY
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Sync cancelled"
        return 0
    fi
    
    echo
    echo "🔄 Syncing mods to server..."
    
    # SYNC PHASE
    local synced=0
    local errors=0
    local synced_names=()

    for mod_entry in "${to_sync[@]}"; do
        local mod_name version mod_file target_file
        IFS='|' read -r mod_name version mod_file target_file <<< "$mod_entry"

        if cp "$mod_file" "$target_file" 2>/dev/null; then
            echo "✅ Synced: $mod_name ($version)"
            synced_names+=("$mod_name")
            (( synced++ ))
        else
            echo "❌ Failed to copy: $mod_name"
            (( errors++ ))
        fi
    done

    echo
    echo "📊 Sync Results:"
    echo "✅ Synced: $synced mods"
    echo "⏭️ Skipped (up to date): $preview_skip_updated_count mods"
    echo "❌ Errors: $errors mods"

    log_workshop "Sync completed: $synced synced, $preview_skip_updated_count skipped (up to date), $errors errors" "INFO"

    if [[ $synced -gt 0 ]]; then
        # Pass the newly synced names so update_enabled_mods can auto-enable only new mods
        update_enabled_mods "${synced_names[@]}"
        echo "💡 Run './tmod-server.sh restart' to load new mods"
        return 0
    else
        return "$([[ $errors -eq 0 ]] && echo 0 || echo 1)"
    fi
}

# Archive old mod versions - only archive mods under 2023
archive_old_versions() {
    echo "📦 Archiving old mod versions..."
    log_workshop "Starting mod version archival" "INFO"
    
    mkdir -p "$ARCHIVE_DIR"
    
    if [[ ! -d "$WORKSHOP_DOWNLOAD_DIR" ]]; then
        echo "❌ Workshop directory not found: $WORKSHOP_DOWNLOAD_DIR"
        return 1
    fi
    
    # PREVIEW PHASE: Show what will be archived
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 ARCHIVE PREVIEW (mods < 2023):"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local to_archive=()
    local preview_count=0
    local total_mods=0
    
    while IFS= read -r -d '' mod_file; do
        [[ ! -f "$mod_file" ]] && continue
        
        local mod_name
        mod_name=$(basename "$mod_file" .tmod)
        local version
        version=$(basename "$(dirname "$mod_file")")
        
        # Skip if not a proper version directory
        [[ ! "$version" =~ ^[0-9] ]] && continue
        
        ((total_mods++))
        
        # Check if version is older than 2023 (incompatible)
        if ! is_compatible_version "$version"; then
            echo "📦 $mod_name (v$version < 2023)"
            to_archive+=("$mod_file")
            ((preview_count++))
        fi
    done < <(find "$WORKSHOP_DOWNLOAD_DIR" -type f -name "*.tmod" -print0)
    
    if [[ $preview_count -eq 0 ]]; then
        echo "✅ No mods to archive (all mods are 2023+)"
        return 0
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Total: $preview_count mods will be archived"
    echo
    
    # CONFIRMATION PROMPT
    read -p "❓ Proceed with archiving? [y/N]: " -r REPLY
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Archive cancelled by user"
        return 0
    fi
    
    echo
    echo "🔄 Archiving mods..."
    
    # ARCHIVING PHASE
    local archived=0
    local kept=$((total_mods - preview_count))
    
    for mod_file in "${to_archive[@]}"; do
        local mod_name
        mod_name=$(basename "$mod_file" .tmod)
        local version
        version=$(basename "$(dirname "$mod_file")")
        
        local archive_file="$ARCHIVE_DIR/${mod_name}-v${version}-OLD.tmod"
        if mv "$mod_file" "$archive_file" 2>/dev/null; then
            echo "📦 Archived: $mod_name (v$version)"
            ((archived++))
        else
            echo "❌ Failed to archive: $mod_name (v$version)"
        fi
    done
    
    # Clean empty directories - fixed with -print0
    find "$WORKSHOP_DOWNLOAD_DIR" -type d -empty -print0 2>/dev/null | xargs -0 rm -rf 2>/dev/null
    
    echo
    echo "📊 Archive Results:"
    echo "📦 Archived: $archived old versions (< 2023)"
    echo "✅ Kept: $kept versions (2023+)"
    echo "📁 Archive location: $ARCHIVE_DIR"
    
    log_workshop "Archive completed: $archived archived (< 2023), $kept kept" "INFO"
    
    if [[ $archived -gt 0 ]]; then
        log_workshop "Archived $archived old mod versions (< 2023)" "INFO"
    fi
    
    return 0
}

# List downloaded workshop mods
list_workshop_mods() {
    echo "📋 Steam Workshop Mods"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [[ ! -d "$WORKSHOP_DOWNLOAD_DIR" ]]; then
        echo "❌ Workshop directory not found: $WORKSHOP_DOWNLOAD_DIR"
        return 1
    fi
    
    # Declare the array that will be populated by get_latest_workshop_mods
    declare -gA latest_mods
    
    # Get latest mods
    get_latest_workshop_mods || {
        echo "❌ Failed to scan workshop mods"
        return 1
    }
    
    if [[ ${#latest_mods[@]} -eq 0 ]]; then
        echo "📭 No workshop mods found"
        echo "💡 Run './tmod-workshop.sh download' to download mods"
        return 0
    fi
    
    printf "%-30s %-12s %-12s %-15s %s\n" "Mod Name" "Version" "Size" "Compatible" "Workshop ID"
    printf '%0.1s' '-'{1..85}; echo
    
    for mod_name in "${!latest_mods[@]}"; do
        local mod_info
        mod_info="${latest_mods[$mod_name]}"
        local version
        version="${mod_info%:*}"
        local mod_file
        mod_file="${mod_info#*:}"
        local workshop_id
        workshop_id=$(basename "$(dirname "$mod_file")")
        
        local size="?"
        if [[ -f "$mod_file" ]]; then
            size=$(stat --format="%s" "$mod_file" 2>/dev/null | numfmt --to=iec || echo "?")
        fi
        
        local compatible="❌ No"
        if is_compatible_version "$version"; then
            compatible="✅ Yes"
        fi
        
        printf "%-30s %-12s %-12s %-15s %s\n" \
            "${mod_name:0:29}" "$version" "$size" "$compatible" "$workshop_id"
    done
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Total: ${#latest_mods[@]} workshop mods"
    
    # Show archive info if exists
    if [[ -d "$ARCHIVE_DIR" ]]; then
        local archived_count
        # Fixed: Use -print0 with xargs -0 or process substitution
        archived_count=$(find "$ARCHIVE_DIR" -name "*.tmod" -print0 2>/dev/null | xargs -0 -n1 | wc -l)
        if [[ $archived_count -gt 0 ]]; then
            echo "📦 Archived versions: $archived_count old mod files"
        fi
    fi
}

# Show workshop mod IDs file with resolved names
show_mod_ids() {
    echo "📄 mod_ids.txt — Queued Workshop Mods"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [[ ! -f "$MOD_IDS_FILE" ]]; then
        echo "  mod_ids.txt not found — nothing queued yet."
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        return
    fi

    local mod_count
    mod_count=$(grep -vc "^[[:space:]]*#\|^[[:space:]]*$" "$MOD_IDS_FILE" 2>/dev/null || echo 0)

    if [[ "$mod_count" -eq 0 ]]; then
        echo "  mod_ids.txt is empty — no mods queued."
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        return
    fi

    echo "  $mod_count mod(s) queued:"
    echo

    # First pass: collect IDs and flag invalid lines
    local ids=()
    local invalid=()
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# || -z "${line// }" ]] && continue
        local mod_id
        mod_id=$(echo "$line" | grep -oE '^[0-9]+' | head -1)
        if [[ -z "$mod_id" ]]; then
            invalid+=("$line")
        else
            ids+=("$mod_id")
        fi
    done < "$MOD_IDS_FILE"

    # Single batch API call for all IDs
    declare -A name_map
    get_workshop_mod_names_batch name_map "${ids[@]}"

    # Build name<TAB>id pairs and sort alphabetically
    local entries=()
    for mod_id in "${ids[@]}"; do
        entries+=("${name_map[$mod_id]}	${mod_id}")
    done

    local i=1
    while IFS='	' read -r name mod_id; do
        printf "  %2d. %-40s %s\n" "$i" "$name" "$mod_id"
        (( i++ ))
    done < <(printf '%s\n' "${entries[@]}" | sort -f)

    # Invalid lines at the bottom
    for line in "${invalid[@]}"; do
        printf "  %2d. %-40s %s  ⚠️ invalid\n" "$i" "" "$line"
        (( i++ ))
    done

    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Clean up workshop downloads
cleanup_workshop() {
    echo "🧹 Cleaning up workshop downloads..."
    log_workshop "Starting workshop cleanup" "INFO"
    
    local removed_dirs=0

    # Clean empty directories - fixed with -print0
    while IFS= read -r -d '' empty_dir; do
        if rmdir "$empty_dir" 2>/dev/null; then
            echo "🗑️ Removed empty directory: $(basename "$empty_dir")"
            ((removed_dirs++))
        fi
    done < <(find "$WORKSHOP_DOWNLOAD_DIR" -type d -empty -print0 2>/dev/null)
    
    # Clean incomplete downloads (directories without .tmod files) - fixed with -print0
    while IFS= read -r -d '' mod_dir; do
        if [[ ! "$(find "$mod_dir" -name "*.tmod" -type f -print0 2>/dev/null | xargs -0 -n1 | wc -l)" -gt 0 ]]; then
            echo "🗑️ Removing incomplete download: $(basename "$mod_dir")"
            rm -rf "$mod_dir"
            ((removed_dirs++))
        fi
    done < <(find "$WORKSHOP_DOWNLOAD_DIR" -maxdepth 1 -type d -print0 2>/dev/null)
    
    echo "📊 Cleanup results:"
    echo "🗑️ Removed directories: $removed_dirs"
    
    log_workshop "Cleanup completed: $removed_dirs directories removed" "INFO"
    
    return 0
}

# Show workshop status and configuration
show_status() {
    echo "📊 Steam Workshop Manager Status"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Configuration status
    echo "⚙️ Configuration:"
    
    if [[ -f "$STEAMCMD_PATH" ]]; then
        echo "   ✅ SteamCMD: Found at $STEAMCMD_PATH"
    else
        echo "   ❌ SteamCMD: Not found at $STEAMCMD_PATH"
    fi
    
    if [[ -n "$STEAM_USERNAME" ]]; then
        echo "   ✅ Steam Login: logged-in ($STEAM_USERNAME)"
    else
        echo "   ℹ️ Steam Login: anonymous fallback"
    fi
    
    if [[ -f "$MOD_IDS_FILE" ]]; then
        local mod_count
        mod_count=$(grep -vc "^[[:space:]]*#\|^[[:space:]]*$" "$MOD_IDS_FILE" 2>/dev/null || echo 0)
        echo "   ✅ Mod IDs File: $mod_count mod IDs configured"
    else
        echo "   ❌ Mod IDs File: Not found"
    fi
    
    echo
    
    # Download directory status
    if [[ -d "$WORKSHOP_DOWNLOAD_DIR" ]]; then
        local downloaded_count
        # Fixed: Use -print0 with process substitution
        downloaded_count=$(find "$WORKSHOP_DOWNLOAD_DIR" -name "*.tmod" -print0 2>/dev/null | xargs -0 -n1 | wc -l)
        local unique_mods
        unique_mods=$(find "$WORKSHOP_DOWNLOAD_DIR" -name "*.tmod" -exec basename {} .tmod \; 2>/dev/null | sort -u | wc -l)
        local total_size
        total_size=$(du -sh "$WORKSHOP_DOWNLOAD_DIR" 2>/dev/null | cut -f1)
        
        echo "📥 Downloads:"
        echo "   📁 Directory: $WORKSHOP_DOWNLOAD_DIR"
        echo "   📋 Total files: $downloaded_count .tmod files"
        echo "   🎮 Unique mods: $unique_mods different mods"
        echo "   💾 Total size: $total_size"
    else
        echo "📥 Downloads: Directory not found"
    fi
    
    echo
    
    # Server mods status
    local server_mod_count
    server_mod_count=$(get_mod_list | wc -l)
    echo "🎮 Server Mods: $server_mod_count mods in server directory"
    
    # Archive status
    if [[ -d "$ARCHIVE_DIR" ]]; then
        local archived_count
        # Fixed: Use -print0 with process substitution
        archived_count=$(find "$ARCHIVE_DIR" -name "*.tmod" -print0 2>/dev/null | xargs -0 -n1 | wc -l)
        echo "📦 Archive: $archived_count archived mod versions"
    else
        echo "📦 Archive: Not initialized"
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Initialize workshop system
init_workshop() {
    echo "🔧 Initializing Steam Workshop system..."
    
    mkdir -p "$ARCHIVE_DIR"
    
    # Create mod IDs file if it doesn't exist
    if [[ ! -f "$MOD_IDS_FILE" ]]; then
        create_example_mod_ids_file
    fi
    
    # Validate configuration
    echo "🔍 Validating configuration..."
    if validate_workshop_config; then
        echo "✅ Workshop system initialized successfully"
        echo "💡 Edit $MOD_IDS_FILE to add your desired mod IDs"
        if [[ -z "$STEAM_USERNAME" ]]; then
            echo "💡 Downloads will use anonymous login until STEAM_USERNAME is configured"
        fi
        echo "💡 Then run './tmod-workshop.sh download' to download mods"
        return 0
    else
        echo "❌ Workshop system initialization failed"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# MOD ENABLE / DISABLE MANAGEMENT
# Reads/writes $MODS_DIR/enabled.json, which tModLoader uses at startup to
# decide which of the installed .tmod files should actually load.
# ─────────────────────────────────────────────────────────────────────────────

# Compute path at call time so it always reflects the current $MODS_DIR value
_enabled_json() { echo "$MODS_DIR/enabled.json"; }

# Read enabled.json → populate the global ENABLED_MODS associative array
# Keys are mod names (lowercase for matching), values are the original-case name.
_load_enabled() {
    declare -gA ENABLED_MODS=()
    local enabled_json
    enabled_json="$(_enabled_json)"
    [[ ! -f "$enabled_json" ]] && return 0
    if command -v jq >/dev/null 2>&1; then
        while IFS= read -r name; do
            ENABLED_MODS["${name,,}"]="$name"
        done < <(jq -r '.[]' "$enabled_json" 2>/dev/null)
    else
        # Fallback: crude grep-based parse for environments without jq
        while IFS= read -r name; do
            name="${name//\"/}"
            name="${name//,/}"
            name="${name// /}"
            [[ -n "$name" && "$name" != "[" && "$name" != "]" ]] \
                && ENABLED_MODS["${name,,}"]="$name"
        done < "$enabled_json"
    fi
}

# Write ENABLED_MODS back to enabled.json (backs up first)
_save_enabled() {
    local enabled_json
    enabled_json="$(_enabled_json)"
    [[ -f "$enabled_json" ]] && cp "$enabled_json" "${enabled_json}.bak"
    local names=()
    for key in "${!ENABLED_MODS[@]}"; do
        names+=("${ENABLED_MODS[$key]}")
    done
    # Sort for stable output
    local sorted=()
    mapfile -t sorted < <(printf '%s\n' "${names[@]}" | sort)

    if command -v jq >/dev/null 2>&1; then
        printf '%s\n' "${sorted[@]}" \
            | jq -R -s -c 'split("\n") | del(.[] | select(. == ""))' \
            > "$enabled_json"
    else
        {
            echo "["
            local last=$(( ${#sorted[@]} - 1 ))
            for i in "${!sorted[@]}"; do
                if [[ $i -lt $last ]]; then
                    printf '  "%s",\n' "${sorted[$i]}"
                else
                    printf '  "%s"\n'  "${sorted[$i]}"
                fi
            done
            echo "]"
        } > "$enabled_json"
    fi
    log_workshop "Saved enabled.json (${#ENABLED_MODS[@]} mods)" "INFO"
}

# Return list of installed .tmod names (no extension, sorted)
_installed_mods() {
    find "$MODS_DIR" -maxdepth 1 -name "*.tmod" -print0 \
        | xargs -0 -n1 basename 2>/dev/null \
        | sed 's/\.tmod$//' \
        | sort
}

# ── mods list ──────────────────────────────────────────────────────────────
# Shows every installed mod and whether it's enabled or disabled.
mods_list() {
    local installed
    mapfile -t installed < <(_installed_mods)

    if [[ ${#installed[@]} -eq 0 ]]; then
        echo "📭 No mods installed in $MODS_DIR"
        echo "   Run './tmod-workshop.sh sync' to copy mods from the workshop."
        return 0
    fi

    _load_enabled

    echo "📦 Installed Mods  (${#installed[@]} total)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "  %-3s  %-40s  %s\n" "#" "Mod Name" "Status"
    printf "  %-3s  %-40s  %s\n" "---" "----------------------------------------" "--------"

    local enabled_count=0 disabled_count=0
    for i in "${!installed[@]}"; do
        local mod="${installed[$i]}"
        local num=$(( i + 1 ))
        if [[ -v "ENABLED_MODS[${mod,,}]" ]]; then
            printf "  %-3s  %-40s  🟢 enabled\n"  "$num" "$mod"
            (( enabled_count++ ))
        else
            printf "  %-3s  %-40s  ⚫ disabled\n" "$num" "$mod"
            (( disabled_count++ ))
        fi
    done

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  🟢 $enabled_count enabled   ⚫ $disabled_count disabled"
}

# ── mods enable <name|all> ────────────────────────────────────────────────
mods_enable() {
    local target="${1:-}"
    _load_enabled

    if [[ "$target" == "all" ]]; then
        local count=0
        while IFS= read -r mod; do
            if [[ ! -v "ENABLED_MODS[${mod,,}]" ]]; then
                ENABLED_MODS["${mod,,}"]="$mod"
                echo "  🟢 Enabled: $mod"
                (( count++ ))
            fi
        done < <(_installed_mods)
        _save_enabled
        echo "✅ Enabled $count mod(s)"
        return 0
    fi

    [[ -z "$target" ]] && { echo "Usage: mods enable <mod_name[,mod2,...]|all>"; return 1; }

    # Split on commas, trim spaces
    local names=()
    IFS=',' read -ra names <<< "$target"

    local changed=0 errors=0
    for raw in "${names[@]}"; do
        local name="${raw// /}"
        [[ -z "$name" ]] && continue

        local matched=""
        while IFS= read -r mod; do
            if [[ "${mod,,}" == "${name,,}" ]]; then matched="$mod"; break; fi
        done < <(_installed_mods)

        if [[ -z "$matched" ]]; then
            local candidates=()
            while IFS= read -r mod; do
                if [[ "${mod,,}" == *"${name,,}"* ]]; then candidates+=("$mod"); fi
            done < <(_installed_mods)
            if [[ ${#candidates[@]} -eq 1 ]]; then
                matched="${candidates[0]}"
            elif [[ ${#candidates[@]} -gt 1 ]]; then
                echo "  ❓ Multiple matches for '$name' — be more specific:"
                for c in "${candidates[@]}"; do echo "     $c"; done
                (( errors++ ))
                continue
            fi
        fi

        if [[ -z "$matched" ]]; then
            echo "  ❌ Not found: $name"
            (( errors++ ))
        elif [[ -v "ENABLED_MODS[${matched,,}]" ]]; then
            echo "  ℹ️  Already enabled: $matched"
        else
            ENABLED_MODS["${matched,,}"]="$matched"
            echo "  🟢 Enabled: $matched"
            (( changed++ ))
        fi
    done

    (( changed > 0 )) && _save_enabled
    [[ $errors -gt 0 ]] && return 1 || return 0
}

# ── mods disable <name|all> ───────────────────────────────────────────────
mods_disable() {
    local target="${1:-}"
    _load_enabled

    if [[ "$target" == "all" ]]; then
        local count=${#ENABLED_MODS[@]}
        ENABLED_MODS=()
        _save_enabled
        echo "✅ Disabled all $count mod(s)"
        return 0
    fi

    [[ -z "$target" ]] && { echo "Usage: mods disable <mod_name[,mod2,...]|all>"; return 1; }

    # Split on commas, trim spaces
    local names=()
    IFS=',' read -ra names <<< "$target"

    local changed=0 errors=0
    for raw in "${names[@]}"; do
        local name="${raw// /}"
        [[ -z "$name" ]] && continue

        # Resolve to canonical installed mod name (exact, then partial)
        local matched=""
        while IFS= read -r mod; do
            if [[ "${mod,,}" == "${name,,}" ]]; then matched="$mod"; break; fi
        done < <(_installed_mods)

        if [[ -z "$matched" ]]; then
            local candidates=()
            while IFS= read -r mod; do
                if [[ "${mod,,}" == *"${name,,}"* ]]; then candidates+=("$mod"); fi
            done < <(_installed_mods)
            if [[ ${#candidates[@]} -eq 1 ]]; then
                matched="${candidates[0]}"
            elif [[ ${#candidates[@]} -gt 1 ]]; then
                echo "  ❓ Multiple matches for '$name' — be more specific:"
                for c in "${candidates[@]}"; do echo "     $c"; done
                (( errors++ ))
                continue
            fi
        fi

        if [[ -z "$matched" ]]; then
            echo "  ❌ Not found: $name"
            (( errors++ ))
            continue
        fi

        local key="${matched,,}"
        if [[ ! -v "ENABLED_MODS[$key]" ]]; then
            echo "  ℹ️  Not enabled: $matched"
        else
            local actual="${ENABLED_MODS[$key]}"
            unset "ENABLED_MODS[$key]"
            echo "  ⚫ Disabled: $actual"
            (( changed++ ))
        fi
    done

    (( changed > 0 )) && _save_enabled
    [[ $errors -gt 0 ]] && return 1 || return 0
}

# ── mods pick  (interactive toggle menu) ─────────────────────────────────
# Arrow-key-free menu that works over SSH.  Type a number to toggle,
# 's' to save, 'q' to quit without saving, 'a' to enable all, 'n' to
# disable all.
mods_pick() {
    local installed
    mapfile -t installed < <(_installed_mods)

    if [[ ${#installed[@]} -eq 0 ]]; then
        echo "📭 No mods installed. Run './tmod-workshop.sh sync' first."
        return 0
    fi

    _load_enabled
    # Work on a local copy so we can cancel without damage
    declare -A local_enabled
    for k in "${!ENABLED_MODS[@]}"; do
        local_enabled["$k"]="${ENABLED_MODS[$k]}"
    done

    while true; do
        clear
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo " 🎮  Mod Load Manager  —  toggle which mods load at server start"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        printf "  %-5s  %-42s  %s\n" "NUM" "Mod Name" "Load?"
        printf "  %-5s  %-42s  %s\n" "-----" "------------------------------------------" "------"

        local enabled_now=0
        for i in "${!installed[@]}"; do
            local mod="${installed[$i]}"
            local num=$(( i + 1 ))
            if [[ -v "local_enabled[${mod,,}]" ]]; then
                printf "  [%-3s]  %-42s  🟢 YES\n" "$num" "$mod"
                (( enabled_now++ ))
            else
                printf "  [%-3s]  %-42s  ⚫ no\n"  "$num" "$mod"
            fi
        done

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  $enabled_now / ${#installed[@]} mods enabled"
        echo
        echo "  Type a number to toggle  |  a = enable all  |  n = disable all"
        echo "  s = save & exit          |  q = quit without saving"
        echo
        read -rp "  Choice: " choice

        case "$choice" in
            [0-9]*)
                # Could be a plain number
                if [[ "$choice" =~ ^[0-9]+$ ]]; then
                    local idx=$(( choice - 1 ))
                    if (( idx >= 0 && idx < ${#installed[@]} )); then
                        local mod="${installed[$idx]}"
                        if [[ -v "local_enabled[${mod,,}]" ]]; then
                            unset "local_enabled[${mod,,}]"
                        else
                            local_enabled["${mod,,}"]="$mod"
                        fi
                    else
                        echo "  ⚠️  Number out of range. Press Enter to continue."
                        read -r
                    fi
                fi
                ;;
            a|A)
                for mod in "${installed[@]}"; do
                    local_enabled["${mod,,}"]="$mod"
                done
                ;;
            n|N)
                local_enabled=()
                ;;
            s|S)
                # Commit changes
                for k in "${!ENABLED_MODS[@]}"; do unset "ENABLED_MODS[$k]"; done
                for k in "${!local_enabled[@]}"; do
                    ENABLED_MODS["$k"]="${local_enabled[$k]}"
                done
                _save_enabled
                echo
                echo "  ✅ Saved — $enabled_now mod(s) will load on next server start."
                
                # Fixed: Use proper if statement instead of A && B || C
                if is_server_up; then
                    echo "  ⚠️  Server is running — restart required for changes to take effect."
                fi
                return 0
                ;;
            q|Q|$'\033')
                echo "  ↩️  Cancelled — no changes saved."
                return 0
                ;;
        esac
    done
}

# ── mods router ──────────────────────────────────────────────────────────
# ── get_workshop_mod_name <id> ────────────────────────────────────────────────
# Fetches the mod title from the Steam Workshop API (no key required).
get_workshop_mod_name() {
    local mod_id="$1"
    
    # Check dependencies
    if ! command -v curl >/dev/null || ! command -v jq >/dev/null; then
        echo "Unknown"
        return
    fi
    
    local response
    # Fixed: Check curl exit code directly
    if ! response=$(curl -sf --max-time 8 \
        --data "itemcount=1&publishedfileids[0]=$mod_id" \
        "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/" 2>/dev/null); then
        echo "Unknown"
        return
    fi
    
    local title
    # Fixed: Check jq exit code directly
    if ! title=$(echo "$response" | jq -r '.response.publishedfiledetails[0].title // "Unknown"' 2>/dev/null); then
        echo "Unknown"
        return
    fi
    
    # Check if title is empty (jq succeeded but returned empty)
    if [[ -z "$title" ]]; then
        echo "Unknown"
        return
    fi
    
    echo "$title"
}

# Resolve names for multiple Workshop IDs in a single API call.
get_workshop_mod_names_batch() {
    local -n _batch_map="$1"; shift
    local ids=("$@")
    
    [[ ${#ids[@]} -eq 0 ]] && return
    
    # Check dependencies
    if ! command -v curl >/dev/null || ! command -v jq >/dev/null; then
        for id in "${ids[@]}"; do
            _batch_map["$id"]="Unknown"
        done
        return
    fi

    # Build POST body
    local body="itemcount=${#ids[@]}"
    local idx=0
    for id in "${ids[@]}"; do
        body+="&publishedfileids[${idx}]=${id}"
        (( idx++ ))
    done

    local response
    # Fixed: Check curl exit code directly
    if ! response=$(curl -sf --max-time 15 \
        --data "$body" \
        "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/" 2>/dev/null); then
        for id in "${ids[@]}"; do
            _batch_map["$id"]="Unknown"
        done
        return
    fi

    # Parse response
    local parsed_data
    # Fixed: Check jq exit code directly
    if ! parsed_data=$(echo "$response" | jq -r \
        '.response.publishedfiledetails[]? | [.publishedfileid, (.title // "Unknown")] | @tsv' \
        2>/dev/null); then
        for id in "${ids[@]}"; do
            _batch_map["$id"]="Unknown"
        done
        return
    fi
    
    # Process successful response
    if [[ -n "$parsed_data" ]]; then
        while IFS=$'\t' read -r id title; do
            [[ -n "$id" ]] && _batch_map["$id"]="${title:-Unknown}"
        done <<< "$parsed_data"
    fi

    # Fill any missing IDs (API may omit invalid ones)
    for id in "${ids[@]}"; do
        if [[ ! -v "_batch_map[$id]" ]]; then
            _batch_map["$id"]="Unknown"
        fi
    done
}

# ── mod_ids_add <url|id> ──────────────────────────────────────────────────────
# Accepts a raw Workshop ID or any Workshop URL and appends the ID to
# mod_ids.txt, skipping duplicates.
mod_ids_add() {
    local input="${1:-}"

    if [[ -z "$input" ]]; then
        echo "Usage: mods add <workshop_url_or_id>"
        echo
        echo "Examples:"
        echo "  mods add 2824688804"
        echo "  mods add https://steamcommunity.com/sharedfiles/filedetails/?id=2824688804"
        return 1
    fi

    # Extract numeric ID from URL or use raw input
    local mod_id
    local url_id
    url_id=$(echo "$input" | grep -oP '(?<=[?&]id=)[0-9]+' | head -1)
    if [[ -n "$url_id" ]]; then
        mod_id="$url_id"
    elif [[ "$input" =~ ^[0-9]+$ ]]; then
        mod_id="$input"
    else
        echo "❌ Could not extract a Workshop ID from: $input"
        echo "   Expected a numeric ID or a URL containing '?id=XXXXXXXXX'"
        return 1
    fi

    # Sanity check — Workshop IDs are typically 7-12 digits
    if [[ ${#mod_id} -lt 7 || ${#mod_id} -gt 12 ]]; then
        echo "❌ '$mod_id' doesn't look like a valid Workshop ID (expected 7-12 digits)"
        return 1
    fi

    # Ensure mod_ids.txt exists
    if [[ ! -f "$MOD_IDS_FILE" ]]; then
        mkdir -p "$(dirname "$MOD_IDS_FILE")"
        printf '# tModLoader Workshop Mod IDs\n# One ID per line. Lines starting with # are ignored.\n' > "$MOD_IDS_FILE"
        log_workshop "Created $MOD_IDS_FILE" "INFO"
    fi

    # Warn if placeholder/example lines are still present
    if grep -qE '^\.\.\.|^[0-9].*#\s*EXAMPLE' "$MOD_IDS_FILE" 2>/dev/null; then
        echo "  ⚠️  mod_ids.txt has example/placeholder entries (... or # EXAMPLE lines)."
        read -p "  Clean them out before adding? (yes/no): " -r _clean
        if [[ "$_clean" == "yes" ]]; then
            sed -i '/^\.\.\./d; /[0-9].*#[[:space:]]*EXAMPLE/d' "$MOD_IDS_FILE"
            echo "  ✅ Placeholder entries removed."
        fi
    fi

    # Check for duplicate — match ID at start of line, allowing trailing comments
    if grep -qE "^[[:space:]]*${mod_id}([[:space:]]|$)" "$MOD_IDS_FILE" 2>/dev/null; then
        local name
        name=$(get_workshop_mod_name "$mod_id")
        echo "ℹ️  Already in list: $name ($mod_id)"
        return 0
    fi

    # Look up mod name before adding
    local mod_name
    mod_name=$(get_workshop_mod_name "$mod_id")

    echo "$mod_id" >> "$MOD_IDS_FILE"
    echo "✅ Added: $mod_name ($mod_id)"
    log_workshop "Added mod: $mod_name ($mod_id)" "INFO"

    local total
    total=$(grep -vc "^[[:space:]]*#\|^[[:space:]]*$" "$MOD_IDS_FILE" 2>/dev/null || echo 0)
    echo "   mod_ids.txt now has $total mod(s)"
}

# ── mod_ids_clear ─────────────────────────────────────────────────────────────
# Wipes all mod IDs from mod_ids.txt, preserving comment header lines.
# Backs up the file first so it can be recovered if needed.
mod_ids_clear() {
    if [[ ! -f "$MOD_IDS_FILE" ]]; then
        echo "ℹ️  mod_ids.txt doesn't exist yet — nothing to clear."
        return 0
    fi

    local total
    total=$(grep -vc "^[[:space:]]*#\|^[[:space:]]*$" "$MOD_IDS_FILE" 2>/dev/null || echo 0)

    if [[ "$total" -eq 0 ]]; then
        echo "ℹ️  mod_ids.txt already has no mod IDs."
        return 0
    fi

    echo "⚠️  This will remove all $total mod ID(s) from mod_ids.txt."
    echo "   A backup will be saved to mod_ids.txt.bak"
    read -p "   Type YES to confirm: " -r confirm
    if [[ "$confirm" != "YES" ]]; then
        echo "   Cancelled."
        return 0
    fi

    cp "$MOD_IDS_FILE" "${MOD_IDS_FILE}.bak"

    # Keep comment/header lines, strip everything else
    grep "^[[:space:]]*#\|^[[:space:]]*$" "$MOD_IDS_FILE" > "${MOD_IDS_FILE}.tmp"
    mv "${MOD_IDS_FILE}.tmp" "$MOD_IDS_FILE"

    echo "✅ Cleared $total mod ID(s). Backup saved to mod_ids.txt.bak"
    log_workshop "Cleared $total mod IDs from $MOD_IDS_FILE (backup saved)" "INFO"
}

mods_cmd() {
    case "${1:-list}" in
        list)           mods_list ;;
        enable)         mods_enable  "${2:-}" ;;
        disable)        mods_disable "${2:-}" ;;
        pick|toggle)    mods_pick ;;
        add)            mod_ids_add   "${2:-}" ;;
        ids|show)       show_mod_ids ;;
        clear)          mod_ids_clear ;;
        *)
            echo "Mod management commands:"
            echo "  mods list              Show all installed mods and their status"
            echo "  mods enable  <n>       Enable a mod (or 'all')"
            echo "  mods disable <n>       Disable a mod (or 'all')"
            echo "  mods pick              Interactive toggle menu"
            echo "  mods add <url|id>      Add a Workshop URL or ID to mod_ids.txt"
            echo "  mods ids               Show queued mods in mod_ids.txt with names"
            echo "  mods clear             Clear all mod IDs from mod_ids.txt"
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────

# Show help
show_help() {
    cat << 'EOF'
🎮 tModLoader Steam Workshop Manager

Download and manage mods directly from Steam Workshop

Usage: ./tmod-workshop.sh [command]

Commands:
  download        Download mods from Steam Workshop using mod_ids.txt
  sync            Sync downloaded mods to server mods directory
  list            List downloaded workshop mods with details
  archive         Archive old mod versions, keep only latest
  cleanup         Clean up incomplete downloads and empty directories
  ids             Show/edit mod IDs configuration file
  status          Show workshop system status and configuration
  init            Initialize workshop system (create config files)
  help            Show this help message

Mod Load Management:
  mods list              Show installed mods with enabled/disabled status
  mods enable  <name>    Enable a mod (use 'all' to enable everything)
  mods disable <name>    Disable a mod (use 'all' to disable everything)
  mods pick              Interactive toggle menu — no nano needed

Workflow:
  1. ./tmod-workshop.sh init           # Initialize system
  2. Edit mod_ids.txt                  # Add desired mod IDs
  3. ./tmod-workshop.sh download       # Download from Workshop
  4. ./tmod-workshop.sh sync           # Copy to server
  5. ./tmod-workshop.sh mods pick      # Toggle which mods load
  6. ./tmod-workshop.sh archive        # Clean up old versions

Configuration:
  Required before downloading:
  - steamcmd_path=./Tools/SteamCMD/steamcmd.sh   # in Configs/serverconfig.txt
  Optional but recommended for larger download batches:
  - STEAM_USERNAME="your_steam_username"   # exported in your shell or Scripts/env.sh

Files:
  - mod_ids.txt: Workshop mod IDs (one per line)
  - Workshop downloads: $WORKSHOP_DOWNLOAD_DIR
  - Server mods: $MODS_DIR
  - Archived mods: $ARCHIVE_DIR

Examples:
  ./tmod-workshop.sh download          # Download all mods in mod_ids.txt
  ./tmod-workshop.sh sync              # Copy workshop mods to server
  ./tmod-workshop.sh list              # Show all downloaded mods
  ./tmod-workshop.sh mods pick         # Open interactive mod toggle menu
  ./tmod-workshop.sh mods enable CalamityMod
  ./tmod-workshop.sh mods disable ThoriumMod
  ./tmod-workshop.sh status            # Check system configuration

Features:
  ✅ Bulk mod downloading from Steam Workshop
  ✅ Version compatibility checking (2024.5+ and 2025.x)
  ✅ Automatic old version archival
  ✅ Enable/disable individual mods without editing files
  ✅ Interactive mod picker (works over SSH, no arrow keys needed)
  ✅ Integration with tmod-* script system
  ✅ Comprehensive logging and error handling
EOF
}

# Main execution
init_tmod

case "${1:-help}" in
    download)       download_mods ;;
    sync)           sync_downloaded_mods ;;
    list)           list_workshop_mods ;;
    archive)        archive_old_versions ;;
    cleanup)        cleanup_workshop ;;
    ids)            show_mod_ids ;;
    status)         show_status ;;
    init)           init_workshop ;;
    mods)           shift; mods_cmd "$@" ;;
    help|*)         show_help ;;
esac
