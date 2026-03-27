# tmodloader-server

![CI](https://github.com/appaKappaK/tmodloader-server/actions/workflows/ci.yml/badge.svg)
![Version](https://img.shields.io/badge/version-2.5.1-blue)
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
- Easy to bootstrap: `make setup` prepares the layout, and `make steamcmd-local` can install SteamCMD directly into the project.

## Feature Summary

- Interactive CLI hub for server lifecycle, mods, monitoring, backups, and maintenance
- Repo-local layout with `Engine/`, `Mods/`, `Worlds/`, `Logs/`, `Backups/`, and `Tools/SteamCMD/`
- Steam Workshop tooling for mod download, sync, archive, and cleanup
- Built-in backup flows for worlds, configs, and full-server snapshots
- Diagnostics and repair helpers for common setup mistakes
- Per-mod config editing from the control menu
- Log rotation and project-relative config path support

## Quick Start

1. Install system packages.
2. Run `make setup`.
3. Optionally run `make steamcmd-local`.
4. Set `STEAM_USERNAME` for a Steam account that owns Terraria.
5. Install tModLoader server files into `Engine/`.
6. Start the control hub.

### 1. Install Packages

Debian / Ubuntu:

```bash
sudo apt update -y
sudo apt install -y git screen curl jq pigz rsync unzip htop ncdu net-tools dos2unix
```

Fedora:

```bash
sudo dnf install -y git screen curl jq pigz rsync unzip htop ncdu net-tools dos2unix
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

### 4. Set Your Steam Username

Add your Steam username to `Scripts/env.sh`:

```bash
export STEAM_USERNAME="your_steam_username"
```

tModLoader can be queried anonymously through SteamCMD, but the actual engine download requires a Steam account that owns Terraria.

### 5. Install tModLoader Server Files

```bash
./Tools/SteamCMD/steamcmd.sh \
  +force_install_dir "$PWD/Engine" \
  +login "$STEAM_USERNAME" \
  +app_update 1281930 validate \
  +quit
```

SteamCMD will prompt for the password and any Steam Guard code it needs. After a successful install, `Engine/` should contain the tModLoader binaries, `tModLoader.dll`, and `steamapps/appmanifest_1281930.acf`.

### 6. Launch the Toolkit

```bash
bash Scripts/hub/tmod-control.sh
```

For verbose terminal logging:

```bash
bash Scripts/hub/tmod-control.sh --debug
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

### Run the Interactive Hub

```bash
bash Scripts/hub/tmod-control.sh
```

Main sections:

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
bash Scripts/hub/tmod-control.sh workshop list
bash Scripts/hub/tmod-control.sh workshop archive
bash Scripts/hub/tmod-control.sh workshop cleanup
```

### Backup Commands

```bash
bash Scripts/hub/tmod-control.sh backup worlds
bash Scripts/hub/tmod-control.sh backup configs
bash Scripts/hub/tmod-control.sh backup full
bash Scripts/hub/tmod-control.sh backup auto
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

That keeps the public repo clean while still letting the project behave like a complete local server workspace.

## Changelog

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

No GitHub release is published yet, but the current documented state of the public portable edition is `v2.5.1`.

## Contributing

Issues, feature requests, and pull requests are welcome.

See `CONTRIBUTING.md` for contribution guidelines and `SECURITY.md` for responsible disclosure.

## License

Apache 2.0. See `LICENSE` for details.
