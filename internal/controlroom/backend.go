package controlroom

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

type logSource struct {
	label string
	path  string
}

type worldOption struct {
	Name     string
	Path     string
	Size     string
	Modified string
	Active   bool
}

type configOption struct {
	RelPath  string
	Path     string
	Size     string
	Modified string
}

type modOption struct {
	Name            string
	Enabled         bool
	OriginalEnabled bool
}

type addonManifest struct {
	Name    string                `json:"name"`
	Section string                `json:"section"`
	Actions []addonManifestAction `json:"actions"`
}

type addonManifestAction struct {
	Section     string   `json:"section"`
	Title       string   `json:"title"`
	Description string   `json:"description"`
	Command     []string `json:"command"`
	ConfirmText string   `json:"confirm_text"`
	WorkingDir  string   `json:"working_dir"`
}

type appStatus struct {
	Online       bool
	PID          string
	CPU          string
	Memory       string
	Uptime       string
	Players      string
	World        string
	ModCount     int
	WorldBackups int
	DiskBusy     string
	TempLabel    string
	TempValue    string
}

var ansiEscapePattern = regexp.MustCompile(`\x1b\[[0-9;?]*[ -/]*[@-~]`)
var numericValuePattern = regexp.MustCompile(`^[0-9]+(\.[0-9]+)?$`)
var wholeNumberPattern = regexp.MustCompile(`^[0-9]+$`)
var signedNumericValuePattern = regexp.MustCompile(`^-?[0-9]+(\.[0-9]+)?$`)
var decorativeLinePattern = regexp.MustCompile(`^[\s\p{So}\p{Sk}\p{Pd}\p{Pc}━─│┌┐└┘]+$`)
var outputGlyphReplacer = strings.NewReplacer(
	"\uFE0F", "",
	"✅ ", "[ok] ",
	"❌ ", "[error] ",
	"⚠ ", "[warn] ",
	"💡 ", "[tip] ",
	"ℹ ", "[info] ",
	"🟢 ", "",
	"🔴 ", "",
	"🟡 ", "",
	"🔵 ", "",
	"🎮 ", "",
	"🚀 ", "",
	"🛑 ", "",
	"🔄 ", "",
	"📦 ", "",
	"📋 ", "",
	"📁 ", "",
	"🧹 ", "",
	"🔍 ", "",
	"🔧 ", "",
	"📊 ", "",
	"🎉 ", "",
	"⚙ ", "",
	"🖥 ", "",
	"📈 ", "",
	"🔪 ", "",
	"📺 ", "",
	"💾 ", "",
	"💿 ", "",
	"⚡ ", "",
	"👥 ", "",
	"📅 ", "",
	"📝 ", "",
	"⏱ ", "Duration: ",
	"·", "|",
)

type diskBusySample struct {
	ioMillis int64
	at       time.Time
}

var diskBusyMu sync.Mutex
var diskBusySamples = map[string]diskBusySample{}

func defaultLogSources(baseDir string) []logSource {
	return []logSource{
		{label: "server.log", path: filepath.Join(baseDir, "Logs", "server.log")},
		{label: "control.log", path: filepath.Join(baseDir, "Logs", "control.log")},
		{label: "workshop.log", path: filepath.Join(baseDir, "Logs", "workshop.log")},
		{label: "backup.log", path: filepath.Join(baseDir, "Logs", "backup.log")},
		{label: "monitor.log", path: filepath.Join(baseDir, "Logs", "monitor.log")},
		{label: "diagnostics.log", path: filepath.Join(baseDir, "Logs", "diagnostics.log")},
	}
}

func (m *model) startAction(act action) {
	label := m.actionLabel(act)
	if err := validateRunnableAction(act); err != nil {
		m.running = false
		m.activeAction = ""
		m.activeSince = time.Time{}
		m.outputMode = outputModeCommand
		m.commandXOffset = 0
		m.outputLines = m.actionOutputIntroLines(act)
		if act.isAddonAction() {
			m.appendOutput("✗ Unable to start addon action: " + err.Error())
			m.appendAddonFailureDetails(act, err)
		} else {
			m.appendOutput("✗ Unable to start action: " + err.Error())
		}
		return
	}
	m.running = true
	m.activeAction = label
	m.activeSince = time.Now()
	m.outputMode = outputModeCommand
	m.commandXOffset = 0
	m.outputLines = m.actionOutputIntroLines(act)
	m.setFooter("Running "+label+"…", 4*time.Second)

	go func() {
		start := time.Now()
		runDir := act.workDir
		if strings.TrimSpace(runDir) == "" {
			runDir = m.baseDir
		}
		err := streamCommand(m.program, runDir, act.command)
		m.program.Send(commandDoneMsg{
			act:      act,
			label:    label,
			duration: time.Since(start),
			err:      err,
		})
	}()
}

func validateRunnableAction(act action) error {
	if len(act.command) == 0 {
		return errors.New("empty command")
	}
	if strings.TrimSpace(act.workDir) == "" {
		return nil
	}
	info, err := os.Stat(act.workDir)
	if err != nil {
		return fmt.Errorf("working_dir %q is unavailable: %w", act.workDir, err)
	}
	if !info.IsDir() {
		return fmt.Errorf("working_dir %q is not a directory", act.workDir)
	}
	return nil
}

func streamCommand(program *tea.Program, baseDir string, argv []string) error {
	if program == nil {
		return streamCommandTo(baseDir, argv, nil)
	}
	return streamCommandTo(baseDir, argv, func(line string) {
		program.Send(outputLineMsg{text: line})
	})
}

func streamCommandTo(baseDir string, argv []string, emit func(string)) error {
	if len(argv) == 0 {
		return errors.New("empty command")
	}

	cmd := exec.Command(argv[0], argv[1:]...)
	cmd.Dir = baseDir
	cmd.Env = append(os.Environ(), "TERM=dumb")

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return err
	}

	if err := cmd.Start(); err != nil {
		return err
	}

	done := make(chan struct{}, 2)
	var emitMu sync.Mutex
	stream := func(r io.Reader) {
		scanner := bufio.NewScanner(r)
		scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
		scanner.Split(scanConsoleLines)
		for scanner.Scan() {
			line := cleanOutputLine(scanner.Text())
			if line == "" {
				continue
			}
			if emit != nil {
				emitMu.Lock()
				emit(line)
				emitMu.Unlock()
			}
		}
		done <- struct{}{}
	}

	go stream(stdout)
	go stream(stderr)

	<-done
	<-done

	return cmd.Wait()
}

func refreshStatusCmd(baseDir string) tea.Cmd {
	return func() tea.Msg {
		status, err := loadStatus(baseDir)
		return statusMsg{status: status, err: err}
	}
}

func refreshLogCmd(source logSource) tea.Cmd {
	return func() tea.Msg {
		lines, err := readTailLines(source.path, 160)
		return logMsg{source: source.label, lines: lines, err: err}
	}
}

func listWorldsCmd(baseDir string, startAfter bool) tea.Cmd {
	return func() tea.Msg {
		worlds, err := listWorldOptions(baseDir)
		return worldListMsg{worlds: worlds, startAfter: startAfter, err: err}
	}
}

func setWorldCmd(baseDir string, world worldOption, startAfter bool) tea.Cmd {
	return func() tea.Msg {
		worldPath := filepath.Join(baseDir, "Worlds", world.Name+".wld")
		snippet := fmt.Sprintf(`
source Scripts/core/tmod-core.sh >/dev/null 2>&1 || exit 1
init_tmod >/dev/null 2>&1
server_config_set "world" %q
server_config_set "worldname" %q
`, worldPath, world.Name)

		cmd := exec.Command("bash", "-lc", snippet)
		cmd.Dir = baseDir
		cmd.Env = append(os.Environ(), "TERM=dumb")
		if out, err := cmd.CombinedOutput(); err != nil {
			return worldSetMsg{world: world.Name, startAfter: startAfter, err: fmt.Errorf("%v: %s", err, strings.TrimSpace(string(out)))}
		}

		return worldSetMsg{world: world.Name, startAfter: startAfter}
	}
}

func listModConfigsCmd(baseDir string) tea.Cmd {
	return func() tea.Msg {
		configs, err := listModConfigOptions(baseDir)
		return configListMsg{configs: configs, err: err}
	}
}

func editModConfigCmd(baseDir string, config configOption) tea.Cmd {
	editorSnippet := `
if [[ -n "${VISUAL:-}" ]]; then
  exec ${VISUAL} "$1"
fi
if [[ -n "${EDITOR:-}" ]]; then
  exec ${EDITOR} "$1"
fi
for candidate in nano nvim vim vi; do
  if command -v "$candidate" >/dev/null 2>&1; then
    exec "$candidate" "$1"
  fi
done
echo "No terminal editor found. Set \$VISUAL or \$EDITOR." >&2
exit 127
`

	cmd := exec.Command("bash", "-lc", editorSnippet, "bash", config.Path)
	cmd.Dir = baseDir
	cmd.Env = os.Environ()

	return tea.ExecProcess(cmd, func(err error) tea.Msg {
		return configEditDoneMsg{config: config, err: err}
	})
}

func listInstalledModsCmd(baseDir string) tea.Cmd {
	return func() tea.Msg {
		mods, err := listInstalledModOptions(baseDir)
		return modListMsg{mods: mods, err: err}
	}
}

func saveModSelectionCmd(baseDir string, mods []modOption) tea.Cmd {
	snapshot := append([]modOption(nil), mods...)
	return func() tea.Msg {
		enabledCount, changedCount, err := saveInstalledModOptions(baseDir, snapshot)
		return modSaveMsg{enabledCount: enabledCount, changedCount: changedCount, err: err}
	}
}

func statusTickCmd() tea.Cmd {
	return tea.Tick(3*time.Second, func(t time.Time) tea.Msg { return statusTickMsg(t) })
}

func logTickCmd() tea.Cmd {
	return tea.Tick(2*time.Second, func(t time.Time) tea.Msg { return logTickMsg(t) })
}

func spinnerTickCmd() tea.Cmd {
	return tea.Tick(120*time.Millisecond, func(t time.Time) tea.Msg { return spinnerMsg(t) })
}

func loadStatus(baseDir string) (appStatus, error) {
	snippet := `
source Scripts/core/tmod-core.sh >/dev/null 2>&1 || exit 1
init_tmod >/dev/null 2>&1

	pid="$(get_server_pid 2>/dev/null || true)"
	online=false
	cpu="0.0"
	mem_kb="0"
	uptime="0"
	players="0"
	if [[ -n "$pid" ]]; then
	  online=true
	  read -r cpu mem_kb etimes <<<"$(ps -p "$pid" -o %cpu=,rss=,etimes= --no-headers 2>/dev/null || echo "0.0 0 0")"
	  cpu="${cpu:-0.0}"
	  mem_kb="${mem_kb:-0}"
	  etimes="${etimes:-0}"
	  uptime="${etimes:-0}"
	  players="$(get_player_count 2>/dev/null || echo 0)"
	fi

world="$(basename "$(server_config_get world "" 2>/dev/null)" .wld 2>/dev/null)"
mods="$(get_mod_list 2>/dev/null | wc -l | tr -d ' ')"
backups="$(find "$BASE_DIR/Backups/Worlds" -maxdepth 1 -name 'worlds_*.tar.gz' 2>/dev/null | wc -l | tr -d ' ')"
disk_device="$(df -P "$BASE_DIR" 2>/dev/null | awk 'NR==2 {print $1}')"
disk_name="${disk_device##*/}"
disk_io_ms="$(awk -v dev="$disk_name" '$3==dev {print $13; found=1} END {if(!found) print ""}' /proc/diskstats 2>/dev/null)"
read -r temp_label temp_value <<<"$(get_host_temperatures 2>/dev/null || echo 'Temp n/a')"

	printf 'online=%s\n' "$online"
	printf 'pid=%s\n' "$pid"
	printf 'cpu=%s\n' "${cpu:-0.0}"
	printf 'mem=%s\n' "${mem_kb:-0}"
	printf 'uptime=%s\n' "${uptime:-0}"
printf 'players=%s\n' "${players:-0}"
printf 'world=%s\n' "$world"
printf 'mods=%s\n' "${mods:-0}"
printf 'backups=%s\n' "${backups:-0}"
printf 'disk_device=%s\n' "${disk_name:-}"
printf 'disk_io_ms=%s\n' "${disk_io_ms:-}"
printf 'temp_label=%s\n' "${temp_label:-Temp}"
printf 'temp_value=%s\n' "${temp_value:-n/a}"
`

	cmd := exec.Command("bash", "-lc", snippet)
	cmd.Dir = baseDir
	cmd.Env = append(os.Environ(), "TERM=dumb")

	out, err := cmd.Output()
	if err != nil {
		return appStatus{}, err
	}

	values := parseKeyValues(out)
	online := values["online"] == "true"
	pid := sanitizePID(values["pid"])
	if !online || pid == "" {
		online = false
		pid = ""
		values["cpu"] = "n/a"
		values["mem"] = "n/a"
		values["uptime"] = "n/a"
		values["players"] = "n/a"
	}

	status := appStatus{
		Online:       online,
		PID:          pid,
		CPU:          formatPercent(values["cpu"]),
		Memory:       formatMemoryRSS(values["mem"]),
		Uptime:       formatUptimeDuration(values["uptime"]),
		Players:      blankFallback(values["players"], "0"),
		World:        values["world"],
		ModCount:     atoi(values["mods"]),
		WorldBackups: atoi(values["backups"]),
		DiskBusy:     computeDiskBusy(baseDir, values["disk_device"], values["disk_io_ms"], time.Now()),
		TempLabel:    formatTemperatureLabel(values["temp_label"]),
		TempValue:    formatTemperature(values["temp_value"]),
	}

	return status, nil
}

func listWorldOptions(baseDir string) ([]worldOption, error) {
	worldPaths, err := filepath.Glob(filepath.Join(baseDir, "Worlds", "*.wld"))
	if err != nil {
		return nil, err
	}
	sort.Strings(worldPaths)

	activeWorld := strings.TrimSuffix(filepath.Base(readServerConfigValue(filepath.Join(baseDir, "Configs", "serverconfig.txt"), "world")), ".wld")
	options := make([]worldOption, 0, len(worldPaths))
	for _, path := range worldPaths {
		info, err := os.Stat(path)
		if err != nil {
			continue
		}
		name := strings.TrimSuffix(filepath.Base(path), ".wld")
		options = append(options, worldOption{
			Name:     name,
			Path:     path,
			Size:     humanSize(info.Size()),
			Modified: info.ModTime().Format("2006-01-02 15:04"),
			Active:   name == activeWorld,
		})
	}

	return options, nil
}

func listModConfigOptions(baseDir string) ([]configOption, error) {
	paths := map[string]struct{}{}
	modConfigDir := filepath.Join(baseDir, "ModConfigs")

	if entries, err := os.ReadDir(modConfigDir); err == nil {
		for _, entry := range entries {
			if entry.IsDir() {
				continue
			}
			paths[filepath.Join(modConfigDir, entry.Name())] = struct{}{}
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}

	excludedDirs := map[string]struct{}{
		"Backups":    {},
		"Engine":     {},
		"Logs":       {},
		"Mods":       {},
		"Scripts":    {},
		"Worlds":     {},
		"ModConfigs": {},
	}
	extensions := []string{".json", ".toml", ".cfg", ".ini"}

	baseEntries, err := os.ReadDir(baseDir)
	if err != nil {
		return nil, err
	}
	for _, entry := range baseEntries {
		if !entry.IsDir() {
			continue
		}
		if _, skip := excludedDirs[entry.Name()]; skip {
			continue
		}

		subdir := filepath.Join(baseDir, entry.Name())
		subEntries, err := os.ReadDir(subdir)
		if err != nil {
			continue
		}
		for _, subEntry := range subEntries {
			if subEntry.IsDir() {
				continue
			}
			ext := strings.ToLower(filepath.Ext(subEntry.Name()))
			if !containsString(extensions, ext) {
				continue
			}
			paths[filepath.Join(subdir, subEntry.Name())] = struct{}{}
		}
	}

	sortedPaths := make([]string, 0, len(paths))
	for path := range paths {
		sortedPaths = append(sortedPaths, path)
	}
	sort.Strings(sortedPaths)

	options := make([]configOption, 0, len(sortedPaths))
	for _, path := range sortedPaths {
		info, err := os.Stat(path)
		if err != nil || info.IsDir() {
			continue
		}
		relPath, err := filepath.Rel(baseDir, path)
		if err != nil {
			relPath = path
		}
		options = append(options, configOption{
			RelPath:  filepath.ToSlash(relPath),
			Path:     path,
			Size:     humanSize(info.Size()),
			Modified: info.ModTime().Format("2006-01-02 15:04"),
		})
	}

	return options, nil
}

func listInstalledModOptions(baseDir string) ([]modOption, error) {
	modPaths, err := filepath.Glob(filepath.Join(baseDir, "Mods", "*.tmod"))
	if err != nil {
		return nil, err
	}
	sort.Strings(modPaths)

	enabledMods, err := readEnabledModNames(filepath.Join(baseDir, "Mods", "enabled.json"))
	if err != nil {
		return nil, err
	}

	options := make([]modOption, 0, len(modPaths))
	for _, path := range modPaths {
		name := strings.TrimSuffix(filepath.Base(path), ".tmod")
		enabled := enabledMods[strings.ToLower(name)]
		options = append(options, modOption{
			Name:            name,
			Enabled:         enabled,
			OriginalEnabled: enabled,
		})
	}

	return options, nil
}

func loadAddonActions(baseDir string) ([]action, []string) {
	pattern := filepath.Join(baseDir, "Addons", "*", "addon.json")
	manifestPaths, err := filepath.Glob(pattern)
	if err != nil {
		return nil, []string{fmt.Sprintf("Unable to scan addon manifests: %v", err)}
	}
	sort.Strings(manifestPaths)

	actions := []action{}
	warnings := []string{}
	for _, manifestPath := range manifestPaths {
		addonDir := filepath.Dir(manifestPath)

		raw, err := os.ReadFile(manifestPath)
		if err != nil {
			warnings = append(warnings, fmt.Sprintf("Skipping addon manifest %s: %v", manifestPath, err))
			continue
		}

		var manifest addonManifest
		if err := json.Unmarshal(raw, &manifest); err != nil {
			warnings = append(warnings, fmt.Sprintf("Skipping addon manifest %s: %v", manifestPath, err))
			continue
		}

		for index, item := range manifest.Actions {
			section := strings.TrimSpace(item.Section)
			if section == "" {
				section = strings.TrimSpace(manifest.Section)
			}
			title := strings.TrimSpace(item.Title)
			if section == "" || title == "" || len(item.Command) == 0 {
				warnings = append(warnings, fmt.Sprintf("Skipping action %d in %s: section, title, and command are required", index+1, manifestPath))
				continue
			}

			command := make([]string, 0, len(item.Command))
			for _, part := range item.Command {
				command = append(command, expandAddonString(part, baseDir, addonDir))
			}

			workDir := strings.TrimSpace(item.WorkingDir)
			if workDir == "" {
				workDir = addonDir
			} else {
				workDir = expandAddonString(workDir, baseDir, addonDir)
				if !filepath.IsAbs(workDir) {
					workDir = filepath.Join(addonDir, workDir)
				}
			}

			actions = append(actions, action{
				category:      section,
				title:         section + " / " + title,
				description:   blankFallback(strings.TrimSpace(item.Description), "Run addon action."),
				command:       command,
				workDir:       workDir,
				addonName:     blankFallback(strings.TrimSpace(manifest.Name), filepath.Base(addonDir)),
				addonManifest: manifestPath,
				confirmText:   strings.TrimSpace(item.ConfirmText),
			})
		}
	}

	return actions, warnings
}

func expandAddonString(value, baseDir, addonDir string) string {
	replacer := strings.NewReplacer(
		"${repo_dir}", baseDir,
		"${addon_dir}", addonDir,
	)
	return replacer.Replace(value)
}

func readEnabledModNames(path string) (map[string]bool, error) {
	enabled := map[string]bool{}

	data, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return enabled, nil
		}
		return nil, err
	}

	var names []string
	if err := json.Unmarshal(data, &names); err == nil {
		for _, name := range names {
			name = strings.TrimSpace(name)
			if name == "" {
				continue
			}
			enabled[strings.ToLower(name)] = true
		}
		return enabled, nil
	}

	scanner := bufio.NewScanner(bytes.NewReader(data))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		line = strings.Trim(line, "[],")
		line = strings.Trim(line, "\"")
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		enabled[strings.ToLower(line)] = true
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}

	return enabled, nil
}

func saveInstalledModOptions(baseDir string, mods []modOption) (enabledCount, changedCount int, err error) {
	enabledJSON := filepath.Join(baseDir, "Mods", "enabled.json")
	if err := os.MkdirAll(filepath.Dir(enabledJSON), 0o755); err != nil {
		return 0, 0, err
	}

	names := make([]string, 0, len(mods))
	for _, mod := range mods {
		if mod.Enabled {
			names = append(names, mod.Name)
			enabledCount++
		}
		if mod.Enabled != mod.OriginalEnabled {
			changedCount++
		}
	}
	sort.Strings(names)

	if current, readErr := os.ReadFile(enabledJSON); readErr == nil {
		if writeErr := os.WriteFile(enabledJSON+".bak", current, 0o644); writeErr != nil {
			return 0, 0, writeErr
		}
	} else if !errors.Is(readErr, os.ErrNotExist) {
		return 0, 0, readErr
	}

	data, err := json.Marshal(names)
	if err != nil {
		return 0, 0, err
	}

	tmpPath := enabledJSON + ".tmp"
	if err := os.WriteFile(tmpPath, append(data, '\n'), 0o644); err != nil {
		return 0, 0, err
	}
	if err := os.Rename(tmpPath, enabledJSON); err != nil {
		return 0, 0, err
	}

	appendWorkshopLog(baseDir, fmt.Sprintf("Saved enabled.json (%d mods)", enabledCount))
	return enabledCount, changedCount, nil
}

func appendWorkshopLog(baseDir, message string) {
	appendNamedLog(baseDir, "workshop.log", "INFO", message)
}

func appendControlLog(baseDir, message, level string) {
	appendNamedLog(baseDir, "control.log", level, message)
}

func appendNamedLog(baseDir, filename, level, message string) {
	logPath := filepath.Join(baseDir, "Logs", filename)
	if err := os.MkdirAll(filepath.Dir(logPath), 0o755); err != nil {
		return
	}

	f, err := os.OpenFile(logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return
	}
	defer f.Close()

	timestamp := time.Now().Format("2006-01-02 15:04:05")
	if strings.TrimSpace(level) == "" {
		level = "INFO"
	}
	_, _ = fmt.Fprintf(f, "[%s] [%s] %s\n", timestamp, level, message)
}

func parseKeyValues(raw []byte) map[string]string {
	values := map[string]string{}
	scanner := bufio.NewScanner(bytes.NewReader(raw))
	for scanner.Scan() {
		line := scanner.Text()
		key, value, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		values[strings.TrimSpace(key)] = strings.TrimSpace(value)
	}
	return values
}

func readTailLines(path string, limit int) ([]string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, nil
		}
		return nil, err
	}

	lines := strings.Split(strings.ReplaceAll(string(data), "\r\n", "\n"), "\n")
	clean := make([]string, 0, len(lines))
	for _, line := range lines {
		line = cleanOutputLine(line)
		if strings.TrimSpace(line) == "" {
			continue
		}
		clean = append(clean, line)
	}
	if len(clean) == 0 {
		return []string{"Log file is empty."}, nil
	}
	return tailLines(clean, limit), nil
}

func readServerConfigValue(path, key string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	lines := strings.Split(string(data), "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if !strings.HasPrefix(line, key+"=") {
			continue
		}
		value := strings.TrimPrefix(line, key+"=")
		if idx := strings.Index(value, "#"); idx >= 0 {
			value = value[:idx]
		}
		return strings.TrimSpace(value)
	}
	return ""
}

func scanConsoleLines(data []byte, atEOF bool) (advance int, token []byte, err error) {
	for i, b := range data {
		if b == '\n' || b == '\r' {
			return i + 1, data[:i], nil
		}
	}
	if atEOF && len(data) > 0 {
		return len(data), data, nil
	}
	return 0, nil, nil
}

func cleanOutputLine(line string) string {
	line = ansiEscapePattern.ReplaceAllString(line, "")
	line = outputGlyphReplacer.Replace(line)
	line = strings.ReplaceAll(line, "\r", "")
	line = normalizeDecorativeLine(line)
	line = strings.TrimSpace(line)
	return line
}

func normalizeDecorativeLine(line string) string {
	trimmed := strings.TrimSpace(line)
	if trimmed == "" {
		return line
	}
	if !decorativeLinePattern.MatchString(trimmed) {
		return line
	}

	width := len([]rune(trimmed))
	if width < 6 {
		return line
	}
	if width > 62 {
		width = 62
	}
	return strings.Repeat("-", width)
}

func humanSize(size int64) string {
	units := []string{"B", "KB", "MB", "GB", "TB"}
	value := float64(size)
	unit := 0
	for value >= 1024 && unit < len(units)-1 {
		value /= 1024
		unit++
	}
	if unit == 0 {
		return fmt.Sprintf("%d%s", size, units[unit])
	}
	return fmt.Sprintf("%.1f%s", value, units[unit])
}

func tailLines(lines []string, limit int) []string {
	if limit <= 0 || len(lines) <= limit {
		return append([]string(nil), lines...)
	}
	return append([]string(nil), lines[len(lines)-limit:]...)
}

func blankFallback(value, fallback string) string {
	if strings.TrimSpace(value) == "" {
		return fallback
	}
	return value
}

func containsString(values []string, want string) bool {
	for _, value := range values {
		if value == want {
			return true
		}
	}
	return false
}

func formatPercent(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" || raw == "not_running" || strings.EqualFold(raw, "n/a") || strings.EqualFold(raw, "unknown") {
		return "n/a"
	}
	raw = strings.TrimSuffix(raw, "%")
	if !numericValuePattern.MatchString(raw) {
		return "n/a"
	}
	return raw + "%"
}

func formatUptimeDuration(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" || strings.EqualFold(raw, "n/a") || strings.EqualFold(raw, "unknown") {
		return "n/a"
	}
	if !wholeNumberPattern.MatchString(raw) {
		return "n/a"
	}
	seconds := atoi(raw)
	if seconds <= 0 {
		return "0s"
	}
	if seconds < 60 {
		return fmt.Sprintf("%ds", seconds)
	}
	minutes := seconds / 60
	if minutes < 60 {
		return fmt.Sprintf("%dm %02ds", minutes, seconds%60)
	}
	hours := minutes / 60
	return fmt.Sprintf("%dh %02dm", hours, minutes%60)
}

func formatTemperature(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" || strings.EqualFold(raw, "n/a") || strings.EqualFold(raw, "unknown") {
		return "n/a"
	}
	raw = strings.TrimSuffix(strings.TrimSuffix(raw, "°C"), "C")
	if !signedNumericValuePattern.MatchString(raw) {
		return "n/a"
	}
	if strings.Contains(raw, ".") {
		raw = strings.TrimRight(strings.TrimRight(raw, "0"), ".")
	}
	return raw + "C"
}

func formatMemoryRSS(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" || strings.EqualFold(raw, "n/a") || strings.EqualFold(raw, "unknown") {
		return "n/a"
	}
	if !wholeNumberPattern.MatchString(raw) {
		return "n/a"
	}
	kb, err := strconv.ParseInt(raw, 10, 64)
	if err != nil || kb < 0 {
		return "n/a"
	}
	if kb == 0 {
		return "0MB"
	}
	bytes := kb * 1024
	const (
		mb = 1024 * 1024
		gb = 1024 * 1024 * 1024
	)
	if bytes >= gb {
		return fmt.Sprintf("%.1fGB", float64(bytes)/float64(gb))
	}
	return fmt.Sprintf("%.0fMB", float64(bytes)/float64(mb))
}

func formatTemperatureLabel(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return "Temp"
	}
	switch strings.ToLower(raw) {
	case "cpu":
		return "CPU"
	case "gpu":
		return "GPU"
	case "ram":
		return "RAM"
	case "nvme":
		return "NVMe"
	case "board":
		return "Board"
	default:
		return raw
	}
}

func computeDiskBusy(baseDir, deviceRaw, ioMillisRaw string, now time.Time) string {
	device := strings.TrimSpace(deviceRaw)
	ioMillisRaw = strings.TrimSpace(ioMillisRaw)
	if device == "" || !wholeNumberPattern.MatchString(ioMillisRaw) {
		return "n/a"
	}

	ioMillis, err := strconv.ParseInt(ioMillisRaw, 10, 64)
	if err != nil || ioMillis < 0 {
		return "n/a"
	}

	key := baseDir + "|" + device

	diskBusyMu.Lock()
	defer diskBusyMu.Unlock()

	previous, ok := diskBusySamples[key]
	diskBusySamples[key] = diskBusySample{ioMillis: ioMillis, at: now}
	if !ok {
		return "0%"
	}
	if ioMillis < previous.ioMillis {
		return "0%"
	}

	elapsedMillis := now.Sub(previous.at).Milliseconds()
	if elapsedMillis <= 0 {
		return "0%"
	}

	busy := float64(ioMillis-previous.ioMillis) / float64(elapsedMillis) * 100
	if busy < 0 {
		busy = 0
	}
	if busy > 100 {
		busy = 100
	}
	return fmt.Sprintf("%.0f%%", busy)
}

func sanitizePID(raw string) string {
	raw = strings.TrimSpace(raw)
	if !wholeNumberPattern.MatchString(raw) {
		return ""
	}
	return raw
}

func atoi(raw string) int {
	var value int
	fmt.Sscanf(strings.TrimSpace(raw), "%d", &value)
	return value
}

func clamp(value, minimum, maximum int) int {
	if value < minimum {
		return minimum
	}
	if value > maximum {
		return maximum
	}
	return value
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func fitLine(line string, width int) string {
	if width <= 0 {
		return line
	}
	runes := []rune(line)
	if len(runes) <= width {
		return line
	}
	if width <= 1 {
		return string(runes[:width])
	}
	return string(runes[:width-1]) + "…"
}
