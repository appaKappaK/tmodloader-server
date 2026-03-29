# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog. Add new user-facing changes to `Unreleased`, then move them into a versioned section when cutting a release.

## [Unreleased]

### Added

- Added a standalone project `CHANGELOG.md` so release history no longer has to live inside the README.
- Added manifest-driven `Addons/*/addon.json` loading so extra sections and command actions can be plugged into the Go control room without editing the built-in action list.
- Added addon warning surfacing in the Go control room header and command-output pane, so broken addon manifests are easier to troubleshoot than a log-only failure.

### Changed

- Tightened the README around the repo-local, self-contained layout so setup-generated local files and gitignored runtime data are documented in one place.
- Retired the legacy shell UI entrypoints so interactive launches now go straight to the Go control room or fail with a clear setup message.
- Restored per-mod config editing in the Go control room through a config picker that opens the selected file in your terminal editor.
- Restored native Workshop URL/ID entry and a native installed-mod load manager in the Go control room, so adding queued mods and editing `enabled.json` no longer depend on the old shell menus.
- Added a subtle hotkey legend to the left panel that keeps the full shortcut set visible while giving the active bindings slightly more contrast on each screen.
- Moved the horizontal scroll readout to a fixed footer line in the output pane and removed the duplicate server state row from the snapshot panel.
- Added a minimum supported terminal size guard so narrow windows show a resize prompt instead of crunching the fixed-width control panels.
- Removed the transient yellow notice line from the header area and made mouse hover track the currently highlighted row in the action and picker lists.
- Normalized Go control room command output and simplified the shell hub's status and maintenance copy so severity stays readable without shell-era emoji formatting.
- Moved the Go UI entrypoint into `cmd/tmodloader-ui` and the app code into `internal/controlroom`, keeping the repo root focused on the Makefile, docs, and script surface.
- Refreshed the README, shell help, man page, contributor docs, and `.gitignore` around the newer control-room, addon, and native workshop flows.

### Fixed

- Fixed laptop-style temperature reporting and integer temperature formatting so representative CPU readings do not collapse into misleading values like `7C`.
- Fixed the snapshot panel so server-only metrics such as CPU, memory, uptime, and players show `n/a` instead of fake zeroes while the server is offline.
- Fixed header truncation caused by transient notices and invalid non-log `l` handling, keeping the top status line stable.

## [2.6.0] - 2026-03-27

### Added

- Added a Bubble Tea-based headless server console that keeps the screen alive while backend actions run.
- Added a section overview, native section pages, and a broader set of shell-backed admin actions in the Go TUI.
- Added `make tui-run` and `make tui-build` so the Go UI is easy to launch from source or build into `bin/tmodloader-ui`.
- Added a live `Server Snapshot` with running state, PID, world, players, mod and backup counts, CPU, RSS memory, uptime, disk activity, and host temperature.

### Changed

- `bash Scripts/hub/tmod-control.sh` now prefers the Go TUI for interactive launches, while keeping `interactive classic` and `TMOD_FORCE_LEGACY_UI=1` for the legacy shell UI.
- Log tails and command output now stay inside the app instead of dropping users back into raw shell output.
- Tightened pane layout, empty states, mouse-wheel handling, and overview/action previews so the interface behaves more like a persistent SSH console than a shell launcher.
- Existing script-driven workflows continue to work through the same `tmod-control.sh`, backup, workshop, diagnostics, and monitor commands.

### Fixed

- Hardened status polling so offline states do not flicker or report bogus PID, memory, or uptime values.

## [2.5.2] - 2026-03-27

### Added

- Added a dependency-aware interactive hub that can use `dialog` for boxed menus and log viewers plus `fzf` for searchable pickers, while keeping plain-Bash fallback intact.
- Added `--yes` support to workshop sync, workshop archive, mod-list clearing, and backup restore so scripted flows do not hang on confirmations.

### Changed

- Expanded the command palette into a fuller direct-action launcher instead of mostly routing through submenu pages.
- Unified page navigation around shared menu and picker helpers for worlds, backups, mod configs, logs, and common prompts.
- Updated maintenance to run workshop sync non-interactively, matching the cron-style examples in the docs.

### Fixed

- Tightened workshop sync so pre-2023 mod builds are skipped consistently instead of being copied into `Mods/`.
- Fixed restore correctness by switching rsync-based restore paths to checksum mode.
- Fixed same-second backup filename collisions so pre-restore safety backups cannot overwrite the archive being restored.

## [2.5.1] - 2026-03-27

### Added

- Added `make steamcmd-local` for repo-local SteamCMD bootstrap.
- Added `Scripts/env.example.sh` and improved `make setup` for portable onboarding.
- Added GitHub community health files, issue templates, a PR template, and a CI workflow for the public repo.

### Changed

- Reworked the toolkit into a project-root portable layout instead of assuming a fixed home-directory install.
- `steamcmd_path` now defaults to `./Tools/SteamCMD/steamcmd.sh`.
- Added support for project-relative paths in config so tracked examples stay machine-agnostic.
- Reframed the repo and README around the portable public edition.

### Fixed

- Fixed full backup and full restore to respect the capitalized `Logs/` and `Backups/` layout.
- Fixed diagnostics `auto_fix` to recreate the actual repo directory structure instead of legacy lowercase paths.
- Fixed monitor process detection so monitoring and health checks agree with the server start mode.
- Fixed `tmod-control.sh diagnostics` to run the full diagnostics script instead of the lightweight inline summary.

## [2.5.0] - 2026-03-01

These notes were inherited from the original `tmodloaderserver` line before the portable fork became the public repo.

### Added

- Expanded Monitoring with dashboard, health check, live monitor, log viewing, and console attach.
- Expanded Backup with inline restore and verify pickers, cleanup, and log viewing.
- Added Mod Configs editing from the Mods page.
- Added world import flow from pre-uploaded `.wld` files.
- Added `--debug` support through `TMOD_DEBUG=1` for noisier child-script output.
- Added configurable log rotation settings and improved rotated log handling.
- Added `server_config_get()` helper support in core scripts.

### Changed

- Restructured all five menu pages for a better headless-server workflow.
- Moved script logging to file-first behavior while keeping warnings and errors visible in the terminal.
- Renamed the main directories to the capitalized tModLoader-style layout.
- Moved `STEAMCMD_PATH` handling into `serverconfig.txt` as `steamcmd_path=`.
- Started treating `Scripts/steam/mod_ids.txt` as a local gitignored file with a tracked example template.
- Excluded `*.bak` from git.

### Removed

- Removed obsolete Download Mods and Sync Mods menu items in favor of the URL-to-`enabled.json` flow.
- Removed the whitelist system from the toolkit.
