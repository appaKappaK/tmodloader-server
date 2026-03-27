#!/usr/bin/env bash
set -euo pipefail

# Copy this file into Testing/local/ and fill in the sections you want.
# Example:
#   cp Testing/templates/flow-smoke.template.sh Testing/local/flow-smoke.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="${TEST_ROOT:-/tmp/tmodloader-flow-smoke}"
WORKDIR="$TEST_ROOT/workdir"

log() {
    printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

run() {
    log "$*"
    "$@"
}

prepare_workspace() {
    rm -rf "$TEST_ROOT"
    mkdir -p "$WORKDIR"
    rsync -a --exclude .git "$ROOT_DIR/" "$WORKDIR/"
}

main() {
    prepare_workspace
    cd "$WORKDIR"

    # Bootstrap
    run make setup

    # Engine path
    # run make engine-github
    # run make steamcmd-local

    # Optional workshop path
    # printf '2563309347\n' > Scripts/steam/mod_ids.txt
    # run env -u STEAM_USERNAME bash Scripts/steam/tmod-workshop.sh download
    # printf 'y\n' | bash Scripts/steam/tmod-workshop.sh sync

    # Optional diagnostics / status / backup checks
    # run bash Scripts/diag/tmod-diagnostics.sh quick
    # run bash Scripts/hub/tmod-control.sh status
    # run bash Scripts/backup/tmod-backup.sh full
}

main "$@"
