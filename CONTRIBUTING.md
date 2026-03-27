# Contributing

Thanks for helping improve `tmodloader`.

## Scope

This repo is the portable/public edition of the toolkit. Changes should favor:

- portable defaults over machine-specific assumptions
- safe, documented workflows for first-time users
- clear shell scripts and predictable file layout
- keeping runtime data and secrets out of git

## Before You Open A PR

1. Run shell syntax checks for any scripts you touched.
2. Update `README.md` when behavior, setup, or file layout changes.
3. Keep new tracked files generic and reusable.
4. Do not commit local runtime data such as worlds, logs, backups, or SteamCMD contents.

## Style Notes

- Prefer POSIX-friendly shell where practical, but Bash is fine when already used.
- Keep comments brief and useful.
- Avoid hardcoded home-directory paths when a project-relative path will work.
- Match the existing directory naming: `Engine/`, `Configs/`, `Logs/`, `Backups/`, `Scripts/`.

## Testing

Useful checks:

```bash
bash -n Scripts/core/tmod-core.sh
bash -n Scripts/hub/tmod-control.sh
bash -n Scripts/steam/tmod-workshop.sh
bash Scripts/hub/tmod-control.sh status
```

If your change affects other scripts, run the relevant `bash -n` checks too.

## Pull Requests

- Keep PRs focused.
- Explain the user-facing impact.
- Mention any setup or migration changes.
- Include follow-up work separately instead of bundling unrelated cleanup.
