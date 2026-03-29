# Addons

Drop addon manifests into `Addons/<addon-name>/addon.json` to add extra sections and actions to the Go control room.

The loader currently supports command-style actions only.

## Manifest

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

## Notes

- `section` is the default category name in the UI.
- `actions[].section` can override the manifest-level section.
- `actions[].working_dir` defaults to the addon directory.
- `${repo_dir}` and `${addon_dir}` placeholders are expanded in `command` and `working_dir`.
- Invalid addon entries are skipped, surfaced as warnings in the control room, and noted in `Logs/control.log`.
