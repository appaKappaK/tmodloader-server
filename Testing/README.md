# Testing Workspace

This folder is a small staging area for repeatable local checks without polluting the repo with throwaway scripts.

Tracked:

- `templates/` holds reusable skeletons
- this README explains the intended workflow

Ignored by git:

- `local/` for one-off test scripts you actually run
- `output/` for captured command output and notes
- `tmp/` for disposable worktrees, copies, and extracted artifacts

Suggested workflow:

```bash
mkdir -p Testing/local Testing/output Testing/tmp
cp Testing/templates/flow-smoke.template.sh Testing/local/flow-smoke.sh
chmod +x Testing/local/flow-smoke.sh
```

Then edit the copied script for the job at hand without worrying about committing it by accident.
