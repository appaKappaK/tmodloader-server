package controlroom

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestLoadAddonActionsLoadsManifestActions(t *testing.T) {
	baseDir := t.TempDir()
	addonDir := filepath.Join(baseDir, "Addons", "admin-tools")
	if err := os.MkdirAll(filepath.Join(addonDir, "scripts"), 0o755); err != nil {
		t.Fatalf("mkdir addon dir: %v", err)
	}

	manifest := `{
  "name": "admin-tools",
  "section": "Admin",
  "actions": [
    {
      "title": "Audit World",
      "description": "Run an addon-local audit helper.",
      "command": ["bash", "${addon_dir}/scripts/audit-world.sh"]
    },
    {
      "section": "Ops",
      "title": "Health Snapshot",
      "description": "Call back into the repo root.",
      "command": ["bash", "${repo_dir}/Scripts/hub/tmod-control.sh", "health"],
      "working_dir": "${repo_dir}",
      "confirm_text": "Run health snapshot now?"
    }
  ]
}`

	manifestPath := filepath.Join(addonDir, "addon.json")
	if err := os.WriteFile(manifestPath, []byte(manifest), 0o644); err != nil {
		t.Fatalf("write manifest: %v", err)
	}

	actions, warnings := loadAddonActions(baseDir)
	if len(warnings) != 0 {
		t.Fatalf("expected no warnings, got %v", warnings)
	}
	if len(actions) != 2 {
		t.Fatalf("expected 2 actions, got %d", len(actions))
	}

	first := actions[0]
	if first.category != "Admin" {
		t.Fatalf("expected first category Admin, got %q", first.category)
	}
	if first.title != "Admin / Audit World" {
		t.Fatalf("unexpected first title: %q", first.title)
	}
	if first.workDir != addonDir {
		t.Fatalf("expected default workDir %q, got %q", addonDir, first.workDir)
	}
	if first.addonName != "admin-tools" {
		t.Fatalf("expected addonName admin-tools, got %q", first.addonName)
	}
	if first.addonManifest != manifestPath {
		t.Fatalf("expected addonManifest %q, got %q", manifestPath, first.addonManifest)
	}
	wantFirstCommand := []string{"bash", filepath.Join(addonDir, "scripts", "audit-world.sh")}
	if !reflect.DeepEqual(first.command, wantFirstCommand) {
		t.Fatalf("unexpected first command: got %v want %v", first.command, wantFirstCommand)
	}

	second := actions[1]
	if second.category != "Ops" {
		t.Fatalf("expected second category Ops, got %q", second.category)
	}
	if second.title != "Ops / Health Snapshot" {
		t.Fatalf("unexpected second title: %q", second.title)
	}
	if second.workDir != baseDir {
		t.Fatalf("expected second workDir %q, got %q", baseDir, second.workDir)
	}
	if second.confirmText != "Run health snapshot now?" {
		t.Fatalf("unexpected confirm text: %q", second.confirmText)
	}
	wantSecondCommand := []string{"bash", filepath.Join(baseDir, "Scripts", "hub", "tmod-control.sh"), "health"}
	if !reflect.DeepEqual(second.command, wantSecondCommand) {
		t.Fatalf("unexpected second command: got %v want %v", second.command, wantSecondCommand)
	}
}

func TestLoadAddonActionsWarnsAndSkipsInvalidEntries(t *testing.T) {
	baseDir := t.TempDir()

	badJSONDir := filepath.Join(baseDir, "Addons", "broken-json")
	if err := os.MkdirAll(badJSONDir, 0o755); err != nil {
		t.Fatalf("mkdir broken addon dir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(badJSONDir, "addon.json"), []byte(`{"section":"Broken","actions":[`), 0o644); err != nil {
		t.Fatalf("write broken manifest: %v", err)
	}

	badActionDir := filepath.Join(baseDir, "Addons", "broken-action")
	if err := os.MkdirAll(badActionDir, 0o755); err != nil {
		t.Fatalf("mkdir broken action dir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(badActionDir, "addon.json"), []byte(`{
  "section": "Admin",
  "actions": [
    {
      "description": "Missing title and command"
    }
  ]
}`), 0o644); err != nil {
		t.Fatalf("write invalid action manifest: %v", err)
	}

	actions, warnings := loadAddonActions(baseDir)
	if len(actions) != 0 {
		t.Fatalf("expected no actions, got %d", len(actions))
	}
	if len(warnings) != 2 {
		t.Fatalf("expected 2 warnings, got %d: %v", len(warnings), warnings)
	}
	if !containsWarning(warnings, "broken-json") {
		t.Fatalf("expected warning mentioning broken-json, got %v", warnings)
	}
	if !containsWarning(warnings, "Skipping action 1") {
		t.Fatalf("expected warning mentioning invalid action, got %v", warnings)
	}
}

func TestLoadAddonActionsUsesRelativeWorkingDirAndFallbackDescription(t *testing.T) {
	baseDir := t.TempDir()
	addonDir := filepath.Join(baseDir, "Addons", "admin-tools")
	if err := os.MkdirAll(filepath.Join(addonDir, "scripts"), 0o755); err != nil {
		t.Fatalf("mkdir addon dir: %v", err)
	}

	if err := os.WriteFile(filepath.Join(addonDir, "addon.json"), []byte(`{
  "section": "Admin",
  "actions": [
    {
      "title": "Relative Runner",
      "command": ["bash", "run.sh"],
      "working_dir": "scripts"
    }
  ]
}`), 0o644); err != nil {
		t.Fatalf("write manifest: %v", err)
	}

	actions, warnings := loadAddonActions(baseDir)
	if len(warnings) != 0 {
		t.Fatalf("expected no warnings, got %v", warnings)
	}
	if len(actions) != 1 {
		t.Fatalf("expected 1 action, got %d", len(actions))
	}

	got := actions[0]
	if got.workDir != filepath.Join(addonDir, "scripts") {
		t.Fatalf("unexpected workDir: %q", got.workDir)
	}
	if got.description != "Run addon action." {
		t.Fatalf("unexpected fallback description: %q", got.description)
	}
}

func TestCategoriesForActionsKeepsBuiltInsOrderedAndAppendsCustomSections(t *testing.T) {
	actions := []action{
		{category: "Admin"},
		{category: "Workshop"},
		{category: "Custom"},
		{category: "Maintenance"},
		{category: "Admin"},
	}

	got := categoriesForActions(actions)
	want := []string{overviewCategory, "Workshop", "Maintenance", "Admin", "Custom"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected categories: got %v want %v", got, want)
	}
}

func TestStreamCommandToUsesWorkingDirAndCleansOutput(t *testing.T) {
	baseDir := t.TempDir()
	lines := []string{}

	err := streamCommandTo(baseDir, []string{
		"bash",
		"-lc",
		`printf '✅ Ready\n⚠ Watch\n'; printf '\033[31mDanger\033[0m\n'; pwd`,
	}, func(line string) {
		lines = append(lines, line)
	})
	if err != nil {
		t.Fatalf("stream command: %v", err)
	}

	want := []string{"[ok] Ready", "[warn] Watch", "Danger", baseDir}
	if !reflect.DeepEqual(lines, want) {
		t.Fatalf("unexpected cleaned output: got %v want %v", lines, want)
	}
}

func TestStreamCommandToCapturesStdoutAndStderr(t *testing.T) {
	baseDir := t.TempDir()
	lines := []string{}

	err := streamCommandTo(baseDir, []string{
		"bash",
		"-lc",
		`printf 'stdout ok\n'; printf 'stderr warn\n' >&2`,
	}, func(line string) {
		lines = append(lines, line)
	})
	if err != nil {
		t.Fatalf("stream command: %v", err)
	}

	if !containsWarning(lines, "stdout ok") {
		t.Fatalf("expected stdout line in %v", lines)
	}
	if !containsWarning(lines, "stderr warn") {
		t.Fatalf("expected stderr line in %v", lines)
	}
}

func TestFormatTemperatureKeepsWholeNumberTrailingZeroes(t *testing.T) {
	cases := map[string]string{
		"70":    "70C",
		"70C":   "70C",
		"70.0":  "70C",
		"70.5":  "70.5C",
		"88":    "88C",
		"68":    "68C",
		"n/a":   "n/a",
		"weird": "n/a",
	}

	for input, want := range cases {
		if got := formatTemperature(input); got != want {
			t.Fatalf("formatTemperature(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestFormatPercentAndMemoryShowUnavailableWhenNotAvailable(t *testing.T) {
	if got := formatPercent("n/a"); got != "n/a" {
		t.Fatalf("formatPercent(n/a) = %q, want n/a", got)
	}
	if got := formatPercent(""); got != "n/a" {
		t.Fatalf("formatPercent(empty) = %q, want n/a", got)
	}
	if got := formatMemoryRSS("n/a"); got != "n/a" {
		t.Fatalf("formatMemoryRSS(n/a) = %q, want n/a", got)
	}
	if got := formatMemoryRSS(""); got != "n/a" {
		t.Fatalf("formatMemoryRSS(empty) = %q, want n/a", got)
	}
	if got := formatMemoryRSS("0"); got != "0MB" {
		t.Fatalf("formatMemoryRSS(0) = %q, want 0MB", got)
	}
}

func TestFormatUptimeAndBackupCountShowUnavailableWhenNotAvailable(t *testing.T) {
	if got := formatUptimeDuration("n/a"); got != "n/a" {
		t.Fatalf("formatUptimeDuration(n/a) = %q, want n/a", got)
	}
	if got := formatUptimeDuration(""); got != "n/a" {
		t.Fatalf("formatUptimeDuration(empty) = %q, want n/a", got)
	}
	if got := formatUptimeDuration("0"); got != "0s" {
		t.Fatalf("formatUptimeDuration(0) = %q, want 0s", got)
	}
}

func containsWarning(warnings []string, fragment string) bool {
	for _, warning := range warnings {
		if strings.Contains(warning, fragment) {
			return true
		}
	}
	return false
}
