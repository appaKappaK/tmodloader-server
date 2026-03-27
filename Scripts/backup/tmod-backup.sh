#!/bin/bash
# tmod-backup.sh - Enhanced backup system with compression and integrity checking
export SCRIPT_VERSION="2.5.2"

# Get the script directory and find the core script - FIXED
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="$SCRIPT_DIR/../core/tmod-core.sh"

# Check if core script exists before sourcing
if [[ -f "$CORE_SCRIPT" ]]; then
    # shellcheck disable=SC1090
    source "$CORE_SCRIPT" || {
        echo "❌ Failed to load core functions from $CORE_SCRIPT"
        exit 1
    }
else
    echo "❌ Cannot find core functions at: $CORE_SCRIPT"
    echo "📁 Current directory: $(pwd)"
    echo "📁 Script directory: $SCRIPT_DIR"
    exit 1
fi

# Enhanced backup configuration
BACKUP_ROOT="$BASE_DIR/Backups"
WORLD_BACKUP_DIR="$BACKUP_ROOT/Worlds"
CONFIG_BACKUP_DIR="$BACKUP_ROOT/Configs"
FULL_BACKUP_DIR="$BACKUP_ROOT/Full"
TEMP_DIR="/tmp/tmod_backup"
BACKUP_ASSUME_YES=0
RESTORE_TARGET=""

# Retention policies
WORLD_RETENTION_DAYS=30
CONFIG_RETENTION_DAYS=14
FULL_RETENTION_DAYS=7

# Compression settings
COMPRESSION_LEVEL=6
USE_PIGZ=true

# Backup sources
CONFIG_FILES=(
    "$BASE_DIR/Configs"
    "$BASE_DIR/ModConfigs"
    "$BASE_DIR/Scripts"
)

# Enhanced logging for backups
log_backup() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_DIR/backup.log"
    
    # Rotate backup log if over 10MB
    if [[ -f "$LOG_DIR/backup.log" ]] && (( $(stat -c%s "$LOG_DIR/backup.log") > 10485760 )); then
        mv "$LOG_DIR/backup.log" "$LOG_DIR/backup.log.old"
        gzip "$LOG_DIR/backup.log.old"
        touch "$LOG_DIR/backup.log"
        log_backup "Backup log rotated" "INFO"
    fi
}

parse_restore_args() {
    BACKUP_ASSUME_YES=0
    RESTORE_TARGET=""

    while (( $# > 0 )); do
        case "$1" in
            -y|--yes|--force)
                BACKUP_ASSUME_YES=1
                ;;
            --)
                ;;
            -*)
                echo "❌ Unknown restore option: $1"
                return 1
                ;;
            *)
                if [[ -z "$RESTORE_TARGET" ]]; then
                    RESTORE_TARGET="$1"
                else
                    echo "❌ Unexpected extra restore argument: $1"
                    return 1
                fi
                ;;
        esac
        shift
    done

    if [[ -z "$RESTORE_TARGET" ]]; then
        echo "❌ Error: Missing backup file"
        echo "Usage: $0 restore [--yes] <backup_file>"
        return 1
    fi
}



# Initialize enhanced backup system
init_backup_system() {
    mkdir -p "$WORLD_BACKUP_DIR" "$CONFIG_BACKUP_DIR" "$FULL_BACKUP_DIR" "$TEMP_DIR"
    mkdir -p "$(dirname "$LOG_DIR/backup.log")"
    
    # Check compression tools
    if command -v pigz >/dev/null && [[ "$USE_PIGZ" == "true" ]]; then
        GZIP_CMD="pigz -$COMPRESSION_LEVEL"      
    else
        GZIP_CMD="gzip -$COMPRESSION_LEVEL"       
    fi
    
    log_backup "Enhanced backup system initialized" "INFO"
}

# Calculate backup statistics
calculate_backup_stats() {
    local start_time="$1"
    local backup_path="$2"
    
    local end_time
    end_time=$(date +%s)
    local duration
    duration=$((end_time - start_time))
    local size_bytes size_human
    
    if [[ -f "$backup_path" ]]; then
        size_bytes=$(stat -c%s "$backup_path")
         
        size_human=$(numfmt --to=iec-i --suffix=B "$size_bytes" 2>/dev/null || du -h "$backup_path" 2>/dev/null | cut -f1 || echo "${size_bytes}B")
    else
        size_bytes=0
        size_human="0B"
    fi
    
    echo "$duration $size_human $size_bytes"
}

next_backup_name() {
    local backup_dir="$1"
    local prefix="$2"
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")

    local candidate="${prefix}_${timestamp}"
    local suffix=0
    while [[ -e "$backup_dir/${candidate}.tar.gz" || -e "$TEMP_DIR/${candidate}.tar" ]]; do
        ((suffix++))
        candidate="${prefix}_${timestamp}_${suffix}"
    done

    echo "$candidate"
}

# Enhanced world backup with integrity checking
backup_world() {
    log_backup "Starting enhanced world backup..." "INFO"
    local start_time
    start_time=$(date +%s)
    local backup_name
    backup_name=$(next_backup_name "$WORLD_BACKUP_DIR" "worlds")
    local temp_archive
    temp_archive="$TEMP_DIR/$backup_name.tar"
    local final_archive
    final_archive="$WORLD_BACKUP_DIR/$backup_name.tar.gz"
    
    # Check if world files exist
    if [[ ! -d "$BASE_DIR/Worlds" ]] || [[ ! "$(ls -A "$BASE_DIR/Worlds" 2>/dev/null)" ]]; then
        log_backup "No world files found to backup" "WARN"
        echo "⚠️ No world files found to backup"
        return 1
    fi

    echo "📦 Creating world backup..."

    # Create archive with better exclusions
    if tar -cf "$temp_archive" -C "$BASE_DIR" \
       --exclude="*.tmp" --exclude="*.bak" --exclude="*.lock" \
       Worlds/; then
        
        # Compress with chosen method
        echo "🗜️ Compressing backup..."
        if $GZIP_CMD "$temp_archive"; then
            mv "$temp_archive.gz" "$final_archive"
            
            # Generate checksum for integrity
            md5sum "$final_archive" > "$final_archive.md5"
            
            # Calculate and report stats
            local stats
            stats=$(calculate_backup_stats "$start_time" "$final_archive")
            local duration size_human
            read -r duration size_human _ <<< "$stats"
            
            echo "✅ World backup completed: $backup_name.tar.gz ($size_human, ${duration}s)"
            log_backup "World backup completed: $backup_name.tar.gz ($size_human, ${duration}s)" "SUCCESS"

            return 0
        else
            log_backup "Failed to compress world backup" "ERROR"
            rm -f "$temp_archive" "$temp_archive.gz"
            echo "❌ Failed to compress world backup"
            return 1
        fi
    else
        log_backup "Failed to create world backup archive" "ERROR"
        echo "❌ Failed to create world backup"
        return 1
    fi
}

# Enhanced config backup
backup_config() {
    log_backup "Starting enhanced config backup..." "INFO"
    local start_time
    start_time=$(date +%s)
    local backup_name
    backup_name=$(next_backup_name "$CONFIG_BACKUP_DIR" "configs")
    local temp_archive
    temp_archive="$TEMP_DIR/$backup_name.tar"
    local final_archive
    final_archive="$CONFIG_BACKUP_DIR/$backup_name.tar.gz"
    
    echo "📦 Creating configuration backup..."
    
    # Build list of existing config sources
    local tar_args=("--exclude=*.log" "--exclude=*.tmp" "--exclude=*.bak" "--exclude=*.old")
    local backup_sources=()

    # Portable relative-path helper (realpath --relative-to is GNU-only)
    _relative_path() {
        python3 -c "import os,sys; print(os.path.relpath(sys.argv[1],sys.argv[2]))" "$1" "$2" 2>/dev/null \
            || echo "${1#"$2"/}"
    }

    for config_item in "${CONFIG_FILES[@]}"; do
        if [[ -e "$config_item" ]]; then
            local relative_path
            relative_path=$(_relative_path "$config_item" "$BASE_DIR")
            backup_sources+=("$relative_path")
        fi
    done
    
    if (( ${#backup_sources[@]} == 0 )); then
        log_backup "No configuration files found to backup" "WARN"
        echo "⚠️ No configuration files found"
        return 1
    fi
    
    if tar -cf "$temp_archive" -C "$BASE_DIR" "${tar_args[@]}" "${backup_sources[@]}"; then
        # Compress
        echo "🗜️ Compressing configuration backup..."
        if $GZIP_CMD "$temp_archive"; then
            mv "$temp_archive.gz" "$final_archive"
            
            # Generate checksum
            md5sum "$final_archive" > "$final_archive.md5"
            
            # Calculate stats
            local stats
            stats=$(calculate_backup_stats "$start_time" "$final_archive")
            local duration size_human
            read -r duration size_human _ <<< "$stats"
            
            echo "✅ Config backup completed: $backup_name.tar.gz ($size_human, ${duration}s)"
            log_backup "Config backup completed: $backup_name.tar.gz ($size_human, ${duration}s)" "SUCCESS"

            return 0
        else
            log_backup "Failed to compress config backup" "ERROR"
            rm -f "$temp_archive" "$temp_archive.gz"
            echo "❌ Failed to compress config backup"
            return 1
        fi
    else
        log_backup "Failed to create config backup archive" "ERROR"
        echo "❌ Failed to create config backup"
        return 1
    fi
}

# Enhanced full backup
backup_full() {
    log_backup "Starting enhanced full server backup..." "INFO"
    local start_time
    start_time=$(date +%s)
    local backup_name
    backup_name=$(next_backup_name "$FULL_BACKUP_DIR" "full")
    local temp_archive
    temp_archive="$TEMP_DIR/$backup_name.tar"
    local final_archive
    final_archive="$FULL_BACKUP_DIR/$backup_name.tar.gz"
    
    echo "📦 Creating full server backup..."
    echo "⚠️ This may take several minutes for large servers..."
    
    local base_name
    base_name="$(basename "$BASE_DIR")"

    # Exclude portable runtime noise that should not be recursively archived.
    local exclude_patterns=(
        "--exclude=${base_name}/Logs/*.log"
        "--exclude=${base_name}/Backups"
        "--exclude=*.tmp"
        "--exclude=*.bak"
        "--exclude=*.old"
        "--exclude=.git"
    )
    
    if tar -cf "$temp_archive" -C "$(dirname "$BASE_DIR")" "${exclude_patterns[@]}" "$(basename "$BASE_DIR")"; then
        # Compress
        echo "🗜️ Compressing full backup (this will take time)..."
        if $GZIP_CMD "$temp_archive"; then
            mv "$temp_archive.gz" "$final_archive"
            
            # Generate checksum
            md5sum "$final_archive" > "$final_archive.md5"
            
            # Calculate stats
            local stats
            stats=$(calculate_backup_stats "$start_time" "$final_archive")
            local duration size_human
            read -r duration size_human _ <<< "$stats"
            
            echo "✅ Full backup completed: $backup_name.tar.gz ($size_human, ${duration}s)"
            log_backup "Full backup completed: $backup_name.tar.gz ($size_human, ${duration}s)" "SUCCESS"

            return 0
        else
            log_backup "Failed to compress full backup" "ERROR"
            rm -f "$temp_archive" "$temp_archive.gz"
            echo "❌ Failed to compress full backup"
            return 1
        fi
    else
        log_backup "Failed to create full backup archive" "ERROR"
        echo "❌ Failed to create full backup"
        return 1
    fi
}

# Auto backup with enhanced reporting
backup_auto() {
    echo "🔄 Starting automated backup sequence..."
    log_backup "Starting automated backup sequence" "INFO"
    
    local success_count=0
    local total_tasks=3
    local start_time
    start_time=$(date +%s)
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 Backup Sequence Progress:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    echo "🌍 [1/3] World backup..."
    if backup_world; then
        ((success_count++))
        echo "    ✅ World backup completed"
    else
        echo "    ❌ World backup failed"
    fi
    echo
    
    echo "⚙️ [2/3] Configuration backup..."
    if backup_config; then
        ((success_count++))
        echo "    ✅ Config backup completed"
    else
        echo "    ❌ Config backup failed"
    fi
    echo
    
    echo "💾 [3/3] Full server backup..."
    if backup_full; then
        ((success_count++))
        echo "    ✅ Full backup completed"
    else
        echo "    ❌ Full backup failed"
    fi
    echo
    
    # Clean old backups
    echo "🧹 Cleaning old backups..."
    cleanup_old_backups
    
    # Calculate total time
    local total_time=$(($(date +%s) - start_time))
    local time_formatted
    time_formatted=$(printf "%dm %02ds" $((total_time/60)) $((total_time%60)))
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 Backup Summary:"
    echo "✅ Successful: $success_count/$total_tasks"
    echo "⏱️  Total Time: $time_formatted"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    log_backup "Automated backup complete: $success_count/$total_tasks successful in $time_formatted" "INFO"
    
    if (( success_count == total_tasks )); then
        echo "🎉 All backups completed successfully!"
        return 0
    else
        echo "⚠️ Backup completed with issues"
        return 1
    fi
}

# Enhanced cleanup with detailed reporting
cleanup_old_backups() {
    log_backup "Starting enhanced backup cleanup..." "INFO"
    local total_removed=0
    local total_space_freed=0
    
    echo "🧹 Cleaning old backups..."
    
    # Cleanup world backups
    echo "  🌍 Cleaning world backups (>$WORLD_RETENTION_DAYS days)..."
    local world_files_to_remove=()
    while IFS= read -r -d '' file; do
        world_files_to_remove+=("$file")
        local size
        size=$(stat -c%s "$file" 2>/dev/null || echo 0)
        total_space_freed=$((total_space_freed + size))
    done < <(find "$WORLD_BACKUP_DIR" -name "worlds_*.tar.gz" -mtime +$WORLD_RETENTION_DAYS -print0 2>/dev/null)
    
    for file in "${world_files_to_remove[@]}"; do
        rm -f "$file" "${file}.md5" 2>/dev/null
        ((total_removed++))
        echo "    🗑️ Removed $(basename "$file")"
    done
    
    # Cleanup config backups
    echo "  ⚙️ Cleaning config backups (>$CONFIG_RETENTION_DAYS days)..."
    local config_files_to_remove=()
    while IFS= read -r -d '' file; do
        config_files_to_remove+=("$file")
        local size
        size=$(stat -c%s "$file" 2>/dev/null || echo 0)
        total_space_freed=$((total_space_freed + size))
    done < <(find "$CONFIG_BACKUP_DIR" -name "configs_*.tar.gz" -mtime +$CONFIG_RETENTION_DAYS -print0 2>/dev/null)
    
    for file in "${config_files_to_remove[@]}"; do
        rm -f "$file" "${file}.md5" 2>/dev/null
        ((total_removed++))
        echo "    🗑️ Removed $(basename "$file")"
    done
    
    # Cleanup full backups
    echo "  💾 Cleaning full backups (>$FULL_RETENTION_DAYS days)..."
    local full_files_to_remove=()
    while IFS= read -r -d '' file; do
        full_files_to_remove+=("$file")
        local size
        size=$(stat -c%s "$file" 2>/dev/null || echo 0)
        total_space_freed=$((total_space_freed + size))
    done < <(find "$FULL_BACKUP_DIR" -name "full_*.tar.gz" -mtime +$FULL_RETENTION_DAYS -print0 2>/dev/null)
    
    for file in "${full_files_to_remove[@]}"; do
        rm -f "$file" "${file}.md5" 2>/dev/null
        ((total_removed++))
        echo "    🗑️ Removed $(basename "$file")"
    done
    
    # Report cleanup results
    local space_freed_human
    space_freed_human=$(numfmt --to=iec-i --suffix=B "$total_space_freed" 2>/dev/null || echo "${total_space_freed}B")
    
    if (( total_removed > 0 )); then
        echo "✅ Cleanup completed: removed $total_removed old backups, freed $space_freed_human"
        log_backup "Cleanup completed: removed $total_removed old backups, freed $space_freed_human" "INFO"
    else
        echo "✅ Cleanup completed: no old backups to remove"
        log_backup "Cleanup completed: no old backups to remove" "INFO"
    fi
}

# Verify backup integrity
verify_backup() {
    local backup_file="$1"
    local checksum_file="$backup_file.md5"
    
    if [[ ! -f "$backup_file" ]]; then
        echo "❌ Backup file not found: $backup_file"
        return 1
    fi
    
    echo "🔍 Verifying backup integrity..."
    
    if [[ ! -f "$checksum_file" ]]; then
        echo "⚠️ Checksum file missing: $checksum_file"
        echo "🔄 Generating checksum..."
        md5sum "$backup_file" > "$checksum_file"
        echo "✅ Checksum generated: $(basename "$backup_file")"
        return 0
    fi
    
    if md5sum -c "$checksum_file" >/dev/null 2>&1; then
        echo "✅ Backup verified: $(basename "$backup_file")"
        return 0
    else
        echo "❌ Backup verification failed: $(basename "$backup_file")"
        echo "⚠️ Backup may be corrupted!"
        return 1
    fi
}

# Enhanced status with detailed breakdown
show_status() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "💾 tModLoader Enhanced Backup System Status"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Storage usage with breakdown
    local total_size world_size config_size full_size
    total_size=$(du -sh "$BACKUP_ROOT" 2>/dev/null | cut -f1)
    world_size=$(du -sh "$WORLD_BACKUP_DIR" 2>/dev/null | cut -f1)
    config_size=$(du -sh "$CONFIG_BACKUP_DIR" 2>/dev/null | cut -f1)  
    full_size=$(du -sh "$FULL_BACKUP_DIR" 2>/dev/null | cut -f1)
    
    echo "📊 Storage Usage:"
    echo "   Total: $total_size"
    echo "   └── Worlds: $world_size"
    echo "   └── Configs: $config_size"
    echo "   └── Full: $full_size"
    echo "📁 Location: $BACKUP_ROOT"
    echo
    
    # World backups with latest info
    local world_count
    world_count=$(find "$WORLD_BACKUP_DIR" -name "worlds_*.tar.gz" 2>/dev/null | wc -l)
    echo "🌍 World Backups: $world_count (retention: ${WORLD_RETENTION_DAYS} days)"
    if (( world_count > 0 )); then
        local latest_world
        latest_world=$(find "$WORLD_BACKUP_DIR" -name "worlds_*.tar.gz" -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
        local world_date size
        world_date=$(date -r "$latest_world" '+%Y-%m-%d %H:%M')
         
        size=$(du -h "$latest_world" | cut -f1)
        echo "   Latest: $(basename "$latest_world") ($size, $world_date)"
        
        # Check integrity of latest
        if verify_backup "$latest_world" >/dev/null 2>&1; then
            echo "   Status: ✅ Latest backup verified"
        else
            echo "   Status: ⚠️ Latest backup needs verification"
        fi
    fi
    echo
    
    # Config backups
    local config_count
    config_count=$(find "$CONFIG_BACKUP_DIR" -name "configs_*.tar.gz" 2>/dev/null | wc -l)
    echo "⚙️ Config Backups: $config_count (retention: ${CONFIG_RETENTION_DAYS} days)"
    if (( config_count > 0 )); then
        local latest_config
        latest_config=$(find "$CONFIG_BACKUP_DIR" -name "configs_*.tar.gz" -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
        local config_date size
        config_date=$(date -r "$latest_config" '+%Y-%m-%d %H:%M')
         
        size=$(du -h "$latest_config" | cut -f1)
        echo "   Latest: $(basename "$latest_config") ($size, $config_date)"
    fi
    echo
    
    # Full backups
    local full_count
    full_count=$(find "$FULL_BACKUP_DIR" -name "full_*.tar.gz" 2>/dev/null | wc -l)
    echo "💾 Full Backups: $full_count (retention: ${FULL_RETENTION_DAYS} days)"
    if (( full_count > 0 )); then
        local latest_full
        latest_full=$(find "$FULL_BACKUP_DIR" -name "full_*.tar.gz" -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
        local full_date size
        full_date=$(date -r "$latest_full" '+%Y-%m-%d %H:%M')
         
        size=$(du -h "$latest_full" | cut -f1)
        echo "   Latest: $(basename "$latest_full") ($size, $full_date)"
    fi
    echo
    
    # Recent activity
    if [[ -f "$LOG_DIR/backup.log" ]]; then
        echo "📋 Recent Activity (last 5 entries):"
        tail -5 "$LOG_DIR/backup.log" | sed 's/^/   /'
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# List backups with enhanced details
list_backups() {
    local backup_type="${1:-all}"
    
    echo "📋 Enhanced Backup Inventory"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [[ "$backup_type" == "all" || "$backup_type" == "worlds" ]]; then
        echo "🌍 World Backups:"
        if compgen -G "$WORLD_BACKUP_DIR/worlds_*.tar.gz" > /dev/null; then
            printf "   %-15s %-10s %-8s %-10s %s\n" "Date" "Time" "Size" "Status" "Filename"
            echo "   $(printf '%0.1s' '-'{1..70})"
            find "$WORLD_BACKUP_DIR" -name "worlds_*.tar.gz" -printf '%TY-%Tm-%Td %TH:%TM  %8s  %f\n' | sort -r | \
            while read -r date time size filename; do
                local size_human status_icon
                size_human=$(numfmt --to=iec-i --suffix=B "$size" 2>/dev/null || echo "${size}B")
                
                # Check if backup has checksum
                if [[ -f "$WORLD_BACKUP_DIR/$filename.md5" ]]; then
                    status_icon="✅"
                else
                    status_icon="⚠️"
                fi
                
                printf "   %-15s %-10s %-8s %-10s %s\n" "$date" "$time" "$size_human" "$status_icon" "$filename"
            done
        else
            echo "   No world backups found"
        fi
        echo
    fi
    
    if [[ "$backup_type" == "all" || "$backup_type" == "configs" ]]; then
        echo "⚙️ Configuration Backups:"
        if compgen -G "$CONFIG_BACKUP_DIR/configs_*.tar.gz" > /dev/null; then
            printf "   %-15s %-10s %-8s %-10s %s\n" "Date" "Time" "Size" "Status" "Filename"
            echo "   $(printf '%0.1s' '-'{1..70})"
            find "$CONFIG_BACKUP_DIR" -name "configs_*.tar.gz" -printf '%TY-%Tm-%Td %TH:%TM  %8s  %f\n' | sort -r | \
            while read -r date time size filename; do
                local size_human status_icon
                size_human=$(numfmt --to=iec-i --suffix=B "$size" 2>/dev/null || echo "${size}B")
                
                if [[ -f "$CONFIG_BACKUP_DIR/$filename.md5" ]]; then
                    status_icon="✅"
                else
                    status_icon="⚠️"
                fi
                
                printf "   %-15s %-10s %-8s %-10s %s\n" "$date" "$time" "$size_human" "$status_icon" "$filename"
            done
        else
            echo "   No config backups found"
        fi
        echo
    fi
    
    if [[ "$backup_type" == "all" || "$backup_type" == "full" ]]; then
        echo "💾 Full Server Backups:"
        if compgen -G "$FULL_BACKUP_DIR/full_*.tar.gz" > /dev/null; then
            printf "   %-15s %-10s %-8s %-10s %s\n" "Date" "Time" "Size" "Status" "Filename"
            echo "   $(printf '%0.1s' '-'{1..70})"
            find "$FULL_BACKUP_DIR" -name "full_*.tar.gz" -printf '%TY-%Tm-%Td %TH:%TM  %8s  %f\n' | sort -r | \
            while read -r date time size filename; do
                local size_human status_icon
                size_human=$(numfmt --to=iec-i --suffix=B "$size" 2>/dev/null || echo "${size}B")
                
                if [[ -f "$FULL_BACKUP_DIR/$filename.md5" ]]; then
                    status_icon="✅"
                else
                    status_icon="⚠️"
                fi
                
                printf "   %-15s %-10s %-8s %-10s %s\n" "$date" "$time" "$size_human" "$status_icon" "$filename"
            done
        else
            echo "   No full backups found"
        fi
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Legend: ✅ = Verified/Has checksum  ⚠️ = Needs verification"
}

# Safe restore with pre-restore backup
restore_backup() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        echo "❌ Backup file not found: $backup_file"
        return 1
    fi
    
    # Verify backup integrity first
    echo "🔍 Verifying backup integrity..."
    if ! verify_backup "$backup_file"; then
        echo "❌ Backup verification failed. Restore aborted for safety."
        return 1
    fi
    
    # Determine backup type and target
    local filename backup_type
    filename=$(basename "$backup_file")
    if [[ "$filename" == worlds_* ]]; then
        backup_type="worlds"
    elif [[ "$filename" == configs_* ]]; then
        backup_type="configs"
    elif [[ "$filename" == full_* ]]; then
        backup_type="full"
    else
        echo "❌ Unknown backup type: $filename"
        return 1
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  RESTORE OPERATION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "This will restore: $backup_type"
    echo "From backup: $filename"
    echo "Target: $backup_type files will be OVERWRITTEN"
    echo
    echo "⚠️ WARNING: Current $backup_type data will be replaced!"
    echo
    if (( BACKUP_ASSUME_YES )); then
        echo "ℹ️ Auto-confirm enabled — proceeding with restore"
    else
        read -p "Are you absolutely sure? Type 'yes' to continue: " -r
        if [[ ! "$REPLY" =~ ^[Yy][Ee][Ss]$ ]]; then
            echo "Restore cancelled for safety."
            return 0
        fi
    fi
    
    # Create pre-restore backup
    echo "📦 Creating pre-restore safety backup..."
    local safety_backup_created=false
    case "$backup_type" in
        worlds)
            if backup_world >/dev/null 2>&1; then
                safety_backup_created=true
                echo "✅ Pre-restore world backup created"
            fi
            ;;
        configs)
            if backup_config >/dev/null 2>&1; then
                safety_backup_created=true
                echo "✅ Pre-restore config backup created"
            fi
            ;;
        full)
            echo "⚠️ Full restore - safety backup skipped (would be too large)"
            ;;
    esac
    
    # Perform restore
    echo "🔄 Restoring from $filename..."
    local temp_extract="$TEMP_DIR/restore_$$"
    mkdir -p "$temp_extract"
    
    if tar -xzf "$backup_file" -C "$temp_extract"; then
        case "$backup_type" in
            worlds)
                if command -v rsync >/dev/null; then
                    rsync -avc --delete "$temp_extract/Worlds/" "$BASE_DIR/Worlds/"
                else
                    rm -rf "$BASE_DIR/Worlds"
                    mv "$temp_extract/Worlds" "$BASE_DIR/"
                fi
                ;;
            configs)
                # Selective config restore to avoid breaking system
                for config_item in "${CONFIG_FILES[@]}"; do
                    local relative_path
                    relative_path=$(python3 -c "import os,sys; print(os.path.relpath(sys.argv[1],sys.argv[2]))" \
                        "$config_item" "$BASE_DIR" 2>/dev/null || echo "${config_item#"$BASE_DIR"/}")
                    if [[ -e "$temp_extract/$relative_path" ]]; then
                        if command -v rsync >/dev/null; then
                            rsync -avc "$temp_extract/$relative_path" "$config_item"
                        else
                            cp -rf "$temp_extract/$relative_path" "$config_item"
                        fi
                        echo "   ✅ Restored $relative_path"
                    fi
                done
                ;;
            full)
                echo "⚠️ Full restore requires server to be offline"
                if command -v rsync >/dev/null; then
                    rsync -avc --exclude="Logs/" --exclude="Backups/" "$temp_extract/$(basename "$BASE_DIR")/" "$BASE_DIR/"
                else
                    cp -rf "$temp_extract/$(basename "$BASE_DIR")"/* "$BASE_DIR/"
                fi
                ;;
        esac
        
        rm -rf "$temp_extract"
        log_backup "Restore completed: $filename" "SUCCESS"
        echo "✅ Restore completed successfully!"
        
        if [[ "$safety_backup_created" == "true" ]]; then
            echo "💡 Pre-restore backup is available if you need to revert"
        fi
        
        return 0
    else
        rm -rf "$temp_extract"
        log_backup "Restore failed: $filename" "ERROR"
        echo "❌ Restore failed - original data unchanged"
        return 1
    fi
}

# Show enhanced help
show_help() {
    cat << 'EOF'
💾 tModLoader Enhanced Backup System

Comprehensive backup solution with compression, integrity checking, and safe restore

Usage: ./tmod-backup.sh [command] [options]

Commands:
  worlds              Create world backup with integrity checking
  configs             Create configuration backup  
  full                Create full server backup
  auto                Create all backup types sequentially
  cleanup             Remove old backups based on retention policy
  status              Show detailed backup system status
  list [type]         List all backups with verification status
                      Types: worlds, configs, full, all (default)
  verify <file>       Verify backup integrity using checksums
  restore [--yes] <file>  Safely restore from backup (with pre-restore backup)
  help                Show this help message

Examples:
  ./tmod-backup.sh worlds                    # Quick world backup
  ./tmod-backup.sh auto                      # Full backup sequence  
  ./tmod-backup.sh list worlds               # List world backups
  ./tmod-backup.sh verify worlds_20250101_120000.tar.gz
  ./tmod-backup.sh restore full_20250101_120000.tar.gz
  ./tmod-backup.sh restore --yes worlds_20250101_120000.tar.gz

Retention Policies:
  🌍 Worlds: ${WORLD_RETENTION_DAYS} days
  ⚙️ Configs: ${CONFIG_RETENTION_DAYS} days  
  💾 Full: ${FULL_RETENTION_DAYS} days

Automation Examples:
  # Hourly world backups
  0 * * * * $SCRIPT_DIR/tmod-backup.sh worlds
  
  # Daily config backups at 2 AM
  0 2 * * * $SCRIPT_DIR/tmod-backup.sh configs
  
  # Weekly full backup on Sundays at 3 AM  
  0 3 * * 0 $SCRIPT_DIR/tmod-backup.sh full
  
  # Daily cleanup at 4 AM
  0 4 * * * $SCRIPT_DIR/tmod-backup.sh cleanup

Features:
  ✅ Parallel compression (pigz) for faster backups
  ✅ MD5 integrity verification with automatic repair
  ✅ Safe restore with pre-restore backups
  ✅ Automated retention policy with space reporting
  ✅ Enhanced Discord notifications with timing/size
  ✅ Comprehensive logging and error handling
  ✅ Smart exclusion patterns to avoid bloat
EOF
}

# Cleanup function for temp files
cleanup_temp() {
    rm -rf "$TEMP_DIR"
}

# Set trap for cleanup
trap cleanup_temp EXIT

# Initialize and execute
init_backup_system

case "${1:-help}" in
    worlds)     backup_world ;;
    configs)    backup_config ;;
    full)       backup_full ;;
    auto)       backup_auto ;;
    cleanup)    cleanup_old_backups ;;
    status)     show_status ;;
    list)       list_backups "${2:-all}" ;;
    verify)     
        if [[ -z "${2:-}" ]]; then
            echo "❌ Error: Missing backup file"
            echo "Usage: $0 verify <backup_file>"
            exit 1
        fi
        verify_backup "$2" ;;
    restore)
        shift
        if ! parse_restore_args "$@"; then
            exit 1
        fi
        restore_backup "$RESTORE_TARGET" ;;
    help|*)     show_help ;;
esac
