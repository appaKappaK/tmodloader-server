# tmodloader-server

![CI](https://github.com/appaKappaK/tmodloader-server/actions/workflows/ci.yml/badge.svg)
![Version](https://img.shields.io/badge/version-2.6.0-blue)
![tModLoader](https://img.shields.io/badge/tModLoader-2024.5+-blue)
![License](https://img.shields.io/badge/license-Apache--2.0-brightgreen)
![Platform](https://img.shields.io/badge/platform-Linux-orange)
![Portable](https://img.shields.io/badge/layout-portable-success)

Portable Linux toolkit for running and managing a tModLoader dedicated server.

This repo is meant to be its own server home. By default the engine, worlds, mods, configs, logs, backups, and optional SteamCMD install all live under the project root. `make setup` turns the tracked example files into local working files, so the project can be cloned, moved, backed up, or published without dragging machine-specific paths through git.

## Highlights

- Repo-local layout with `Engine/`, `Mods/`, `Worlds/`, `ModConfigs/`, `Backups/`, `Logs/`, and optional `Tools/SteamCMD/`
- Persistent Go control room with live server snapshot, log tails, in-app command output, and mouse-friendly navigation
- Native control-room flows for Workshop URL or ID queueing, installed-mod load management, and per-mod config editing
- Manifest-driven addon sections from `Addons/*/addon.json`, so new tool groups can plug into the UI without editing core code
- Shell hub kept for automation and direct command entrypoints while interactive launches go straight to the Go control room
- Backup, monitoring, diagnostics, and workshop maintenance still live in the same repo-local toolkit
- Local-only files and Go build artifacts are already covered by `.gitignore`

## Quick Start

### 1. Install packages

Debian / Ubuntu:

```bash
sudo apt update -y                                                       # refresh package metadata
sudo apt install -y git screen curl jq pigz rsync unzip net-tools dos2unix htop ncdu  # core runtime and admin tools
sudo apt install -y golang                                               # Go toolchain for make tui-run and shell-launched UI
```

Fedora:

```bash
sudo dnf install -y git screen curl jq pigz rsync unzip net-tools dos2unix htop ncdu  # core runtime and admin tools
sudo dnf install -y golang                                               # Go toolchain for make tui-run and shell-launched UI
```

Notes:

- `golang` is required for `make tui-run` or for `bash Scripts/hub/tmod-control.sh` when no built binary exists yet.
- `screen` is required for normal server start and stop flows.

### 2. Bootstrap the repo

```bash
make setup  # create repo-local directories and missing local config files
```

This creates the expected directory layout, copies local working files from tracked examples, and makes the scripts executable. Existing local files are left alone.

Created on first run:

- `Configs/serverconfig.txt` from `Configs/serverconfig.example.txt`
- `Scripts/env.sh` from `Scripts/env.example.sh`
- `Scripts/steam/mod_ids.txt` from `Scripts/steam/mod_ids.example.txt`

### 3. Optionally install SteamCMD locally

```bash
make steamcmd-local  # install SteamCMD into Tools/SteamCMD/
```

This installs SteamCMD into `Tools/SteamCMD/steamcmd.sh`, which matches the default `steamcmd_path` in `Configs/serverconfig.txt`.

Run this if you want Workshop downloads, or if you prefer installing the engine through SteamCMD instead of GitHub releases.

### 4. Install tModLoader into `Engine/`

Recommended public-friendly path:

```bash
make engine-github  # download and extract the latest tModLoader release into Engine/
```

This downloads the latest official `tModLoader.zip` release from GitHub and extracts it into `Engine/`.

Alternative SteamCMD path:

```bash
export STEAM_USERNAME="your_steam_username"  # Steam account used for owned-app installs
./Tools/SteamCMD/steamcmd.sh \               # run the local SteamCMD install
  +force_install_dir "$PWD/Engine" \         # place server files in this repo's Engine/
  +login "$STEAM_USERNAME" \                 # authenticate with your Steam account
  +app_update 1281930 validate \             # install or update tModLoader server files
  +quit                                      # exit SteamCMD
```

Notes:

- `1281930` is the tModLoader app ID.
- Steam reports that app as requiring Terraria ownership (`105600`), so anonymous SteamCMD downloads can appear to succeed while leaving `Engine/` empty.
- The GitHub release path avoids that first-run trap for public users.

After a successful install, `Engine/` should contain `tModLoader.dll`, `tModLoader.runtimeconfig.json`, and `start-tModLoaderServer.sh`.

### 5. Launch the control room

Run the Go UI from source:

```bash
make tui-run  # launch the Go control room from source
```

Run with verbose terminal logging:

```bash
TMOD_DEBUG=1 make tui-run  # launch the Go control room with verbose terminal logging
```

Use the shell entrypoint to open the Go control room from the repo root:

```bash
bash Scripts/hub/tmod-control.sh tui  # launch the Go control room through the shell hub
```

If Go is not installed on the host yet, build the binary first and then use the same shell entrypoint:

```bash
make tui-build                             # build bin/tmodloader-ui once
bash Scripts/hub/tmod-control.sh tui       # launch the built control room
```

Optional extras:

```bash
make tui-build    # build bin/tmodloader-ui
make install-man  # install the man page system-wide
make help         # list the available make targets
```

## Self-Contained Layout

```text
<project-root>/
├── Engine/                     # tModLoader server files
├── Mods/                       # Installed .tmod files + enabled.json
├── Worlds/                     # World save files
├── ModConfigs/                 # Per-mod config files
├── Configs/
│   ├── serverconfig.example.txt
│   ├── serverconfig.txt        # local, created by make setup
│   └── workshop_map.json       # optional local Workshop-ID hints
├── Backups/
│   ├── Worlds/
│   ├── Configs/
│   └── Full/
├── Logs/                       # Script, server, monitor, backup, and dotnet logs
├── Tools/
│   └── SteamCMD/
├── Addons/                     # optional manifest-driven UI extensions
├── Scripts/
│   ├── env.example.sh
│   ├── env.sh                  # local, created by make setup
│   ├── backup/
│   ├── core/
│   ├── diag/
│   ├── hub/
│   └── steam/
│       ├── mod_ids.example.txt
│       └── mod_ids.txt         # local, created by make setup
└── Testing/
    ├── local/                  # ignored scratch scripts
    ├── output/                 # ignored captured output
    └── tmp/                    # ignored disposable workspace
```

Tracked examples stay in git. Generated working copies, runtime content, and scratch space stay local.

## Daily Use

### Control room and UI

```bash
bash Scripts/hub/tmod-control.sh tui          # launch the Go control room
bash Scripts/hub/tmod-control.sh interactive  # accepted alias for the same control room
```

Go UI basics:

- `Enter` opens a section or runs the selected action
- `r` refreshes status and the current log view
- `l` cycles between log files when log-tail view is active
- `Tab` switches between log-tail view and command-output view
- `Esc` returns to the section overview
- `q` quits when idle
- mouse hover and click can select and activate rows when your terminal forwards mouse events

The left legend stays visible on every screen and gives the currently valid hotkeys a little more contrast, so the control scheme stays learn-once instead of page-by-page.

Workshop tools in the Go UI now include native screens for `Add Mod by URL or ID`, `Manage Installed Mods`, and `Edit Mod Configs`. The config editor still hands off to your terminal editor and returns you to the TUI when you exit.

Addon action packs under `Addons/*/addon.json` are loaded into the control room automatically. If an addon manifest is invalid, the control room shows a warning in the header and command-output pane, and the loader details are still written to `Logs/control.log`.

### Server commands

```bash
bash Scripts/hub/tmod-control.sh start    # start the server in its managed screen session
bash Scripts/hub/tmod-control.sh stop     # stop the running server cleanly
bash Scripts/hub/tmod-control.sh restart  # restart the managed server process
bash Scripts/hub/tmod-control.sh status   # print a quick status summary
```

### Workshop commands

```bash
bash Scripts/hub/tmod-control.sh workshop download        # download Workshop mods listed in mod_ids.txt
bash Scripts/hub/tmod-control.sh workshop sync            # copy compatible Workshop mods into Mods/
bash Scripts/hub/tmod-control.sh workshop sync --yes      # run sync non-interactively
bash Scripts/hub/tmod-control.sh workshop list            # inspect downloaded Workshop mods
bash Scripts/hub/tmod-control.sh workshop archive         # archive old incompatible mod versions
bash Scripts/hub/tmod-control.sh workshop archive --yes   # run archival non-interactively
bash Scripts/hub/tmod-control.sh workshop cleanup         # remove incomplete Workshop leftovers
bash Scripts/hub/tmod-control.sh workshop status          # show Workshop paths and SteamCMD status
```

### Backup and diagnostics

```bash
bash Scripts/hub/tmod-control.sh backup worlds     # back up world save files
bash Scripts/hub/tmod-control.sh backup configs    # back up server and script config files
bash Scripts/hub/tmod-control.sh backup full       # create a full repo-local server backup
bash Scripts/hub/tmod-control.sh backup auto       # run the default automatic backup flow
bash Scripts/hub/tmod-control.sh monitor start     # start the background health monitor
bash Scripts/hub/tmod-control.sh monitor status    # inspect monitor status
bash Scripts/hub/tmod-control.sh diagnostics       # run the full diagnostics entrypoint
bash Scripts/diag/tmod-diagnostics.sh report       # generate a standalone diagnostics report
```

For the full command surface:

```bash
bash Scripts/hub/tmod-control.sh help  # print the shell hub usage summary
man tmod-control                       # open the installed man page
```

## Local Configuration

### `Configs/serverconfig.txt`

`make setup` creates this file from `Configs/serverconfig.example.txt`. It is the main local server config and is intentionally gitignored.

Useful notes:

- `world=` and `worldname=` are usually managed by the world picker
- `steamcmd_path` defaults to `./Tools/SteamCMD/steamcmd.sh`
- script settings live under the `tmod-scripts` section at the bottom
- paths support absolute values, `~/...`, and project-relative paths like `./Tools/SteamCMD/steamcmd.sh`

Example:

```ini
# ─── tmod-scripts ─────────────────────────────────────────────────────────────
steamcmd_path=./Tools/SteamCMD/steamcmd.sh
log_max_size=10M
log_keep_days=14
```

### `Scripts/env.sh`

`make setup` creates this file from `Scripts/env.example.sh`. Use it for local values you do not want in tracked files, such as:

- `STEAM_USERNAME`
- `STEAM_API_KEY`
- webhook URLs
- machine-specific overrides

For Workshop downloads, `STEAM_USERNAME` is optional. Anonymous SteamCMD access is used as a fallback, but a real Steam account may be more reliable for larger download batches.

### `Scripts/steam/mod_ids.txt`

`make setup` creates this file from `Scripts/steam/mod_ids.example.txt` if it is missing. It is local and gitignored. Add one Steam Workshop URL or numeric ID per line. Lines starting with `#` are ignored.

The Go UI can manage this file natively through `Workshop / Add Mod by URL or ID`, and `Workshop / Manage Installed Mods` writes the matching `Mods/enabled.json` load list:

```bash
bash Scripts/hub/tmod-control.sh mods add https://steamcommunity.com/sharedfiles/filedetails/?id=2824688804   # add by Workshop URL
bash Scripts/hub/tmod-control.sh mods add 2824688804                                                        # add by numeric Workshop ID
```

Direct editing works fine too.

### `Configs/workshop_map.json`

Optional local file for mapping mod names to Workshop IDs when dependency helpers need a manual hint.

```json
{
  "MyMod": "1234567890"
}
```

## Runtime Notes

### .NET runtime

You do not need to install the tModLoader runtime manually. On first server start, the toolkit reads the required version from `Engine/tModLoader.runtimeconfig.json` and runs tModLoader's bundled installer into `Engine/dotnet/`.

If that install fails, check:

- `Logs/dotnet-install.log`
- that `Engine/` contains a valid tModLoader server install
- that the host can reach the required download endpoints

### What stays out of git

`.gitignore` already excludes:

- `Engine/`, `Mods/`, `Worlds/`, `ModConfigs/`, `Backups/`, `Logs/`, and `Tools/SteamCMD/`
- `Configs/serverconfig.txt` and `Configs/workshop_map.json`
- `Scripts/env.sh` and `Scripts/steam/mod_ids.txt`
- `Testing/local/`, `Testing/output/`, and `Testing/tmp/`
- `bin/`, `tmodloader-ui`, `cmd/tmodloader-ui/tmodloader-ui`, `coverage.out`, `*.coverprofile`, `*.test`, `*.prof`, and `*.pprof`

That keeps the public repo clean while still letting the project behave like a complete local server workspace.

## Addons

The Go control room can load extra sections and actions from addon manifests in `Addons/<addon-name>/addon.json`.

Each manifest defines a default `section` plus one or more `actions`. By default, addon actions run with their own addon directory as the working directory, so local helper scripts can be referenced directly.

Example structure:

```text
Addons/
└── admin-tools/
    ├── addon.json
    └── scripts/
        ├── audit-world.sh
        └── rotate-admin-tokens.sh
```

Example manifest:

```json
{
  "name": "admin-tools",
  "section": "Admin",
  "actions": [
    {
      "title": "Audit World",
      "description": "Run the world audit helper.",
      "command": ["bash", "scripts/audit-world.sh"]
    },
    {
      "title": "Rotate Admin Tokens",
      "description": "Rotate admin auth material.",
      "command": ["bash", "scripts/rotate-admin-tokens.sh"],
      "confirm_text": "Rotate admin tokens now?"
    }
  ]
}
```

Supported manifest fields:

- `name`: optional label for the addon bundle
- `section`: default UI section name for all actions in the file
- `actions[].section`: optional per-action override if one addon needs multiple sections
- `actions[].title`: action label shown in the UI
- `actions[].description`: short help text for the selected action panel
- `actions[].command`: argv array to execute
- `actions[].confirm_text`: optional confirm prompt before running
- `actions[].working_dir`: optional working directory

`actions[].command` and `actions[].working_dir` also support `${repo_dir}` and `${addon_dir}` placeholders. Invalid addon manifests are skipped with warnings in the control room and details in `Logs/control.log`.

See [Addons/README.md](/home/matt/githubprojects/tmodloader-github/tmodloader-server/Addons/README.md) for the same rules in a smaller reference format.

## Changelog

Release history lives in [`CHANGELOG.md`](CHANGELOG.md).

Add new user-facing changes to `Unreleased` there so the README can stay focused on setup, usage, and the self-contained layout.

## Releases

No GitHub release is published yet, but the current documented state of the public portable edition is `v2.6.0`.

## Contributing

Issues, feature requests, and pull requests are welcome.

See `CONTRIBUTING.md` for contribution guidelines and `SECURITY.md` for responsible disclosure.

## License

Apache 2.0. See `LICENSE` for details.
