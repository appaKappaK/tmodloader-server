#!/usr/bin/env bash
set -euo pipefail

# Copy this file into Testing/local/ for one-off command checks.
# Example:
#   cp Testing/templates/command-check.template.sh Testing/local/command-check.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/Testing/output"

mkdir -p "$OUTPUT_DIR"

run_check() {
    local name="$1"
    shift

    local logfile="$OUTPUT_DIR/${name}.log"
    echo "== $name ==" | tee "$logfile"
    "$@" 2>&1 | tee -a "$logfile"
}

# Fill in the checks you want for the current task.
# Examples:
# run_check status bash "$ROOT_DIR/Scripts/hub/tmod-control.sh" status
# run_check diagnostics bash "$ROOT_DIR/Scripts/diag/tmod-diagnostics.sh" quick
# run_check backup bash "$ROOT_DIR/Scripts/backup/tmod-backup.sh" full
