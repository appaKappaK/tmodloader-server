# tmodloader-server

![CI](https://github.com/appaKappaK/tmodloader-server/actions/workflows/ci.yml/badge.svg)
![Version](https://img.shields.io/badge/version-2.6.0-blue)
![tModLoader](https://img.shields.io/badge/tModLoader-2024.5+-blue)
![License](https://img.shields.io/badge/license-Apache--2.0-brightgreen)
![Platform](https://img.shields.io/badge/platform-Linux-orange)
![Portable](https://img.shields.io/badge/layout-portable-success)

Portable Linux toolkit for running and managing a tModLoader dedicated server.

This edition is built around a self-contained project layout: the server engine, worlds, mods, logs, backups, and optional local SteamCMD install all live inside the repo folder by default. That makes it easier to clone, move, test, back up, and publish without dragging around machine-specific paths.

## Why This Repo

- Portable by default: the project folder acts as the server home.
- Public-repo friendly: runtime data and local machine config stay out of git.
- Practical for real hosting: workshop sync, backups, monitoring, diagnostics, and world management are already wired together.
- Easy to bootstrap: `make setup` prepares the layout, `make steamcmd-local` installs SteamCMD locally, and `make engine-github` installs the engine from the official GitHub release.

## Feature Summary

- Persistent Go TUI with section overview, live server snapshot, log tail, and in-app command output
- Shell hub preserved as a CLI backend and legacy fallback for users who still want menu-driven Bash
- Live host and process metrics for PID, players, mods, backups, CPU, memory, uptime, disk activity, and temperature
- Repo-local layout with `Engine/`, `Mods/`, `Worlds/`, `Logs/`, `Backups/`, and `Tools/SteamCMD/`
- Engine bootstrap via official GitHub release or SteamCMD
- Steam Workshop tooling for mod download, sync, archive, and cleanup
- Built-in backup flows for worlds, configs, and full-server snapshots
- Diagnostics and repair helpers for common setup mistakes
- Per-mod config editing from the control menu
- Log rotation and project-relative config path support

## Quick Start

1. Install system packages.
2. Run `make setup`.
3. Optionally run `make steamcmd-local`.
4. Install tModLoader server files into `Engine/`.
5. Start the persistent control room.

### 1. Install Packages

Debian / Ubuntu:

```bash
sudo apt update -y
sudo apt install -y git screen curl jq pigz rsync unzip htop ncdu net-tools dos2unix fzf dialog golang
```

Fedora:

```bash
sudo dnf install -y git screen curl jq pigz rsync unzip htop ncdu net-tools dos2unix fzf dialog golang
```

### 2. Bootstrap the Project

```bash
make setup
```

This creates the expected directory layout, copies local config templates, and makes the scripts executable.

### 3. Install SteamCMD Locally

```bash
make steamcmd-local
```

This installs SteamCMD into `Tools/SteamCMD/steamcmd.sh`, which matches the default `steamcmd_path` in `Configs/serverconfig.txt`.

If you plan to use Workshop downloads, install SteamCMD even if you used `make engine-github` for the engine itself.

### 4. Install tModLoader Server Files

Recommended public-friendly path:

```bash
make engine-github
```

This downloads the latest official `tModLoader.zip` release from GitHub and extracts it into `Engine/`.

Alternative SteamCMD path:

```bash
export STEAM_USERNAME="your_steam_username"
./Tools/SteamCMD/steamcmd.sh \
  +force_install_dir "$PWD/Engine" \
  +login "$STEAM_USERNAME" \
  +app_update 1281930 validate \
  +quit
```

Notes:

- `1281930` is the tModLoader app ID.
- Steam reports that app as requiring ownership of Terraria (`105600`), so anonymous SteamCMD downloads can appear to succeed while leaving `Engine/` empty.
- The GitHub release path avoids that first-run trap for public users.

After a successful install, `Engine/` should contain the tModLoader binaries, `tModLoader.dll`, `tModLoader.runtimeconfig.json`, and `start-tModLoaderServer.sh`.

### 5. Launch the Persistent TUI

```bash
make tui-run
```

For verbose terminal logging:

```bash
TMOD_DEBUG=1 make tui-run
```

Shell entrypoint that now prefers the Go control room:

```bash
bash Scripts/hub/tmod-control.sh
```

## Project Layout

```text
<project-root>/
├── Engine/           # tModLoader server files
├── Mods/             # Installed .tmod files + enabled.json
├── Worlds/           # World save files
├── ModConfigs/       # Per-mod config files
├── Configs/          # Server and workshop config
├── Backups/
│   ├── Worlds/
│   ├── Configs/
│   └── Full/
├── Logs/             # Script, server, monitor, and dotnet logs
├── Tools/
│   └── SteamCMD/
└── Scripts/
    ├── backup/
    ├── core/
    ├── diag/
    ├── hub/
    └── steam/
```

Everything above is expected to live inside the project by default. That is the main difference between this public portable repo and the older machine-specific setup it came from.

## Common Workflows

### Run the Persistent TUI

```bash
make tui-run
```

This is the new primary interface. It keeps the screen alive while commands run, streams backend script output inside the app, refreshes server status in place, and lets you cycle through the project log files without dropping back to raw shell output.

The default landing view is a section overview, so you drill into `Server`, `Workshop`, `Backup`, `Monitor`, `Diagnostics`, or `Maintenance` instead of starting on one long action list. The right side of the UI stays anchored around a selected-section/action panel, a live `Server Snapshot`, and a lower pane for log tails or command output.

The shell entrypoint now prefers the same control room when it can find a built `bin/tmodloader-ui` or a local Go toolchain:

```bash
bash Scripts/hub/tmod-control.sh
```

Useful keys:

- `Enter`: open the selected section or run the selected action
- `r`: refresh status and the current log view
- `l`: cycle between `server.log`, `control.log`, `workshop.log`, `backup.log`, `monitor.log`, and `diagnostics.log`
- `Tab`: switch between log-tail view and command-output view
- `Shift+Left` / `Shift+Right`: horizontal scroll in the lower pane when output is wider than the window
- `Esc`: return to the section overview from a category page
- Mouse wheel: move one item at a time in the current list
- `q`: quit when idle
- `Ctrl+C`: force quit immediately

### Run the Legacy Shell Fallback

```bash
bash Scripts/hub/tmod-control.sh interactive classic
```

If you want the older searchable shell palette instead of the Go TUI, force the legacy path:

```bash
TMOD_FORCE_LEGACY_UI=1 bash Scripts/hub/tmod-control.sh interactive
```

When available, the legacy hub uses `fzf` for searchable pickers and `dialog` for boxed menus and log viewers. You can force a legacy shell mode with `TMOD_UI_MODE=dialog`, `TMOD_UI_MODE=fzf`, or `TMOD_UI_MODE=plain`.

Main areas exposed through the palette:

- `Server`: start, stop, restart, select world, create world, import world
- `Mods`: add by Workshop URL or ID, toggle enabled mods, inspect downloads, edit mod configs
- `Monitoring`: dashboard, health check, live monitor, log viewing, console attach
- `Backup`: create, restore, verify, and clean up backups
- `Maintenance`: diagnostics, engine update, emergency controls

### Server Commands

```bash
bash Scripts/hub/tmod-control.sh start
bash Scripts/hub/tmod-control.sh stop
bash Scripts/hub/tmod-control.sh restart
bash Scripts/hub/tmod-control.sh status
```

### Workshop Commands

```bash
bash Scripts/hub/tmod-control.sh workshop download
bash Scripts/hub/tmod-control.sh workshop sync
bash Scripts/hub/tmod-control.sh workshop sync --yes
bash Scripts/hub/tmod-control.sh workshop list
bash Scripts/hub/tmod-control.sh workshop archive
bash Scripts/hub/tmod-control.sh workshop archive --yes
bash Scripts/hub/tmod-control.sh workshop cleanup
```

### Backup Commands

```bash
bash Scripts/hub/tmod-control.sh backup worlds
bash Scripts/hub/tmod-control.sh backup configs
bash Scripts/hub/tmod-control.sh backup full
bash Scripts/hub/tmod-control.sh backup auto
bash Scripts/backup/tmod-backup.sh restore --yes Backups/Worlds/worlds_YYYYMMDD_HHMMSS.tar.gz
```

### Diagnostics Commands

```bash
bash Scripts/diag/tmod-diagnostics.sh quick
bash Scripts/diag/tmod-diagnostics.sh full
bash Scripts/diag/tmod-diagnostics.sh binaries
bash Scripts/diag/tmod-diagnostics.sh config
bash Scripts/diag/tmod-diagnostics.sh fix
bash Scripts/diag/tmod-diagnostics.sh report
```

## Configuration

### `Configs/serverconfig.txt`

`make setup` creates `Configs/serverconfig.txt` from the tracked example file. This local config is intentionally gitignored.

Useful notes:

- `world=` and `worldname=` are usually managed by the world picker
- `steamcmd_path` defaults to `./Tools/SteamCMD/steamcmd.sh`
- script settings live under the `tmod-scripts` section at the bottom
- paths support absolute values, `~/...`, and project-relative paths like `./Tools/SteamCMD/steamcmd.sh`

Example script settings:

```ini
# ─── tmod-scripts ─────────────────────────────────────────────────────────────
steamcmd_path=./Tools/SteamCMD/steamcmd.sh
log_max_size=10M
log_keep_days=14
```

### `Scripts/env.sh`

`make setup` also creates `Scripts/env.sh` from `Scripts/env.example.sh`.

Use it for local values you do not want in tracked files, such as:

- `STEAM_USERNAME`
- `STEAM_API_KEY`
- webhook URLs
- machine-specific overrides

For Workshop downloads, `STEAM_USERNAME` is optional. The toolkit will fall back to anonymous SteamCMD access if it is unset, but a real Steam account may be more reliable for larger download batches.

### `Scripts/steam/mod_ids.txt`

This file is also local and gitignored. It accepts one Steam Workshop URL or numeric ID per line. Lines starting with `#` are ignored.

The control hub can manage it for you through the Mods page, but direct editing works fine too.

### `Configs/workshop_map.json`

Optional file for mapping mod names to Workshop IDs when dependency helpers need a manual hint.

Example:

```json
{
  "MyMod": "1234567890"
}
```

## Runtime Notes

### .NET Runtime

You do not need to install the tModLoader runtime manually. On first server start, the toolkit reads the required version from `Engine/tModLoader.runtimeconfig.json` and runs tModLoader's bundled installer into `Engine/dotnet/`.

If that install fails, check:

- `Logs/dotnet-install.log`
- that `Engine/` contains a valid tModLoader server install
- that the host can reach the required download endpoints

### Git Hygiene

The repo is set up so that runtime data stays local. `.gitignore` already excludes:

- `Engine/`, `Mods/`, `Worlds/`, `Backups/`, `Logs/`, `Tools/SteamCMD/`
- `Configs/serverconfig.txt`
- `Scripts/env.sh`
- `Scripts/steam/mod_ids.txt`
- `bin/`, `coverage.out`, `*.coverprofile`, and `*.test`
- `Testing/local/`, `Testing/output/`, and `Testing/tmp/`

That keeps the public repo clean while still letting the project behave like a complete local server workspace.

## Changelog

### v2.6.0 — 2026-03-27

**Persistent Go TUI**
- Added a Bubble Tea-based headless server console that keeps the screen alive while backend actions run.
- Replaced the old catch-all landing list with a section overview, native section pages, and a broader set of shell-backed admin actions.
- Added `make tui-run` and `make tui-build` so the Go UI is easy to launch from source or build into `bin/tmodloader-ui`.
- Made `bash Scripts/hub/tmod-control.sh` prefer the Go TUI for interactive launches, while keeping `interactive classic` and `TMOD_FORCE_LEGACY_UI=1` for the legacy shell UI.

**Observability & Layout**
- Added a live `Server Snapshot` with running state, PID, world, players, mod and backup counts, CPU, RSS memory, uptime, disk activity, and host temperature.
- Kept log tails and command output inside the app so server actions no longer dump you back into raw shell output.
- Tightened pane layout, empty states, mouse-wheel handling, and overview/action previews so the interface behaves more like a persistent SSH console than a shell launcher.
- Hardened status polling so offline states do not flicker or report bogus PID, memory, or uptime values.

**Compatibility**
- The Bash control hub remains available as a legacy fallback and backend command surface.
- Existing script-driven workflows continue to work through the same `tmod-control.sh`, backup, workshop, diagnostics, and monitor commands.

### v2.5.2 — 2026-03-27

**Headless UI**
- Added a dependency-aware interactive hub that can use `dialog` for boxed menus/log viewers and `fzf` for searchable pickers, while keeping plain-Bash fallback intact.
- Expanded the command palette into a fuller direct-action launcher instead of mostly routing through submenu pages.
- Unified page navigation around shared menu and picker helpers for worlds, backups, mod configs, logs, and common prompts.

**Automation & Workflow Fixes**
- Added `--yes` support to workshop sync, workshop archive, mod-list clearing, and backup restore so scripted flows do not hang on confirmations.
- Updated maintenance to run workshop sync non-interactively, matching the cron-style examples in the docs.
- Tightened workshop sync so pre-2023 mod builds are skipped consistently instead of being copied into `Mods/`.

**Backup Safety**
- Fixed restore correctness by switching rsync-based restore paths to checksum mode.
- Fixed same-second backup filename collisions so pre-restore safety backups cannot overwrite the archive you are trying to restore.

### v2.5.1 — 2026-03-27

**Portable/Public Release**
- Reworked the toolkit into a project-root portable layout instead of assuming a fixed home-directory install.
- Made `steamcmd_path` default to `./Tools/SteamCMD/steamcmd.sh`.
- Added support for project-relative paths in config so tracked examples stay machine-agnostic.
- Added `make steamcmd-local` for repo-local SteamCMD bootstrap.
- Added `Scripts/env.example.sh` and improved `make setup` for portable onboarding.
- Added GitHub community health files, issue templates, PR template, and CI workflow for the public repo.
- Reframed the repo and README around the portable public edition.

**Bug Fixes**
- Fixed full backup and full restore to respect the capitalized `Logs/` and `Backups/` layout.
- Fixed diagnostics `auto_fix` to recreate the actual repo directory structure instead of legacy lowercase paths.
- Fixed monitor process detection so monitoring and health checks agree with the server start mode.
- Fixed `tmod-control.sh diagnostics` to run the full diagnostics script instead of the lightweight inline summary.

### v2.5.0 — 2026-03-01

Inherited from the original `tmodloaderserver` line before the portable fork became the public repo.

**Menu & UX**
- Removed obsolete Download Mods and Sync Mods menu items in favor of the URL-to-`enabled.json` flow.
- Restructured all five menu pages for a better headless-server workflow.
- Expanded Monitoring with dashboard, health check, live monitor, log viewing, and console attach.
- Expanded Backup with inline restore and verify pickers, cleanup, and log viewing.
- Added Mod Configs editing from the Mods page.
- Added world import flow from pre-uploaded `.wld` files.

**Logging and Config**
- Moved script logging to file-first behavior while keeping warnings and errors visible in the terminal.
- Added `--debug` support through `TMOD_DEBUG=1` for noisier child-script output.
- Renamed the main directories to the capitalized tModLoader-style layout.
- Moved `STEAMCMD_PATH` handling into `serverconfig.txt` as `steamcmd_path=`.
- Added configurable log rotation settings and improved rotated log handling.
- Added `server_config_get()` helper support in core scripts.

**Cleanup**
- Removed the whitelist system from the toolkit.
- Excluded `*.bak` from git.
- Started treating `Scripts/steam/mod_ids.txt` as a local gitignored file with a tracked example template.

## Releases

No GitHub release is published yet, but the current documented state of the public portable edition is `v2.6.0`.

## Contributing

Issues, feature requests, and pull requests are welcome.

See `CONTRIBUTING.md` for contribution guidelines and `SECURITY.md` for responsible disclosure.

## License

Apache 2.0. See `LICENSE` for details.
