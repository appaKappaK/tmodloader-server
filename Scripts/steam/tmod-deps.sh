#!/bin/bash
# tmod-deps.sh - Mod Dependency Resolution for tModLoader Server
export SCRIPT_VERSION="2.5.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="$SCRIPT_DIR/../core/tmod-core.sh"
WORKSHOP_SCRIPT="$SCRIPT_DIR/tmod-workshop.sh"

if [[ -f "$CORE_SCRIPT" ]]; then
    # shellcheck disable=SC1090
    source "$CORE_SCRIPT" 2>/dev/null || {
        echo "⚠️ Could not load core functions from $CORE_SCRIPT"
    }
else
    echo "ℹ️ Core functions not found at $CORE_SCRIPT, using fallback paths"
fi

init_tmod

log_dependency() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_DIR/dependency.log"
}

# ─── Dependency extraction ────────────────────────────────────────────────────

# Extract dependency list from a .tmod file (zip archive with description.json)
_mod_deps() {
    local mod_file="$1"
    if ! command -v unzip >/dev/null 2>&1; then
        log_dependency "unzip not installed — cannot read mod metadata" "WARN"
        return 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        log_dependency "jq not installed — cannot parse mod metadata" "WARN"
        return 1
    fi
    unzip -p "$mod_file" "description.json" 2>/dev/null \
        | jq -r '.dependencies[]?' 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────────────

check_dependencies() {
    echo "ℹ️ Scanning for missing dependencies..."
    local missing_count=0
    local missing_list=()

    local mod_files=()
    mapfile -t mod_files < <(find "$MODS_DIR" -maxdepth 1 -name "*.tmod" 2>/dev/null)

    if [[ ${#mod_files[@]} -eq 0 ]]; then
        echo "⚠️ No mod files found in $MODS_DIR"
        return 0
    fi

    for mod_file in "${mod_files[@]}"; do
        local mod_name
        mod_name=$(basename "$mod_file" .tmod)

        local deps=()
        mapfile -t deps < <(_mod_deps "$mod_file")

        for dep in "${deps[@]}"; do
            [[ -z "$dep" ]] && continue
            if [[ ! -f "$MODS_DIR/$dep.tmod" ]]; then
                echo "⚠️ Missing: $dep  (required by $mod_name)"
                missing_list+=("$dep:$mod_name")
                (( missing_count++ ))
            fi
        done
    done

    if [[ $missing_count -eq 0 ]]; then
        echo "✅ No missing dependencies found"
        log_dependency "Dependency check: all satisfied" "INFO"
    else
        echo
        echo "⚠️ Found $missing_count missing dependencies"
        echo "ℹ️ Unique missing:"
        printf '%s\n' "${missing_list[@]}" | cut -d: -f1 | sort -u | while IFS= read -r dep; do
            echo "  $dep"
        done
        log_dependency "Dependency check: $missing_count missing" "WARN"
    fi

    # Cap at 254 so exit code never wraps to 0 at 256
    return $(( missing_count > 254 ? 254 : missing_count ))
}

# ─────────────────────────────────────────────────────────────────────────────

install_dependencies() {
    echo "ℹ️ Installing missing dependencies..."
    local installed_count=0
    local failed_count=0

    local mod_files=()
    mapfile -t mod_files < <(find "$MODS_DIR" -maxdepth 1 -name "*.tmod" 2>/dev/null)

    declare -A missing_deps
    for mod_file in "${mod_files[@]}"; do
        local mod_name
        mod_name=$(basename "$mod_file" .tmod)

        local deps=()
        mapfile -t deps < <(_mod_deps "$mod_file")

        for dep in "${deps[@]}"; do
            [[ -z "$dep" ]] && continue
            [[ ! -f "$MODS_DIR/$dep.tmod" ]] && missing_deps["$dep"]="$mod_name"
        done
    done

    if [[ ${#missing_deps[@]} -eq 0 ]]; then
        echo "✅ No missing dependencies to install"
        return 0
    fi

    echo "ℹ️ Found ${#missing_deps[@]} unique missing dependencies"
    echo

    for dep in "${!missing_deps[@]}"; do
        local required_by="${missing_deps[$dep]}"
        echo "ℹ️ Installing: $dep  (required by $required_by)"

        local workshop_id
        workshop_id=$(find_workshop_id "$dep")

        if [[ -z "$workshop_id" ]]; then
            echo "  ❌ No Workshop ID found for $dep"
            echo "     Add it to Configs/workshop_map.json to enable auto-install"
            log_dependency "No workshop ID for: $dep (required by $required_by)" "ERROR"
            (( failed_count++ ))
            continue
        fi

        # Delegate entirely to tmod-workshop.sh so we use $STEAMCMD_PATH,
        # $STEAM_USERNAME, rate-limit handling, and skip-if-exists logic.
        if [[ ! -x "$WORKSHOP_SCRIPT" ]]; then
            echo "  ❌ tmod-workshop.sh not found at $WORKSHOP_SCRIPT"
            log_dependency "Workshop script missing — cannot install $dep" "ERROR"
            (( failed_count++ ))
            continue
        fi

        "$WORKSHOP_SCRIPT" mods add "$workshop_id" >/dev/null 2>&1
        if "$WORKSHOP_SCRIPT" download "$workshop_id"; then
            echo "  ✅ Installed $dep"
            log_dependency "Installed dependency: $dep (required by $required_by)" "INFO"
            (( installed_count++ ))
        else
            echo "  ❌ Download failed for $dep"
            log_dependency "Failed to install: $dep (required by $required_by)" "ERROR"
            (( failed_count++ ))
        fi

        sleep 2
    done

    echo
    echo "ℹ️ Done: ✅ $installed_count installed  ❌ $failed_count failed"
    log_dependency "Dependency install: $installed_count installed, $failed_count failed" "INFO"

    [[ $installed_count -gt 0 ]] && echo "⚠️ Restart the server for changes to take effect"

    return $(( failed_count > 254 ? 254 : failed_count ))
}

# ─────────────────────────────────────────────────────────────────────────────

# Find Workshop ID for a mod name.
# Checks: (1) local workshop_map.json, (2) existing downloaded workshop mods,
# (3) hardcoded table of common mods.
find_workshop_id() {
    local mod_name="$1"

    # 1) Local mapping file
    local workshop_map="$BASE_DIR/Configs/workshop_map.json"
    if [[ -f "$workshop_map" ]] && command -v jq >/dev/null 2>&1; then
        local workshop_id
        workshop_id=$(jq -r --arg mod "$mod_name" '.[$mod] // empty' "$workshop_map" 2>/dev/null)
        if [[ -n "$workshop_id" ]]; then
            echo "$workshop_id"
            return 0
        fi
    fi

    # 2) Scan already-downloaded workshop mods
    if [[ -d "$WORKSHOP_DIR" ]]; then
        local workshop_id
        workshop_id=$(find "$WORKSHOP_DIR" -name "*.tmod" -exec sh -c '
            search_name="$1"; shift
            for mod_path; do
                result=$(unzip -p "$mod_path" "description.json" 2>/dev/null \
                    | jq -e --arg name "$search_name" ".name == \$name" 2>/dev/null)
                if [[ "$result" == "true" ]]; then
                    basename "$(dirname "$mod_path")"
                    exit 0
                fi
            done
            exit 1
        ' sh "$mod_name" {} + 2>/dev/null)

        if [[ -n "$workshop_id" ]]; then
            echo "$workshop_id"
            return 0
        fi
    fi

    # 3) Hardcoded fallback for common mods
    case "$mod_name" in
        "CalamityMod")      echo "2563309347" ;;
        "ThoriumMod")       echo "2565639705" ;;
        "MagicStorage")     echo "2568564996" ;;
        "RecipeBrowser")    echo "2564692595" ;;
        "BossChecklist")    echo "2564692805" ;;
        "FargosMutantMod")  echo "2559899376" ;;
        "VeinMiner")        echo "2564593266" ;;
        "AlchemistNPCLite") echo "2537483679" ;;
        *) return 1 ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────

show_dependency_tree() {
    echo "ℹ️ Generating dependency tree..."

    local mod_files=()
    mapfile -t mod_files < <(find "$MODS_DIR" -maxdepth 1 -name "*.tmod" 2>/dev/null | sort)

    if [[ ${#mod_files[@]} -eq 0 ]]; then
        echo "⚠️ No mods found to analyze"
        return 0
    fi

    for mod_file in "${mod_files[@]}"; do
        local mod_name
        mod_name=$(basename "$mod_file" .tmod)

        local deps=()
        mapfile -t deps < <(_mod_deps "$mod_file" | sort -u)

        # Filter empty entries
        local clean_deps=()
        for d in "${deps[@]}"; do
            [[ -n "$d" ]] && clean_deps+=("$d")
        done

        if [[ ${#clean_deps[@]} -eq 0 ]]; then
            echo "$mod_name"
            echo "   └─ no dependencies"
        else
            echo "$mod_name"
            local last_idx=$(( ${#clean_deps[@]} - 1 ))
            for i in "${!clean_deps[@]}"; do
                local dep="${clean_deps[$i]}"
                local connector="├─"
                [[ $i -eq $last_idx ]] && connector="└─"
                if [[ -f "$MODS_DIR/$dep.tmod" ]]; then
                    echo "   ${connector} $dep  ✅"
                else
                    echo "   ${connector} $dep  ❌ missing"
                fi
            done
        fi
        echo
    done

    echo "ℹ️ Analyzed ${#mod_files[@]} mods"
}

# ─────────────────────────────────────────────────────────────────────────────

validate_dependencies() {
    echo "ℹ️ Validating all dependencies..."
    local errors=0

    local mod_files=()
    mapfile -t mod_files < <(find "$MODS_DIR" -maxdepth 1 -name "*.tmod" 2>/dev/null)

    for mod_file in "${mod_files[@]}"; do
        local mod_name
        mod_name=$(basename "$mod_file" .tmod)

        local deps=()
        mapfile -t deps < <(_mod_deps "$mod_file")

        for dep in "${deps[@]}"; do
            [[ -z "$dep" ]] && continue
            if [[ ! -f "$MODS_DIR/$dep.tmod" ]]; then
                echo "  ❌ Missing: $dep  (required by $mod_name)"
                (( errors++ ))
            fi
        done
    done

    if [[ $errors -eq 0 ]]; then
        echo "✅ All dependencies satisfied"
        log_dependency "Validation: all dependencies satisfied" "INFO"
        return 0
    else
        echo "⚠️ Found $errors unsatisfied dependencies"
        log_dependency "Validation: $errors unsatisfied dependencies" "WARN"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────

show_help() {
    cat << 'EOF'
🎮 tModLoader Dependency Resolution

Scan, validate, and install missing mod dependencies.

Usage: ./tmod-deps.sh [command]

Commands:
  check       Scan for missing dependencies (default)
  install     Install missing dependencies via tmod-workshop.sh
  tree        Show dependency tree for all installed mods
  validate    Validate all dependencies are satisfied
  help        Show this help message

Workflow:
  1. ./tmod-deps.sh check      # Find what's missing
  2. ./tmod-deps.sh install    # Install missing deps
  3. ./tmod-deps.sh validate   # Confirm all satisfied

Workshop ID lookup order:
  1. Configs/workshop_map.json  (add your own mappings here)
  2. Already-downloaded workshop mods
  3. Built-in table of common mods

To add custom mod mappings, create Configs/workshop_map.json:
  {
    "MyMod": "1234567890",
    "AnotherMod": "9876543210"
  }

Requirements:
  - unzip and jq must be installed to read .tmod metadata
  - tmod-workshop.sh must be present for the install command
EOF
}

# ─────────────────────────────────────────────────────────────────────────────

main() {
    local cmd="${1:-check}"
    case "$cmd" in
        check)          check_dependencies ;;
        install)        install_dependencies ;;
        tree)           show_dependency_tree ;;
        validate)       validate_dependencies ;;
        help|--help|-h) show_help ;;
        *)
            echo "❌ Unknown command: $cmd"
            echo "   Run './tmod-deps.sh help' for usage"
            exit 1
            ;;
    esac

    log_dependency "Operation completed: ${cmd}" "INFO"
}

main "$@"
