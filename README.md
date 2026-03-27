# tModLoader Server Portable

![Version](https://img.shields.io/badge/version-2.5.0-blue)
![tModLoader](https://img.shields.io/badge/tModLoader-2024.5+-blue)
![License](https://img.shields.io/badge/license-Apache--2.0-brightgreen)
![Platform](https://img.shields.io/badge/platform-Linux-orange)

A self-contained tModLoader server toolkit for Linux with Steam Workshop integration, automated backups, world management, mod config editing, diagnostics, and a single interactive CLI menu.

Everything lives inside the project folder by default: engine files, worlds, mods, logs, backups, and even SteamCMD. That makes this edition easier to publish, clone, move, test, and run on a fresh machine without rewriting hardcoded paths.

## Why This Version

- Portable by default: the project folder is the server home.
- Public-repo friendly: runtime data and local config are meant to stay out of git.
- Easier onboarding: `make setup` and `make steamcmd-local` bootstrap the whole layout.
- Safer experimentation: copy the folder, try changes, and remove it cleanly if needed.

## Quick Start

```bash
make setup
make steamcmd-local
./Tools/SteamCMD/steamcmd.sh \
  +force_install_dir "$PWD/Engine" \
  +login anonymous \
  +app_update 1281930 validate \
  +quit
bash Scripts/hub/tmod-control.sh
```

Optional local secrets and overrides live in `Scripts/env.sh`, which is created from `Scripts/env.example.sh` during setup and ignored by git.

---

## 📁 Directory Structure

```text
<project-root>/
├── Engine/           # tModLoader server files (managed by SteamCMD)
├── Mods/             # Installed .tmod files + enabled.json
├── Worlds/           # World save files
├── ModConfigs/       # Per-mod config files (JSON, TOML, etc.)
├── Configs/          # serverconfig.txt, workshop_map.json
├── Backups/          # Automated backup storage
│   ├── Worlds/
│   ├── Configs/
│   └── Full/
├── Logs/             # All script and server logs
└── Scripts/
    ├── core/         # tmod-core.sh, tmod-server.sh, tmod-monitor.sh
    ├── hub/          # tmod-control.sh  ← main entry point
    ├── backup/       # tmod-backup.sh
    ├── steam/        # tmod-workshop.sh, tmod-deps.sh, mod_ids.txt
    └── diag/         # tmod-diagnostics.sh
```

---

## 📦 Requirements

### System Dependencies

**Debian / Ubuntu**
```bash
sudo apt update -y
sudo apt install -y git screen curl jq pigz rsync unzip htop ncdu net-tools dos2unix
```

**Fedora / RHEL / CentOS** *(untested — community contributions welcome)*
```bash
sudo dnf install -y git screen curl jq pigz rsync unzip htop ncdu net-tools dos2unix
```

> Note: `pigz` and `dos2unix` may require the EPEL repository on RHEL/CentOS.

### SteamCMD

Preferred for this portable layout:
```bash
make steamcmd-local
```

**Debian / Ubuntu**
```bash
sudo dpkg --add-architecture i386
sudo apt update -y
sudo apt install -y steamcmd
```

**Portable manual install into this project**
```bash
mkdir -p ./Tools/SteamCMD
curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" \
  | tar -xzf - -C ./Tools/SteamCMD
```

`Configs/serverconfig.txt` now defaults to `./Tools/SteamCMD/steamcmd.sh`, so no edit is needed if you keep SteamCMD inside the project.

### tModLoader Server Files
```bash
./Tools/SteamCMD/steamcmd.sh \
  +force_install_dir /path/to/your/project/Engine \
  +login anonymous \
  +app_update 1281930 validate \
  +quit
```

### .NET Runtime

**No manual installation needed.** On first server start the scripts automatically:

1. Read the required .NET version from `Engine/tModLoader.runtimeconfig.json`
2. Run tModLoader's bundled `Engine/LaunchUtils/InstallDotNet.sh`
3. Install the correct runtime into `Engine/dotnet/`

Install progress is logged to `Logs/dotnet-install.log`. If the install fails, check that file for details.

---

## ⚙️ Setup

After cloning or copying the project, run once to create required directories, copy example configs, and set script permissions:

```bash
make setup
```

Then install SteamCMD locally if you want the whole stack inside the project:

```bash
make steamcmd-local
```

If you keep SteamCMD somewhere else, edit `Configs/serverconfig.txt`. Everything else already defaults to the current project folder.

`make setup` also creates `Scripts/env.sh` from `Scripts/env.example.sh` so you have a safe place for local environment variables that should not be committed.

---

## 🚀 Usage

All management goes through `Scripts/hub/tmod-control.sh`. Run with no arguments to open the interactive menu:

```bash
./Scripts/hub/tmod-control.sh
# or from the hub directory:
./tmod-control.sh
# with debug logging to terminal:
./tmod-control.sh --debug
```

Every page shows a live status bar with server state, uptime, player count, mod count, active world, folder sizes, and disk usage.

### Interactive Menu

| # | Section | Description |
|---|---------|-------------|
| 1 | Server | Start, stop, restart, status, world management |
| 2 | Mods | Add, enable/disable, mod configs, workshop tools |
| 3 | Monitoring | Dashboard, live log tail, console attach |
| 4 | Backup | Create, restore, verify, cleanup |
| 5 | Maintenance | Diagnostics, update engine, emergency shutdown |

---

### Server Page

| # | Option |
|---|--------|
| 1 | Show Status |
| 2 | Start Server |
| 3 | Stop Server |
| 4 | Restart Server |
| 5 | Select Active World |
| 6 | Start with World Select |
| 7 | Create New World |
| 8 | Import World (from uploaded .wld file) |

**Select World** — lists all `.wld` files with size, last modified, and marks the currently active world. Updates `serverconfig.txt` automatically.

**Create New World** — generates a world headlessly via tModLoader's `-autocreate`. Prompts for name, size, difficulty, and seed.

**Import World** — paste the path to a pre-uploaded `.wld` file. Copies it into `Worlds/`, optionally renames it, sets it as active, and optionally starts the server.

---

### Mods Page

| # | Option |
|---|--------|
| 1 | Add Mod by URL or ID |
| 2 | Show mod_ids.txt |
| 3 | Clear mod_ids.txt |
| 4 | Mod Picker (interactive toggle) |
| 5 | Enable a Mod |
| 6 | Disable a Mod |
| 7 | List Mods (enabled/disabled) |
| 8 | List Installed Mods |
| 9 | Check for Errors |
| 10 | Workshop Status |
| 11 | List Workshop Downloads |
| 12 | Archive Old Versions |
| 13 | Cleanup Downloads |
| 14 | Mod Configs (edit per-mod settings) |

**Add Mod by URL or ID** — paste one or more Steam Workshop URLs (including concatenated multi-URL strings). Automatically extracts all `?id=` values, adds them to `mod_ids.txt`, and optionally downloads + syncs immediately.

**Mod Configs** — scans `ModConfigs/` and any mod-created subdirectories (e.g. `TerrariaOverhaul/`) for config files. Select one to open in `nano`.

---

### Backup Page

| # | Option |
|---|--------|
| 1 | Backup Status |
| 2 | World Backup |
| 3 | Config Backup |
| 4 | Full Server Backup |
| 5 | Auto Backup (all three) |
| 6 | List Backups |
| 7 | Restore from Backup |
| 8 | Verify a Backup |
| 9 | Cleanup Old Backups |
| 10 | View Backup Log |

Restore and Verify use an inline file picker that scans all backup subdirectories.

---

### Monitoring Page

| # | Option |
|---|--------|
| 1 | Status Dashboard |
| 2 | Health Check |
| 3 | Live Monitor (continuous) |
| 4 | Follow Server Log (tail -f) |
| 5 | View Server Log (last 50) |
| 6 | View Monitor Log |
| 7 | View Control Log |
| 8 | Attach to Server Console |

---

## ⚙️ Configuration

### Configs/serverconfig.txt

`serverconfig.txt` is **not tracked** in git (machine-specific paths). A clean template is provided:

```bash
cp Configs/serverconfig.example.txt Configs/serverconfig.txt
```

Then edit `serverconfig.txt` for your machine. The `world=` and `worldname=` keys are managed automatically by the world picker — leave them commented out initially. The `tmod-scripts` section at the bottom holds script-specific settings:

```ini
# ─── tmod-scripts ─────────────────────────────────────────────────────────────
steamcmd_path=./Tools/SteamCMD/steamcmd.sh
log_max_size=10M    # Rotate logs larger than this (e.g. 5M, 10M, 50M)
log_keep_days=14    # Delete compressed old logs after this many days
```

Paths support `~/` expansion and project-relative values like `./Tools/SteamCMD/steamcmd.sh`.

### Secrets

Sensitive values such as `STEAM_API_KEY`, `STEAM_USERNAME`, or webhook URLs should live in `Scripts/env.sh` or your shell profile, not in tracked files.

### mod_ids.txt

`mod_ids.txt` is **not tracked** in git (personal mod list). A clean template is provided:

```bash
cp Scripts/steam/mod_ids.example.txt Scripts/steam/mod_ids.txt
```

Then add your Workshop URLs or numeric IDs — one per line. Managed via the menu (Mods → Add Mod by URL or ID) or edited directly. Lines starting with `#` are ignored.

### workshop_map.json

Optional at `Configs/workshop_map.json`. Maps mod names to Workshop IDs for use by `tmod-deps.sh`:
```json
{
  "MyMod": "1234567890"
}
```

---

## 🔧 Diagnostics

```bash
./Scripts/diag/tmod-diagnostics.sh full      # Full system check
./Scripts/diag/tmod-diagnostics.sh quick     # Fast essential checks
./Scripts/diag/tmod-diagnostics.sh binaries  # Check tModLoader binary
./Scripts/diag/tmod-diagnostics.sh config    # Check config files
./Scripts/diag/tmod-diagnostics.sh fix       # Auto-fix common issues
./Scripts/diag/tmod-diagnostics.sh report    # Generate shareable report
```

---

## 📋 CLI Reference

```bash
# Server
./tmod-control.sh start
./tmod-control.sh stop
./tmod-control.sh restart
./tmod-control.sh status

# Backup
./tmod-control.sh backup worlds
./tmod-control.sh backup configs
./tmod-control.sh backup full
./tmod-control.sh backup auto

# Monitoring
./tmod-control.sh monitor status
./tmod-control.sh monitor start
./tmod-control.sh monitor logs

# Workshop
./tmod-control.sh workshop download
./tmod-control.sh workshop sync
./tmod-control.sh workshop list
./tmod-control.sh workshop archive
./tmod-control.sh workshop cleanup
```

---

## 📝 Changelog

### Portable Edition Refresh — 2026-03-27

**Portable Layout**
- The toolkit now treats the project folder itself as `BASE_DIR` by default, so copied or renamed installs work in place.
- Runtime content is expected to live inside the repo folder: `Engine/`, `Mods/`, `Worlds/`, `Logs/`, `Backups/`, and `Tools/SteamCMD/`.
- `steamcmd_path` now defaults to the project-local `./Tools/SteamCMD/steamcmd.sh`.
- Relative paths in config are now supported, so tracked examples do not need machine-specific absolute paths.

**Bootstrap and Local Tooling**
- Added `make steamcmd-local` to download SteamCMD directly into `Tools/SteamCMD/`.
- `make setup` now bootstraps local config files for the portable workflow, including `Scripts/env.sh`.
- Added `Scripts/env.example.sh` as a tracked template for optional local environment overrides.
- Workshop and startup scripts now derive Steam runtime paths from the configured SteamCMD location instead of assuming a fixed home-directory install.

**Inherited Toolkit Features**
- The portable edition still includes the existing server control, workshop sync, backups, monitoring, diagnostics, and interactive menu system from the current tModLoader server toolkit.

---

## 🤝 Contributing

Issues, feature requests, and pull requests are welcome.

See `CONTRIBUTING.md` for contribution guidelines and `SECURITY.md` for responsible disclosure.

## 🧹 Git Hygiene

The portable runtime directories and local machine-specific files are intended to stay untracked. The repo ships with a `.gitignore` that excludes:

- `Engine/`, `Mods/`, `Worlds/`, `Backups/`, `Logs/`, `Tools/SteamCMD/`
- `Configs/serverconfig.txt`
- `Scripts/env.sh`
- `Scripts/steam/mod_ids.txt`

## 📄 License

Apache 2.0 — see [LICENSE](LICENSE) for details.
