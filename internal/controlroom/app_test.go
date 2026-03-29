package controlroom

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

func TestAddonSmokeMatrixLoadsIntoModelAndRunsCommands(t *testing.T) {
	baseDir := t.TempDir()

	if err := os.MkdirAll(filepath.Join(baseDir, "Addons", "smoke-scripts", "scripts"), 0o755); err != nil {
		t.Fatalf("mkdir smoke-scripts addon: %v", err)
	}
	if err := os.MkdirAll(filepath.Join(baseDir, "Addons", "smoke-admin"), 0o755); err != nil {
		t.Fatalf("mkdir smoke-admin addon: %v", err)
	}
	if err := os.MkdirAll(filepath.Join(baseDir, "Addons", "smoke-broken"), 0o755); err != nil {
		t.Fatalf("mkdir smoke-broken addon: %v", err)
	}
	if err := os.MkdirAll(filepath.Join(baseDir, "Addons", "smoke-ignored"), 0o755); err != nil {
		t.Fatalf("mkdir smoke-ignored addon: %v", err)
	}

	if err := os.WriteFile(filepath.Join(baseDir, "Addons", "smoke-scripts", "addon.json"), []byte(`{
  "name": "smoke-scripts",
  "section": "Smoke",
  "actions": [
    {
      "title": "Addon Local",
      "description": "Temporary smoke-test action using the addon root.",
      "command": [
        "bash",
        "-lc",
        "printf 'smoke local ok\n'; [ -d \"$1\" ] && printf 'addon arg ok\n'; basename \"$PWD\"",
        "_",
        "${addon_dir}"
      ]
    },
    {
      "title": "Relative Dir",
      "description": "Temporary smoke-test action using a relative working dir.",
      "command": [
        "bash",
        "-lc",
        "printf 'smoke relative ok\n'; basename \"$PWD\""
      ],
      "working_dir": "scripts"
    }
  ]
}`), 0o644); err != nil {
		t.Fatalf("write smoke-scripts manifest: %v", err)
	}

	if err := os.WriteFile(filepath.Join(baseDir, "Addons", "smoke-admin", "addon.json"), []byte(`{
  "name": "smoke-admin",
  "section": "Admin",
  "actions": [
    {
      "title": "Repo Root",
      "description": "Temporary smoke-test action using the repo root.",
      "command": [
        "bash",
        "-lc",
        "printf 'admin repo ok\n'; [ -d Addons ] && printf 'repo dir ok\n'; basename \"$PWD\""
      ],
      "working_dir": "${repo_dir}"
    },
    {
      "section": "Ops",
      "title": "Override",
      "description": "Temporary smoke-test action using a section override.",
      "command": [
        "bash",
        "-lc",
        "printf 'ops override ok\n'; basename \"$PWD\""
      ]
    }
  ]
}`), 0o644); err != nil {
		t.Fatalf("write smoke-admin manifest: %v", err)
	}

	if err := os.WriteFile(filepath.Join(baseDir, "Addons", "smoke-broken", "addon.json"), []byte(`{"section":"Broken","actions":[`), 0o644); err != nil {
		t.Fatalf("write broken manifest: %v", err)
	}

	if err := os.WriteFile(filepath.Join(baseDir, "Addons", "smoke-ignored", "addon.json.example"), []byte(`{
  "section": "Ignored",
  "actions": [
    {
      "title": "Should Not Load",
      "command": ["bash", "-lc", "printf 'ignored\n'"]
    }
  ]
}`), 0o644); err != nil {
		t.Fatalf("write ignored example manifest: %v", err)
	}

	m := newModel(baseDir)

	for _, category := range []string{"Smoke", "Admin", "Ops"} {
		if !containsString(m.categories, category) {
			t.Fatalf("expected category %q in %v", category, m.categories)
		}
	}
	for _, category := range []string{"Broken", "Ignored"} {
		if containsString(m.categories, category) {
			t.Fatalf("did not expect category %q in %v", category, m.categories)
		}
	}

	smokeLocal, ok := actionByTitle(m.actions, "Smoke / Addon Local")
	if !ok {
		t.Fatalf("expected Smoke / Addon Local action")
	}
	smokeRelative, ok := actionByTitle(m.actions, "Smoke / Relative Dir")
	if !ok {
		t.Fatalf("expected Smoke / Relative Dir action")
	}
	adminRepo, ok := actionByTitle(m.actions, "Admin / Repo Root")
	if !ok {
		t.Fatalf("expected Admin / Repo Root action")
	}
	opsOverride, ok := actionByTitle(m.actions, "Ops / Override")
	if !ok {
		t.Fatalf("expected Ops / Override action")
	}

	assertActionOutputs := func(act action, expected ...string) {
		t.Helper()
		lines := []string{}
		err := streamCommandTo(act.workDir, act.command, func(line string) {
			lines = append(lines, line)
		})
		if err != nil {
			t.Fatalf("run %q: %v", act.title, err)
		}
		for _, want := range expected {
			if !containsWarning(lines, want) {
				t.Fatalf("expected output %q in %v", want, lines)
			}
		}
	}

	assertActionOutputs(smokeLocal, "smoke local ok", "addon arg ok", "smoke-scripts")
	assertActionOutputs(smokeRelative, "smoke relative ok", "scripts")
	assertActionOutputs(adminRepo, "admin repo ok", "repo dir ok", filepath.Base(baseDir))
	assertActionOutputs(opsOverride, "ops override ok", "smoke-admin")

	controlLog := filepath.Join(baseDir, "Logs", "control.log")
	data, err := os.ReadFile(controlLog)
	if err != nil {
		t.Fatalf("read control log: %v", err)
	}
	if !strings.Contains(string(data), "Skipping addon manifest") || !strings.Contains(string(data), "smoke-broken") {
		t.Fatalf("expected broken addon warning in control log, got %q", string(data))
	}
}

func TestNewModelLoadsAddonActionsAndLogsWarnings(t *testing.T) {
	baseDir := t.TempDir()

	goodAddonDir := filepath.Join(baseDir, "Addons", "admin-tools")
	if err := os.MkdirAll(goodAddonDir, 0o755); err != nil {
		t.Fatalf("mkdir good addon dir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(goodAddonDir, "addon.json"), []byte(`{
  "section": "Admin",
  "actions": [
    {
      "title": "Health Snapshot",
      "description": "Run a custom admin helper.",
      "command": ["bash", "-lc", "true"]
    }
  ]
}`), 0o644); err != nil {
		t.Fatalf("write good addon manifest: %v", err)
	}

	badAddonDir := filepath.Join(baseDir, "Addons", "broken")
	if err := os.MkdirAll(badAddonDir, 0o755); err != nil {
		t.Fatalf("mkdir bad addon dir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(badAddonDir, "addon.json"), []byte(`{"section":"Broken","actions":[`), 0o644); err != nil {
		t.Fatalf("write bad addon manifest: %v", err)
	}

	m := newModel(baseDir)

	if !containsString(m.categories, "Admin") {
		t.Fatalf("expected Admin category in %v", m.categories)
	}

	foundAction := false
	for _, act := range m.actions {
		if act.title == "Admin / Health Snapshot" {
			foundAction = true
			if act.workDir != goodAddonDir {
				t.Fatalf("expected addon workDir %q, got %q", goodAddonDir, act.workDir)
			}
		}
	}
	if !foundAction {
		t.Fatalf("expected addon action to be loaded")
	}

	controlLog := filepath.Join(baseDir, "Logs", "control.log")
	data, err := os.ReadFile(controlLog)
	if err != nil {
		t.Fatalf("read control log: %v", err)
	}
	if !strings.Contains(string(data), "Skipping addon manifest") {
		t.Fatalf("expected addon warning in control log, got %q", string(data))
	}
	if len(m.addonWarnings) != 1 {
		t.Fatalf("expected 1 addon warning, got %d", len(m.addonWarnings))
	}
	if !containsWarning(m.outputLines, "[warn] Skipping addon manifest") {
		t.Fatalf("expected startup command output warning, got %v", m.outputLines)
	}
}

func TestHandleNormalMouseMotionHighlightsAction(t *testing.T) {
	m := newModel(t.TempDir())
	m.width = 140
	m.height = 40
	m.ready = true
	m.categoryIndex = 1 // Server
	m.cursor = 0

	y, ok := actionPanelYForIndex(m, 2)
	if !ok {
		t.Fatalf("unable to find y coordinate for action index 2")
	}

	panelX, _, _, _, _, _, _, _ := m.actionPanelGeometry()
	msg := tea.MouseMsg{
		X:      panelX + 1,
		Y:      y,
		Action: tea.MouseActionMotion,
		Button: tea.MouseButtonNone,
	}

	if _, cmd := m.handleNormalMouse(msg); cmd != nil {
		t.Fatalf("expected no command from hover motion")
	}
	if m.cursor != 2 {
		t.Fatalf("expected cursor to move to 2, got %d", m.cursor)
	}
}

func TestHandleNormalMouseShiftWheelDoesNotScrollOutputHorizontally(t *testing.T) {
	m := newModel(t.TempDir())
	m.width = 140
	m.height = 40
	m.ready = true
	m.outputMode = outputModeCommand
	m.outputLines = []string{
		"This is a deliberately long command output line that should require horizontal scrolling in the output panel.",
	}

	_, _, _, _, contentX, contentY, _, _ := m.outputPanelGeometry()
	msg := tea.MouseMsg{
		X:      contentX + 1,
		Y:      contentY + 1,
		Action: tea.MouseActionPress,
		Button: tea.MouseButtonWheelDown,
		Shift:  true,
	}

	if _, cmd := m.handleNormalMouse(msg); cmd != nil {
		t.Fatalf("expected no command from shift+wheel scroll")
	}
	if m.commandXOffset != 0 {
		t.Fatalf("expected horizontal offset to stay 0, got %d", m.commandXOffset)
	}
}

func TestHandleNormalMouseWheelDoesNotScrollOutputHorizontallyWithoutShift(t *testing.T) {
	m := newModel(t.TempDir())
	m.width = 140
	m.height = 40
	m.ready = true
	m.outputMode = outputModeCommand
	m.outputLines = []string{
		"This is a deliberately long command output line that should require horizontal scrolling in the output panel.",
	}

	_, _, _, _, contentX, contentY, _, _ := m.outputPanelGeometry()
	msg := tea.MouseMsg{
		X:      contentX + 1,
		Y:      contentY + 1,
		Action: tea.MouseActionPress,
		Button: tea.MouseButtonWheelDown,
	}

	if _, cmd := m.handleNormalMouse(msg); cmd != nil {
		t.Fatalf("expected no command from wheel scroll")
	}
	if m.commandXOffset != 0 {
		t.Fatalf("expected horizontal offset to stay 0 without shift, got %d", m.commandXOffset)
	}
}

func TestHandleNormalMouseHorizontalWheelDoesNotScrollOutputHorizontally(t *testing.T) {
	m := newModel(t.TempDir())
	m.width = 140
	m.height = 40
	m.ready = true
	m.outputMode = outputModeCommand
	m.outputLines = []string{
		"This is a deliberately long command output line that should require horizontal scrolling in the output panel.",
	}

	_, _, _, _, contentX, contentY, _, _ := m.outputPanelGeometry()
	msg := tea.MouseMsg{
		X:      contentX + 1,
		Y:      contentY + 1,
		Action: tea.MouseActionPress,
		Button: tea.MouseButtonWheelRight,
	}

	if _, cmd := m.handleNormalMouse(msg); cmd != nil {
		t.Fatalf("expected no command from horizontal wheel scroll")
	}
	if m.commandXOffset != 0 {
		t.Fatalf("expected horizontal offset to stay 0 with horizontal wheel, got %d", m.commandXOffset)
	}
}

func TestHandleNormalKeysIgnoresLogSwitchOutsideLogView(t *testing.T) {
	m := newModel(t.TempDir())
	m.outputMode = outputModeCommand
	m.logSourceIndex = 2
	m.footer = "unchanged"
	m.footerTimestamp = time.Now().Add(time.Minute)

	if _, cmd := m.handleNormalKeys(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'l'}}); cmd != nil {
		t.Fatalf("expected no command from l outside log view")
	}
	if m.logSourceIndex != 2 {
		t.Fatalf("expected log source index to stay 2, got %d", m.logSourceIndex)
	}
	if m.footer != "unchanged" {
		t.Fatalf("expected footer to stay unchanged, got %q", m.footer)
	}
}

func TestHeaderShowsAddonWarningSummary(t *testing.T) {
	baseDir := t.TempDir()
	badAddonDir := filepath.Join(baseDir, "Addons", "broken")
	if err := os.MkdirAll(badAddonDir, 0o755); err != nil {
		t.Fatalf("mkdir bad addon dir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(badAddonDir, "addon.json"), []byte(`{"section":"Broken","actions":[`), 0o644); err != nil {
		t.Fatalf("write bad addon manifest: %v", err)
	}

	m := newModel(baseDir)
	m.width = 120
	m.height = 30

	rendered := m.renderHeader()
	if !strings.Contains(rendered, "addon warnings: 1") {
		t.Fatalf("expected addon warning summary in header, got %q", rendered)
	}
	if m.headerHeight() != 2 {
		t.Fatalf("expected header height 2 with addon warnings, got %d", m.headerHeight())
	}
}

func TestStartActionShowsAddonTroubleshootingForInvalidWorkingDir(t *testing.T) {
	baseDir := t.TempDir()
	m := newModel(baseDir)

	act := action{
		category:      "Smoke",
		title:         "Smoke / Broken Action",
		description:   "Broken addon action for troubleshooting output.",
		command:       []string{"bash", "-lc", "printf 'should not run\\n'"},
		workDir:       filepath.Join(baseDir, "Addons", "broken-addon", "missing"),
		addonName:     "broken-addon",
		addonManifest: filepath.Join(baseDir, "Addons", "broken-addon", "addon.json"),
	}

	m.startAction(act)

	if m.running {
		t.Fatalf("expected invalid addon action to fail before running")
	}
	if !containsWarning(m.outputLines, "Unable to start addon action") {
		t.Fatalf("expected startup failure line in %v", m.outputLines)
	}
	if !containsWarning(m.outputLines, "Manifest: Addons/broken-addon/addon.json") {
		t.Fatalf("expected manifest line in %v", m.outputLines)
	}
	if !containsWarning(m.outputLines, "Working dir: Addons/broken-addon/missing") {
		t.Fatalf("expected working dir line in %v", m.outputLines)
	}
	if !containsWarning(m.outputLines, "Hint: Check the addon working_dir path in addon.json.") {
		t.Fatalf("expected working_dir hint in %v", m.outputLines)
	}
}

func TestHeaderNoLongerRendersFooterNotice(t *testing.T) {
	m := newModel(t.TempDir())
	m.width = 120
	m.height = 30
	m.footer = "This old yellow popup should not render anymore."
	m.footerTimestamp = time.Now().Add(time.Minute)

	rendered := m.renderHeader()
	if strings.Contains(rendered, m.footer) {
		t.Fatalf("expected header to omit footer text, got %q", rendered)
	}
	if m.headerHeight() != 1 {
		t.Fatalf("expected base header height 1, got %d", m.headerHeight())
	}
}

func TestRenderOutputIndicatorUsesColumnLanguage(t *testing.T) {
	got := renderOutputIndicator(0, 60, 39)
	if !strings.Contains(got, "Viewing columns 1-39 of 99") {
		t.Fatalf("expected column wording in indicator, got %q", got)
	}
	if strings.Contains(got, "Horizontal scroll") {
		t.Fatalf("expected old horizontal scroll wording to be gone, got %q", got)
	}
}

func TestBuildOutputViewCommandSubtitleUsesStatusLineInsteadOfTabHint(t *testing.T) {
	m := newModel(t.TempDir())
	m.outputMode = outputModeCommand
	m.outputLines = []string{"hello"}

	view := m.buildOutputView(80, 12)
	if !strings.Contains(view.subtitle, "Current log source: server.log") {
		t.Fatalf("expected status subtitle, got %q", view.subtitle)
	}
	if strings.Contains(view.subtitle, "Tab") {
		t.Fatalf("expected tab hint to be removed from subtitle, got %q", view.subtitle)
	}
}

func actionPanelYForIndex(m *model, target int) (int, bool) {
	_, _, _, _, _, contentY, _, contentHeight := m.actionPanelGeometry()
	for y := contentY; y < contentY+contentHeight; y++ {
		index, ok := m.actionPanelListIndexAt(y)
		if ok && index == target {
			return y, true
		}
	}
	return 0, false
}

func actionByTitle(actions []action, want string) (action, bool) {
	for _, act := range actions {
		if act.title == want {
			return act, true
		}
	}
	return action{}, false
}
