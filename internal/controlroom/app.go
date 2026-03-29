package controlroom

import (
	"fmt"
	"path/filepath"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type actionKind int

const (
	actionRunCommand actionKind = iota
	actionSelectWorld
	actionEditModConfig
	actionAddWorkshopMod
	actionManageInstalledMods
)

type outputMode int

const (
	outputModeLogs outputMode = iota
	outputModeCommand
)

type uiMode int

const (
	uiModeNormal uiMode = iota
	uiModeConfirm
	uiModeWorldPicker
	uiModeConfigPicker
	uiModeWorkshopInput
	uiModeModPicker
)

const overviewCategory = "Overview"
const panelVerticalChrome = 2
const panelHorizontalChrome = 3
const panelHorizontalPadding = 2
const actionPanelTotalWidth = 36
const statusPanelMaxTotalWidth = 48
const minAppWidth = actionPanelTotalWidth + 44
const minAppHeight = 20

type action struct {
	category         string
	title            string
	description      string
	command          []string
	workDir          string
	addonName        string
	addonManifest    string
	kind             actionKind
	confirmText      string
	startAfterSelect bool
}

type statusMsg struct {
	status appStatus
	err    error
}

type logMsg struct {
	source string
	lines  []string
	err    error
}

type worldListMsg struct {
	worlds     []worldOption
	startAfter bool
	err        error
}

type worldSetMsg struct {
	world      string
	startAfter bool
	err        error
}

type configListMsg struct {
	configs []configOption
	err     error
}

type configEditDoneMsg struct {
	config configOption
	err    error
}

type modListMsg struct {
	mods []modOption
	err  error
}

type modSaveMsg struct {
	enabledCount int
	changedCount int
	err          error
}

type outputLineMsg struct {
	text string
}

type commandDoneMsg struct {
	act      action
	label    string
	duration time.Duration
	err      error
}

type spinnerMsg time.Time
type statusTickMsg time.Time
type logTickMsg time.Time

type model struct {
	baseDir string
	program *tea.Program

	width  int
	height int
	ready  bool

	actions       []action
	categories    []string
	categoryIndex int
	cursor        int

	status        appStatus
	statusError   string
	addonWarnings []string
	lastRefresh   time.Time

	logSources      []logSource
	logSourceIndex  int
	logLines        []string
	logXOffset      int
	outputLines     []string
	commandXOffset  int
	outputMode      outputMode
	activeAction    string
	activeSince     time.Time
	running         bool
	spinnerIndex    int
	footer          string
	footerTimestamp time.Time

	uiMode        uiMode
	pendingAction action
	worldOptions  []worldOption
	worldCursor   int
	configOptions []configOption
	configCursor  int
	workshopInput string
	modOptions    []modOption
	modCursor     int
}

type outputView struct {
	title      string
	subtitle   string
	lines      []string
	emptyState string
	indicator  string
	offset     int
	maxOffset  int
}

type hotkeyHint struct {
	key    string
	desc   string
	active bool
}

func Run(baseDir string) error {
	m := newModel(baseDir)
	p := tea.NewProgram(m, tea.WithAltScreen(), tea.WithMouseAllMotion())
	m.program = p
	_, err := p.Run()
	return err
}

func newModel(baseDir string) *model {
	actions := defaultActions()
	addonActions, addonWarnings := loadAddonActions(baseDir)
	actions = append(actions, addonActions...)

	for _, warning := range addonWarnings {
		appendControlLog(baseDir, warning, "WARN")
	}

	var initialOutput []string
	if len(addonWarnings) > 0 {
		initialOutput = []string{
			fmt.Sprintf("[warn] %d addon load warning(s) detected during startup.", len(addonWarnings)),
			"Addons with invalid manifests were skipped.",
			"",
		}
		for _, warning := range addonWarnings {
			initialOutput = append(initialOutput, "[warn] "+warning)
		}
		initialOutput = append(initialOutput, "", "Review Logs/control.log for the same warnings later.")
	}

	return &model{
		baseDir:        baseDir,
		actions:        actions,
		categories:     categoriesForActions(actions),
		logSources:     defaultLogSources(baseDir),
		outputMode:     outputModeLogs,
		addonWarnings:  addonWarnings,
		footer:         "↑/↓ move • Enter open/run • Esc back • wheel scrolls 1 item • q quit • Ctrl+C force quit",
		outputLines:    initialOutput,
		categoryIndex:  0,
		cursor:         0,
		logSourceIndex: 0,
	}
}

func (m *model) footerActive() bool {
	return m.footer != "" && time.Now().Before(m.footerTimestamp)
}

func (m *model) minimumSizeOK() bool {
	return m.width >= minAppWidth && m.height >= minAppHeight
}

func joinHeaderBits(bits []string) string {
	filtered := make([]string, 0, len(bits))
	for _, bit := range bits {
		if strings.TrimSpace(bit) != "" {
			filtered = append(filtered, bit)
		}
	}
	if len(filtered) == 0 {
		return ""
	}
	if len(filtered) == 1 {
		return filtered[0]
	}

	joined := filtered[0]
	for _, bit := range filtered[1:] {
		joined = lipgloss.JoinHorizontal(lipgloss.Left, joined, headerSeparatorStyle.Render(" • "), bit)
	}
	return joined
}

func (m *model) headerStatusBits() []string {
	bits := []string{}
	if m.running {
		bits = append(bits, runningStyle.Render(spinnerFrames[m.spinnerIndex]+" "+m.activeAction))
	}
	if len(m.addonWarnings) > 0 {
		bits = append(bits, infoStyle.Render(fmt.Sprintf("addon warnings: %d (Tab for details)", len(m.addonWarnings))))
	}
	return bits
}

func (m *model) Init() tea.Cmd {
	return tea.Batch(
		refreshStatusCmd(m.baseDir),
		refreshLogCmd(m.currentLogSource()),
		statusTickCmd(),
		logTickCmd(),
		spinnerTickCmd(),
	)
}

func (m *model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.ready = true
		return m, tea.ClearScreen

	case tea.MouseMsg:
		if m.ready && !m.minimumSizeOK() {
			return m, nil
		}
		switch m.uiMode {
		case uiModeConfirm:
			return m, nil
		case uiModeWorldPicker:
			return m.handleWorldPickerMouse(msg)
		case uiModeConfigPicker:
			return m.handleConfigPickerMouse(msg)
		case uiModeWorkshopInput:
			return m.handleWorkshopInputMouse(msg)
		case uiModeModPicker:
			return m.handleModPickerMouse(msg)
		default:
			return m.handleNormalMouse(msg)
		}

	case tea.KeyMsg:
		if m.ready && !m.minimumSizeOK() {
			return m.handleSmallWindowKeys(msg)
		}
		switch m.uiMode {
		case uiModeConfirm:
			return m.handleConfirmKeys(msg)
		case uiModeWorldPicker:
			return m.handleWorldPickerKeys(msg)
		case uiModeConfigPicker:
			return m.handleConfigPickerKeys(msg)
		case uiModeWorkshopInput:
			return m.handleWorkshopInputKeys(msg)
		case uiModeModPicker:
			return m.handleModPickerKeys(msg)
		default:
			return m.handleNormalKeys(msg)
		}

	case statusMsg:
		if msg.err != nil {
			m.statusError = msg.err.Error()
		} else {
			m.status = msg.status
			m.statusError = ""
			m.lastRefresh = time.Now()
		}
		return m, nil

	case logMsg:
		if msg.err != nil {
			m.logLines = []string{"Unable to read log: " + msg.err.Error()}
		} else {
			m.logLines = msg.lines
		}
		return m, nil

	case worldListMsg:
		if msg.err != nil {
			m.setFooter("Unable to load worlds: "+msg.err.Error(), 4*time.Second)
			return m, nil
		}
		m.worldOptions = msg.worlds
		m.worldCursor = 0
		m.pendingAction = action{startAfterSelect: msg.startAfter}
		if len(msg.worlds) == 0 {
			m.setFooter("No worlds found in Worlds/.", 4*time.Second)
			return m, nil
		}
		m.uiMode = uiModeWorldPicker
		m.outputMode = outputModeCommand
		m.commandXOffset = 0
		m.outputLines = []string{"Select an active world and press Enter to apply it."}
		m.setFooter("World picker opened. Enter to select, Esc to cancel.", 4*time.Second)
		return m, nil

	case worldSetMsg:
		m.running = false
		m.activeAction = ""
		m.activeSince = time.Time{}
		if msg.err != nil {
			m.appendOutput("✗ Failed to set active world: " + msg.err.Error())
			m.setFooter("Failed to set active world: "+msg.err.Error(), 4*time.Second)
			return m, nil
		}
		m.uiMode = uiModeNormal
		m.worldOptions = nil
		m.worldCursor = 0
		m.appendOutput(fmt.Sprintf("✓ Active world set to %s", msg.world))
		m.outputMode = outputModeCommand
		m.setFooter("Active world updated to "+msg.world+".", 4*time.Second)
		if msg.startAfter {
			act := action{
				category:    "Server",
				title:       "Start Server",
				description: "Start the server after world selection.",
				command:     []string{"bash", "Scripts/hub/tmod-control.sh", "start"},
			}
			m.startAction(act)
			return m, nil
		}
		return m, refreshStatusCmd(m.baseDir)

	case configListMsg:
		if msg.err != nil {
			m.configOptions = nil
			m.configCursor = 0
			m.setFooter("Unable to load mod configs: "+msg.err.Error(), 4*time.Second)
			return m, nil
		}
		m.configOptions = msg.configs
		m.configCursor = 0
		if len(msg.configs) == 0 {
			m.outputMode = outputModeCommand
			m.outputLines = []string{"No mod config files were found under ModConfigs/ or other repo-local config directories."}
			m.setFooter("No mod config files found.", 4*time.Second)
			return m, nil
		}
		m.uiMode = uiModeConfigPicker
		m.outputMode = outputModeCommand
		m.commandXOffset = 0
		m.outputLines = []string{"Select a config file and press Enter to open it in your terminal editor."}
		m.setFooter("Mod config picker opened. Enter to edit, Esc to cancel.", 4*time.Second)
		return m, nil

	case configEditDoneMsg:
		m.running = false
		m.activeAction = ""
		m.activeSince = time.Time{}
		if msg.err != nil {
			m.appendOutput("✗ Failed to edit config: " + msg.err.Error())
			m.setFooter("Failed to open editor for "+msg.config.RelPath+".", 4*time.Second)
			return m, nil
		}
		m.appendOutput(fmt.Sprintf("✓ Finished editing %s", msg.config.RelPath))
		m.setFooter("Finished editing "+msg.config.RelPath+".", 4*time.Second)
		return m, nil

	case modListMsg:
		if msg.err != nil {
			m.modOptions = nil
			m.modCursor = 0
			m.setFooter("Unable to load installed mods: "+msg.err.Error(), 4*time.Second)
			return m, nil
		}
		m.modOptions = msg.mods
		m.modCursor = 0
		if len(msg.mods) == 0 {
			m.outputMode = outputModeCommand
			m.outputLines = []string{"No installed .tmod files were found under Mods/. Run Workshop / Sync Mods first."}
			m.setFooter("No installed mods found.", 4*time.Second)
			return m, nil
		}
		m.uiMode = uiModeModPicker
		m.outputMode = outputModeCommand
		m.commandXOffset = 0
		m.outputLines = []string{"Toggle installed mods, then press S to save the load list."}
		m.setFooter("Mod load manager opened. Enter toggles, S saves, Esc cancels.", 4*time.Second)
		return m, nil

	case modSaveMsg:
		m.running = false
		m.activeAction = ""
		m.activeSince = time.Time{}
		if msg.err != nil {
			m.appendOutput("✗ Failed to save mod load selection: " + msg.err.Error())
			m.setFooter("Failed to save enabled.json.", 4*time.Second)
			return m, nil
		}
		m.modOptions = nil
		m.modCursor = 0
		m.appendOutput(fmt.Sprintf("✓ Saved enabled.json with %d enabled mod(s)", msg.enabledCount))
		if msg.changedCount == 0 {
			m.setFooter("enabled.json was already up to date.", 4*time.Second)
		} else if m.status.Online {
			m.appendOutput("Info: Server is running; restart required for mod load changes to take effect.")
			m.setFooter("Saved mod load selection. Restart the server to apply it.", 4*time.Second)
		} else {
			m.setFooter("Saved mod load selection.", 4*time.Second)
		}
		return m, nil

	case outputLineMsg:
		m.appendOutput(msg.text)
		m.outputMode = outputModeCommand
		return m, nil

	case commandDoneMsg:
		m.running = false
		m.activeAction = ""
		m.activeSince = time.Time{}
		if msg.err != nil {
			if msg.act.isAddonAction() {
				m.appendOutput(fmt.Sprintf("✗ Addon action %s failed after %s: %v", msg.label, msg.duration.Round(time.Second), msg.err))
				m.appendAddonFailureDetails(msg.act, msg.err)
			} else {
				m.appendOutput(fmt.Sprintf("✗ %s failed after %s: %v", msg.label, msg.duration.Round(time.Second), msg.err))
			}
			m.setFooter(msg.label+" failed.", 4*time.Second)
		} else {
			m.appendOutput(fmt.Sprintf("✓ %s finished in %s", msg.label, msg.duration.Round(time.Second)))
			m.setFooter(msg.label+" finished successfully.", 4*time.Second)
		}
		return m, tea.Batch(
			refreshStatusCmd(m.baseDir),
			refreshLogCmd(m.currentLogSource()),
		)

	case spinnerMsg:
		if m.running {
			m.spinnerIndex = (m.spinnerIndex + 1) % len(spinnerFrames)
		}
		return m, spinnerTickCmd()

	case statusTickMsg:
		return m, tea.Batch(statusTickCmd(), refreshStatusCmd(m.baseDir))

	case logTickMsg:
		if m.outputMode == outputModeLogs && m.uiMode == uiModeNormal {
			return m, tea.Batch(logTickCmd(), refreshLogCmd(m.currentLogSource()))
		}
		return m, logTickCmd()
	}

	return m, nil
}

func (m *model) handleNormalKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "ctrl+c":
		return m, tea.Quit
	case "q":
		if m.running {
			m.setFooter("A command is still running. Wait for it to finish or press Ctrl+C to force quit.", 4*time.Second)
			return m, nil
		}
		return m, tea.Quit
	case "up", "k":
		m.moveCursor(-1)
		return m, nil
	case "down", "j":
		m.moveCursor(1)
		return m, nil
	case "shift+left":
		m.shiftOutputScroll(-6)
		return m, nil
	case "shift+right":
		m.shiftOutputScroll(6)
		return m, nil
	case "left", "esc", "backspace":
		if m.currentCategory() != overviewCategory {
			m.categoryIndex = 0
			m.cursor = 0
			m.setFooter("Returned to section overview.", 2*time.Second)
		}
		return m, nil
	case "enter":
		return m, m.activateCurrentSelection()
	case "r":
		m.setFooter("Refreshing status and current log…", 2*time.Second)
		return m, tea.Batch(refreshStatusCmd(m.baseDir), refreshLogCmd(m.currentLogSource()))
	case "l":
		if m.outputMode != outputModeLogs {
			return m, nil
		}
		m.logSourceIndex = (m.logSourceIndex + 1) % len(m.logSources)
		m.logXOffset = 0
		m.setFooter("Switched log source to "+m.currentLogSource().label+".", 2*time.Second)
		return m, refreshLogCmd(m.currentLogSource())
	case "tab":
		if m.outputMode == outputModeLogs {
			m.outputMode = outputModeCommand
			m.setFooter("Showing command output.", 2*time.Second)
		} else {
			m.outputMode = outputModeLogs
			m.setFooter("Showing "+m.currentLogSource().label+".", 2*time.Second)
			return m, refreshLogCmd(m.currentLogSource())
		}
		return m, nil
	}

	return m, nil
}

func (m *model) handleSmallWindowKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "ctrl+c", "q":
		return m, tea.Quit
	default:
		return m, nil
	}
}

func (m *model) handleNormalMouse(msg tea.MouseMsg) (tea.Model, tea.Cmd) {
	if m.mouseOverActionPanel(msg.X, msg.Y) {
		if msg.Action == tea.MouseActionMotion && msg.Button == tea.MouseButtonNone {
			index, ok := m.actionPanelListIndexAt(msg.Y)
			if ok {
				m.cursor = index
			}
			return m, nil
		}
		if msg.Action != tea.MouseActionPress {
			return m, nil
		}
		switch msg.Button {
		case tea.MouseButtonWheelUp:
			m.moveCursor(-1)
		case tea.MouseButtonWheelDown:
			m.moveCursor(1)
		case tea.MouseButtonLeft:
			index, ok := m.actionPanelListIndexAt(msg.Y)
			if !ok {
				return m, nil
			}
			m.cursor = index
			return m, m.activateCurrentSelection()
		}
		return m, nil
	}
	if !m.mouseOverOutputPanel(msg.X, msg.Y) {
		return m, nil
	}
	if msg.Action != tea.MouseActionPress {
		return m, nil
	}

	return m, nil
}

func (m *model) handleConfirmKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "ctrl+c":
		return m, tea.Quit
	case "q", "esc", "n":
		m.uiMode = uiModeNormal
		m.pendingAction = action{}
		m.setFooter("Cancelled.", 2*time.Second)
		return m, nil
	case "enter", "y":
		act := m.pendingAction
		m.uiMode = uiModeNormal
		m.pendingAction = action{}
		return m, m.triggerAction(act)
	}

	return m, nil
}

func (m *model) handleWorldPickerKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "ctrl+c":
		return m, tea.Quit
	case "q", "esc":
		m.uiMode = uiModeNormal
		m.worldOptions = nil
		m.worldCursor = 0
		m.setFooter("World selection cancelled.", 2*time.Second)
		return m, nil
	case "up", "k":
		m.moveWorldCursor(-1)
		return m, nil
	case "down", "j":
		m.moveWorldCursor(1)
		return m, nil
	case "enter":
		return m, m.activateWorldSelection()
	}

	return m, nil
}

func (m *model) handleConfigPickerKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "ctrl+c":
		return m, tea.Quit
	case "q", "esc":
		m.uiMode = uiModeNormal
		m.configOptions = nil
		m.configCursor = 0
		m.setFooter("Mod config selection cancelled.", 2*time.Second)
		return m, nil
	case "up", "k":
		m.moveConfigCursor(-1)
		return m, nil
	case "down", "j":
		m.moveConfigCursor(1)
		return m, nil
	case "enter":
		return m, m.activateConfigSelection()
	}

	return m, nil
}

func (m *model) handleWorkshopInputKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "ctrl+c":
		return m, tea.Quit
	case "esc":
		m.uiMode = uiModeNormal
		m.workshopInput = ""
		m.setFooter("Workshop mod add cancelled.", 2*time.Second)
		return m, nil
	case "enter":
		input := strings.TrimSpace(m.workshopInput)
		if input == "" {
			m.setFooter("Enter a Workshop URL or numeric ID first.", 3*time.Second)
			return m, nil
		}
		m.uiMode = uiModeNormal
		m.workshopInput = ""
		act := action{
			category:    "Workshop",
			title:       "Workshop / Add Mod by URL or ID",
			description: "Add a Workshop URL or numeric ID to mod_ids.txt.",
			command:     []string{"bash", "Scripts/steam/tmod-workshop.sh", "mods", "add", "--yes", input},
		}
		m.startAction(act)
		return m, nil
	case "backspace", "ctrl+h":
		runes := []rune(m.workshopInput)
		if len(runes) > 0 {
			m.workshopInput = string(runes[:len(runes)-1])
		}
		return m, nil
	case "ctrl+u":
		m.workshopInput = ""
		return m, nil
	}

	if msg.Type == tea.KeyRunes && len(msg.Runes) > 0 {
		m.workshopInput += string(msg.Runes)
	}

	return m, nil
}

func (m *model) handleModPickerKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "ctrl+c":
		return m, tea.Quit
	case "q", "esc":
		m.uiMode = uiModeNormal
		m.modOptions = nil
		m.modCursor = 0
		m.setFooter("Mod load changes discarded.", 2*time.Second)
		return m, nil
	case "up", "k":
		m.moveModCursor(-1)
		return m, nil
	case "down", "j":
		m.moveModCursor(1)
		return m, nil
	case " ", "enter":
		m.toggleCurrentMod()
		return m, nil
	case "a":
		m.setAllModsEnabled(true)
		return m, nil
	case "n":
		m.setAllModsEnabled(false)
		return m, nil
	case "s":
		if len(m.modOptions) == 0 {
			return m, nil
		}
		m.uiMode = uiModeNormal
		m.running = true
		m.activeAction = "Save Mod Selection"
		m.activeSince = time.Now()
		m.outputMode = outputModeCommand
		m.outputLines = []string{
			"Saving mod load selection to Mods/enabled.json…",
			"",
		}
		m.setFooter("Saving mod load selection…", 3*time.Second)
		return m, saveModSelectionCmd(m.baseDir, m.modOptions)
	}

	return m, nil
}

func (m *model) handleWorldPickerMouse(msg tea.MouseMsg) (tea.Model, tea.Cmd) {
	if !m.mouseOverOutputPanel(msg.X, msg.Y) {
		return m, nil
	}
	if msg.Action == tea.MouseActionMotion && msg.Button == tea.MouseButtonNone {
		index, ok := m.worldPickerIndexAt(msg.Y)
		if ok {
			m.worldCursor = index
		}
		return m, nil
	}
	if msg.Action != tea.MouseActionPress {
		return m, nil
	}

	switch msg.Button {
	case tea.MouseButtonWheelUp:
		m.moveWorldCursor(-1)
	case tea.MouseButtonWheelDown:
		m.moveWorldCursor(1)
	case tea.MouseButtonLeft:
		index, ok := m.worldPickerIndexAt(msg.Y)
		if !ok {
			return m, nil
		}
		m.worldCursor = index
		return m, m.activateWorldSelection()
	}

	return m, nil
}

func (m *model) handleConfigPickerMouse(msg tea.MouseMsg) (tea.Model, tea.Cmd) {
	if !m.mouseOverOutputPanel(msg.X, msg.Y) {
		return m, nil
	}
	if msg.Action == tea.MouseActionMotion && msg.Button == tea.MouseButtonNone {
		index, ok := m.configPickerIndexAt(msg.Y)
		if ok {
			m.configCursor = index
		}
		return m, nil
	}
	if msg.Action != tea.MouseActionPress {
		return m, nil
	}

	switch msg.Button {
	case tea.MouseButtonWheelUp:
		m.moveConfigCursor(-1)
	case tea.MouseButtonWheelDown:
		m.moveConfigCursor(1)
	case tea.MouseButtonLeft:
		index, ok := m.configPickerIndexAt(msg.Y)
		if !ok {
			return m, nil
		}
		m.configCursor = index
		return m, m.activateConfigSelection()
	}

	return m, nil
}

func (m *model) handleWorkshopInputMouse(msg tea.MouseMsg) (tea.Model, tea.Cmd) {
	if msg.Action != tea.MouseActionPress {
		return m, nil
	}
	if !m.mouseOverOutputPanel(msg.X, msg.Y) {
		return m, nil
	}
	return m, nil
}

func (m *model) handleModPickerMouse(msg tea.MouseMsg) (tea.Model, tea.Cmd) {
	if !m.mouseOverOutputPanel(msg.X, msg.Y) {
		return m, nil
	}
	if msg.Action == tea.MouseActionMotion && msg.Button == tea.MouseButtonNone {
		index, ok := m.modPickerIndexAt(msg.Y)
		if ok {
			m.modCursor = index
		}
		return m, nil
	}
	if msg.Action != tea.MouseActionPress {
		return m, nil
	}

	switch msg.Button {
	case tea.MouseButtonWheelUp:
		m.moveModCursor(-1)
	case tea.MouseButtonWheelDown:
		m.moveModCursor(1)
	case tea.MouseButtonLeft:
		index, ok := m.modPickerIndexAt(msg.Y)
		if !ok {
			return m, nil
		}
		m.modCursor = index
		m.toggleCurrentMod()
	}

	return m, nil
}

func (m *model) activateCurrentSelection() tea.Cmd {
	if m.running {
		m.setFooter("A command is already running.", 2*time.Second)
		return nil
	}
	if m.currentCategory() == overviewCategory {
		category, ok := m.selectedCategoryEntry()
		if !ok {
			return nil
		}
		m.openCategory(category)
		return nil
	}
	act, ok := m.selectedAction()
	if !ok {
		return nil
	}
	return m.triggerAction(act)
}

func (m *model) activateWorldSelection() tea.Cmd {
	if len(m.worldOptions) == 0 {
		return nil
	}
	selected := m.worldOptions[m.worldCursor]
	m.uiMode = uiModeNormal
	m.running = true
	m.activeAction = "Set Active World"
	m.activeSince = time.Now()
	m.outputMode = outputModeCommand
	m.outputLines = []string{
		fmt.Sprintf("Applying active world: %s", selected.Name),
		"",
	}
	m.setFooter("Setting active world to "+selected.Name+"…", 3*time.Second)
	return setWorldCmd(m.baseDir, selected, m.pendingAction.startAfterSelect)
}

func (m *model) activateConfigSelection() tea.Cmd {
	if len(m.configOptions) == 0 {
		return nil
	}
	selected := m.configOptions[m.configCursor]
	m.uiMode = uiModeNormal
	m.configOptions = nil
	m.configCursor = 0
	m.running = true
	m.activeAction = "Edit Mod Config"
	m.activeSince = time.Now()
	m.outputMode = outputModeCommand
	m.outputLines = []string{
		fmt.Sprintf("Opening %s in your terminal editor…", selected.RelPath),
		"",
	}
	m.setFooter("Opening "+selected.RelPath+" in editor…", 3*time.Second)
	return editModConfigCmd(m.baseDir, selected)
}

func (m *model) triggerAction(act action) tea.Cmd {
	switch act.kind {
	case actionSelectWorld:
		return listWorldsCmd(m.baseDir, act.startAfterSelect)
	case actionEditModConfig:
		return listModConfigsCmd(m.baseDir)
	case actionAddWorkshopMod:
		m.uiMode = uiModeWorkshopInput
		m.workshopInput = ""
		m.outputMode = outputModeCommand
		m.commandXOffset = 0
		m.outputLines = []string{"Paste a Workshop URL or numeric ID, then press Enter to add it to mod_ids.txt."}
		m.setFooter("Workshop URL or ID entry opened. Enter adds, Esc cancels.", 4*time.Second)
		return nil
	case actionManageInstalledMods:
		return listInstalledModsCmd(m.baseDir)
	default:
		if act.confirmText != "" {
			m.uiMode = uiModeConfirm
			m.pendingAction = act
			m.outputMode = outputModeCommand
			return nil
		}
		m.startAction(act)
		return nil
	}
}

func (m *model) View() string {
	if !m.ready {
		return "Loading tModLoader control room…"
	}
	if !m.minimumSizeOK() {
		return m.renderMinimumSizeView()
	}

	header := m.renderHeader()
	body := lipgloss.JoinHorizontal(lipgloss.Top, m.renderActionPanel(), m.renderRightColumn())
	return lipgloss.JoinVertical(lipgloss.Left, header, body)
}

func (m *model) renderMinimumSizeView() string {
	lines := []string{
		sectionTitleStyle.Render("Window Too Small"),
		sectionMutedStyle.Render(fmt.Sprintf("Resize the terminal to at least %dx%d.", minAppWidth, minAppHeight)),
		sectionMutedStyle.Render(fmt.Sprintf("Current size: %dx%d", m.width, m.height)),
		"",
		sectionMutedStyle.Render("q or Ctrl+C quits."),
	}
	body := strings.Join(lines, "\n")
	return lipgloss.Place(max(1, m.width), max(1, m.height), lipgloss.Center, lipgloss.Center, body)
}

func (m *model) renderHeader() string {
	title := headerTitleStyle.Render("tmodloader-server")
	subtitle := headerSubtleStyle.Render("Persistent headless server console")

	stateText := "OFFLINE"
	stateStyle := stateOfflineStyle
	if m.status.Online {
		stateText = "ONLINE"
		stateStyle = stateOnlineStyle
	}

	statusBits := m.headerStatusBits()

	headerLine := lipgloss.JoinHorizontal(
		lipgloss.Left,
		stateStyle.Render(stateText),
		headerGapStyle.Render(" "),
		title,
		headerGapStyle.Render(" "),
		subtitle,
	)
	statusLine := joinHeaderBits(statusBits)

	lines := []string{headerLine}
	if statusLine != "" {
		lines = append(lines, statusLine)
	}
	if m.statusError != "" {
		lines = append(lines, errorStyle.Render("Status refresh: "+m.statusError))
	}

	return outerPanelStyle.Width(m.width).Render(lipgloss.JoinVertical(lipgloss.Left, lines...))
}

func (m *model) renderActionPanel() string {
	panelTotalWidth := actionPanelTotalWidth
	panelWidth := availablePanelContentWidth(panelTotalWidth)
	textWidth := panelInnerTextWidth(panelWidth)
	contentHeight := availablePanelContentHeight(m.bodyHeight())
	hotkeyRows := m.renderHotkeyLegend(textWidth)
	hotkeyFootprint := panelBlockFootprint(hotkeyRows)
	if m.currentCategory() == overviewCategory {
		return m.renderOverviewPanel(panelWidth, contentHeight, hotkeyRows, hotkeyFootprint)
	}

	lines := []string{
		m.renderCategoryTabs(textWidth),
		panelDivider(textWidth),
		sectionTitleStyle.Render(m.currentCategory()),
	}

	filtered := m.filteredActions()
	visibleSlots := max(1, contentHeight-5-hotkeyFootprint)
	start, end := visibleWindow(len(filtered), visibleSlots, m.cursor)

	if start > 0 {
		lines = append(lines, sectionMutedStyle.Render("  …"))
	}

	for i := start; i < end; i++ {
		act := filtered[i]
		prefix := "  "
		lineStyle := actionStyle

		if i == m.cursor {
			prefix = "▶ "
			lineStyle = selectedActionStyle
		}

		lines = append(lines, lineStyle.Render(fitLine(prefix+m.actionLabel(act), textWidth)))
	}

	if end < len(filtered) {
		lines = append(lines, sectionMutedStyle.Render("  …"))
	}

	lines = m.appendBottomPanelBlock(lines, hotkeyRows, contentHeight)
	lines = truncatePanelLines(lines, contentHeight)
	return panelStyle.Width(panelWidth).Height(contentHeight).Render(strings.Join(lines, "\n"))
}

func (m *model) renderOverviewPanel(panelWidth int, contentHeight int, hotkeyRows []string, hotkeyFootprint int) string {
	textWidth := panelInnerTextWidth(panelWidth)
	lines := []string{
		m.renderCategoryTabs(textWidth),
		panelDivider(textWidth),
		sectionTitleStyle.Render("Sections"),
	}

	entries := m.categoryEntries()
	nameWidth := m.overviewNameWidth()
	visibleSlots := max(1, contentHeight-5-hotkeyFootprint)
	start, end := visibleWindow(len(entries), visibleSlots, m.cursor)

	if start > 0 {
		lines = append(lines, sectionMutedStyle.Render("  …"))
	}

	for i := start; i < end; i++ {
		category := entries[i]
		prefix := "  "
		lineStyle := actionStyle
		if i == m.cursor {
			prefix = "▶ "
			lineStyle = selectedActionStyle
		}

		title := fmt.Sprintf("%s%-*s  (%2d actions)", prefix, nameWidth, category, m.categoryActionCount(category))
		lines = append(lines, lineStyle.Render(fitLine(title, textWidth)))
	}

	if end < len(entries) {
		lines = append(lines, sectionMutedStyle.Render("  …"))
	}

	lines = m.appendBottomPanelBlock(lines, hotkeyRows, contentHeight)
	lines = truncatePanelLines(lines, contentHeight)
	return panelStyle.Width(panelWidth).Height(contentHeight).Render(strings.Join(lines, "\n"))
}

func (m *model) renderCategoryTabs(width int) string {
	if width <= 0 {
		return ""
	}
	if m.currentCategory() == overviewCategory {
		return fitLine("Path: Overview", width)
	}
	return fitLine("Path: Overview / "+m.currentCategory(), width)
}

func (m *model) renderRightColumn() string {
	_, rightTotalWidth, statusTotalHeight, outputTotalHeight := m.rightColumnLayout()
	rightWidth := availablePanelContentWidth(rightTotalWidth)
	statusTotalWidth := min(rightTotalWidth, statusPanelMaxTotalWidth)
	statusWidth := availablePanelContentWidth(statusTotalWidth)

	statusContentHeight := availablePanelContentHeight(statusTotalHeight)
	outputContentHeight := availablePanelContentHeight(outputTotalHeight)

	statusPanel := panelStyle.Width(statusWidth).Height(statusContentHeight).Render(m.renderStatusPanel(panelInnerTextWidth(statusWidth), statusContentHeight))
	outputPanel := panelStyle.Width(rightWidth).Height(outputContentHeight).Render(m.renderOutputPanel(panelInnerTextWidth(rightWidth), outputContentHeight))

	return lipgloss.JoinVertical(lipgloss.Left, statusPanel, outputPanel)
}

func (m *model) renderHotkeyLegend(width int) []string {
	if width <= 0 {
		return nil
	}

	rows := []string{
		hotkeyTitleStyle.Render("Hotkeys"),
	}

	hints := m.hotkeyHints()
	if len(hints) == 0 {
		return rows
	}

	for _, hint := range hints {
		rows = append(rows, renderHotkeyCell(hint, width))
	}

	return rows
}

func renderHotkeyCell(hint hotkeyHint, width int) string {
	if width <= 0 {
		return ""
	}

	keyLabel := formatHotkeyLabel(hint.key)
	keyWidth := min(9, max(5, width/2))
	if keyWidth >= width {
		keyWidth = max(1, width-1)
	}
	descWidth := width - keyWidth - 1

	keyStyle := hotkeyInactiveKeyStyle
	descStyle := hotkeyInactiveDescStyle
	if hint.active {
		keyStyle = hotkeyActiveKeyStyle
		descStyle = hotkeyActiveDescStyle
	}

	if descWidth <= 0 {
		return keyStyle.Render(fitAndPadLine(keyLabel, width))
	}

	keyText := keyStyle.Render(fitAndPadLine(keyLabel, keyWidth))
	descText := descStyle.Render(fitLine(hint.desc, descWidth))
	padding := width - lipgloss.Width(keyText) - 1 - lipgloss.Width(descText)
	if padding < 0 {
		padding = 0
	}

	return keyText + " " + descText + strings.Repeat(" ", padding)
}

func renderWorkshopInputField(value string, width int) string {
	if width <= 0 {
		return ""
	}

	prompt := "> "
	cursor := "█"
	if strings.TrimSpace(value) == "" {
		return inputFieldStyle.Render(fitAndPadLine(prompt+cursor, width))
	}

	available := max(1, width-len([]rune(prompt))-len([]rune(cursor)))
	runes := []rune(value)
	if len(runes) > available {
		runes = runes[len(runes)-available:]
	}

	return inputFieldStyle.Render(fitAndPadLine(prompt+string(runes)+cursor, width))
}

func formatHotkeyLabel(label string) string {
	if len([]rune(label)) != 1 {
		return label
	}
	return strings.ToUpper(label)
}

func (m *model) hotkeyHints() []hotkeyHint {
	switch m.uiMode {
	case uiModeConfirm:
		return []hotkeyHint{
			{key: "Up/Down", desc: "move", active: false},
			{key: "Enter/y", desc: "confirm", active: true},
			{key: "Esc/n", desc: "cancel", active: true},
			{key: "Tab", desc: "swap view", active: false},
			{key: "l", desc: "next log", active: false},
			{key: "r", desc: "refresh", active: false},
			{key: "q", desc: "cancel", active: true},
			{key: "Ctrl+C", desc: "force quit", active: true},
		}
	case uiModeWorldPicker:
		return []hotkeyHint{
			{key: "Up/Down", desc: "move", active: true},
			{key: "Enter", desc: "set world", active: true},
			{key: "Esc", desc: "cancel", active: true},
			{key: "Tab", desc: "swap view", active: false},
			{key: "l", desc: "next log", active: false},
			{key: "r", desc: "refresh", active: false},
			{key: "q", desc: "cancel", active: true},
			{key: "Ctrl+C", desc: "force quit", active: true},
		}
	case uiModeConfigPicker:
		return []hotkeyHint{
			{key: "Up/Down", desc: "move", active: true},
			{key: "Enter", desc: "edit file", active: true},
			{key: "Esc", desc: "cancel", active: true},
			{key: "Tab", desc: "swap view", active: false},
			{key: "l", desc: "next log", active: false},
			{key: "r", desc: "refresh", active: false},
			{key: "q", desc: "cancel", active: true},
			{key: "Ctrl+C", desc: "force quit", active: true},
		}
	case uiModeWorkshopInput:
		return []hotkeyHint{
			{key: "Type", desc: "enter url/id", active: true},
			{key: "Enter", desc: "add mod", active: true},
			{key: "Backspace", desc: "erase", active: true},
			{key: "Ctrl+U", desc: "clear", active: true},
			{key: "Esc", desc: "cancel", active: true},
			{key: "Tab", desc: "swap view", active: false},
			{key: "l", desc: "next log", active: false},
			{key: "r", desc: "refresh", active: false},
			{key: "Ctrl+C", desc: "force quit", active: true},
		}
	case uiModeModPicker:
		return []hotkeyHint{
			{key: "Up/Down", desc: "move", active: true},
			{key: "Enter", desc: "toggle", active: true},
			{key: "A", desc: "enable all", active: true},
			{key: "N", desc: "disable all", active: true},
			{key: "S", desc: "save", active: true},
			{key: "Esc", desc: "cancel", active: true},
			{key: "Tab", desc: "swap view", active: false},
			{key: "l", desc: "next log", active: false},
			{key: "q", desc: "cancel", active: true},
			{key: "Ctrl+C", desc: "force quit", active: true},
		}
	default:
		if m.outputMode == outputModeLogs {
			return []hotkeyHint{
				{key: "Up/Down", desc: "move", active: true},
				{key: "Enter", desc: "open/run", active: true},
				{key: "Esc", desc: "back", active: true},
				{key: "Tab", desc: "command out", active: true},
				{key: "l", desc: "next log", active: true},
				{key: "r", desc: "refresh", active: true},
				{key: "q", desc: "quit", active: true},
				{key: "Ctrl+C", desc: "force quit", active: true},
			}
		}
		return []hotkeyHint{
			{key: "Up/Down", desc: "move", active: true},
			{key: "Enter", desc: "open/run", active: true},
			{key: "Esc", desc: "back", active: true},
			{key: "Tab", desc: "log tail", active: true},
			{key: "l", desc: "next log", active: false},
			{key: "r", desc: "refresh", active: true},
			{key: "q", desc: "quit", active: true},
			{key: "Ctrl+C", desc: "force quit", active: true},
		}
	}
}

func (m *model) renderStatusPanel(width, height int) string {
	rows := []string{}
	selectionRows := m.renderSelectionRows(width, height)
	if len(selectionRows) > 0 {
		rows = append(rows, normalizePanelBlock(selectionRows, m.selectionBlockHeight(height))...)
	}

	snapshotRows := m.renderSnapshotRows(width)
	if len(snapshotRows) > 0 {
		if len(rows) > 0 {
			rows = append(rows, panelDivider(width))
		}
		remainingHeight := height - len(rows)
		if remainingHeight > 0 {
			rows = append(rows, truncatePanelLines(snapshotRows, remainingHeight)...)
		}
	}

	rows = truncatePanelLines(rows, height)
	return strings.Join(rows, "\n")
}

func (m *model) renderOutputPanel(width, height int) string {
	switch m.uiMode {
	case uiModeConfirm:
		return m.renderConfirmPanel(width, height)
	case uiModeWorldPicker:
		return m.renderWorldPickerPanel(width, height)
	case uiModeConfigPicker:
		return m.renderConfigPickerPanel(width, height)
	case uiModeWorkshopInput:
		return m.renderWorkshopInputPanel(width, height)
	case uiModeModPicker:
		return m.renderModPickerPanel(width, height)
	}

	view := m.buildOutputView(width, height)
	bodyHeight := max(1, height-3)

	rendered := []string{
		outputHeaderTitleStyle.Width(width).Render(view.title),
	}
	rendered = append(rendered, outputHeaderMetaStyle.Width(width).Render(fitLine(view.subtitle, width)))
	if view.emptyState != "" {
		placeholder := lipgloss.Place(width, bodyHeight, lipgloss.Center, lipgloss.Center, outputPlaceholderStyle.Render(view.emptyState))
		rendered = append(rendered, placeholder)
		rendered = append(rendered, outputIndicatorStyle.Render(fitLine(view.indicator, width)))
		return strings.Join(rendered, "\n")
	}

	bodyLines := make([]string, 0, bodyHeight)
	for _, line := range truncatePanelLines(view.lines, bodyHeight) {
		bodyLines = append(bodyLines, outputBodyStyle.Width(width).Render(fitLine(line, width)))
	}
	for len(bodyLines) < bodyHeight {
		bodyLines = append(bodyLines, outputBodyStyle.Width(width).Render(""))
	}
	rendered = append(rendered, bodyLines...)
	rendered = append(rendered, outputIndicatorStyle.Render(fitLine(view.indicator, width)))
	return strings.Join(rendered, "\n")
}

func (m *model) renderConfirmPanel(width, height int) string {
	lines := []string{
		sectionTitleStyle.Render("Confirm Action"),
		errorStyle.Render(fitLine(m.pendingAction.title, width)),
		"",
		fitLine(blankFallback(m.pendingAction.confirmText, "Press Enter to continue or Esc to cancel."), width),
		"",
		sectionMutedStyle.Render("Enter or y to continue."),
		sectionMutedStyle.Render("Esc or n to cancel."),
	}
	lines = truncatePanelLines(lines, height)
	return strings.Join(lines, "\n")
}

func (m *model) renderWorldPickerPanel(width, height int) string {
	lines := []string{
		sectionTitleStyle.Render("World Picker"),
		sectionMutedStyle.Render("Select a world, then press Enter to make it active."),
	}

	if len(m.worldOptions) == 0 {
		lines = append(lines, "No worlds found.")
		return strings.Join(lines, "\n")
	}

	visibleSlots := max(1, height-6)
	start, end := visibleWindow(len(m.worldOptions), visibleSlots, m.worldCursor)
	if start > 0 {
		lines = append(lines, sectionMutedStyle.Render("  …"))
	}

	for i := start; i < end; i++ {
		world := m.worldOptions[i]
		prefix := "  "
		style := actionStyle
		if i == m.worldCursor {
			prefix = "▶ "
			style = selectedActionStyle
		}

		activeMarker := ""
		if world.Active {
			activeMarker = "  (active)"
		}
		lines = append(lines, style.Render(fitLine(prefix+world.Name+activeMarker, width)))
		lines = append(lines, actionDescStyle.Render(fitLine(fmt.Sprintf("  %s  %s", world.Size, world.Modified), width)))
	}

	if end < len(m.worldOptions) {
		lines = append(lines, sectionMutedStyle.Render("  …"))
	}

	lines = append(lines, "")
	lines = append(lines, sectionMutedStyle.Render("Esc cancels without changes."))
	lines = truncatePanelLines(lines, height)
	return strings.Join(lines, "\n")
}

func (m *model) renderConfigPickerPanel(width, height int) string {
	lines := []string{
		sectionTitleStyle.Render("Mod Config Picker"),
		sectionMutedStyle.Render("Select a config file, then press Enter to open it in your editor."),
	}

	if len(m.configOptions) == 0 {
		lines = append(lines, "No mod config files found.")
		return strings.Join(lines, "\n")
	}

	visibleSlots := max(1, height-6)
	start, end := visibleWindow(len(m.configOptions), visibleSlots, m.configCursor)
	if start > 0 {
		lines = append(lines, sectionMutedStyle.Render("  …"))
	}

	for i := start; i < end; i++ {
		config := m.configOptions[i]
		prefix := "  "
		style := actionStyle
		if i == m.configCursor {
			prefix = "▶ "
			style = selectedActionStyle
		}

		lines = append(lines, style.Render(fitLine(prefix+config.RelPath, width)))
		lines = append(lines, actionDescStyle.Render(fitLine(fmt.Sprintf("  %s  %s", config.Size, config.Modified), width)))
	}

	if end < len(m.configOptions) {
		lines = append(lines, sectionMutedStyle.Render("  …"))
	}

	lines = append(lines, "")
	lines = append(lines, sectionMutedStyle.Render("Esc cancels without opening a file."))
	lines = truncatePanelLines(lines, height)
	return strings.Join(lines, "\n")
}

func (m *model) renderWorkshopInputPanel(width, height int) string {
	lines := []string{
		sectionTitleStyle.Render("Add Workshop Mod"),
		sectionMutedStyle.Render("Paste a Steam Workshop URL or numeric ID, then press Enter to add it to mod_ids.txt."),
		"",
		renderWorkshopInputField(m.workshopInput, width),
		"",
		sectionMutedStyle.Render("Examples:"),
		sectionMutedStyle.Render(fitLine("  2824688804", width)),
		sectionMutedStyle.Render(fitLine("  https://steamcommunity.com/sharedfiles/filedetails/?id=2824688804", width)),
		"",
		sectionMutedStyle.Render("Esc cancels without changes."),
	}
	lines = truncatePanelLines(lines, height)
	return strings.Join(lines, "\n")
}

func (m *model) renderModPickerPanel(width, height int) string {
	lines := []string{
		sectionTitleStyle.Render("Mod Load Manager"),
		sectionMutedStyle.Render(m.modPickerSummary(width)),
	}

	if len(m.modOptions) == 0 {
		lines = append(lines, "No installed mods found.")
		return strings.Join(lines, "\n")
	}

	visibleSlots := max(1, height-6)
	start, end := visibleWindow(len(m.modOptions), visibleSlots, m.modCursor)
	if start > 0 {
		lines = append(lines, sectionMutedStyle.Render("  …"))
	}

	for i := start; i < end; i++ {
		mod := m.modOptions[i]
		prefix := "  "
		style := actionStyle
		if i == m.modCursor {
			prefix = "▶ "
			style = selectedActionStyle
		}

		state := "[off]"
		if mod.Enabled {
			state = "[ON ]"
		}
		changed := ""
		if mod.Enabled != mod.OriginalEnabled {
			changed = " *"
		}

		lines = append(lines, style.Render(fitLine(prefix+state+" "+mod.Name+changed, width)))
	}

	if end < len(m.modOptions) {
		lines = append(lines, sectionMutedStyle.Render("  …"))
	}

	lines = append(lines, "")
	lines = append(lines, sectionMutedStyle.Render("S saves to enabled.json  |  A enable all  |  N disable all"))
	lines = append(lines, sectionMutedStyle.Render("Esc cancels without saving."))
	lines = truncatePanelLines(lines, height)
	return strings.Join(lines, "\n")
}

func (m *model) bodyHeight() int {
	return max(1, m.height-m.headerHeight())
}

func (m *model) filteredActions() []action {
	category := m.currentCategory()
	if category == overviewCategory {
		return m.actions
	}
	filtered := make([]action, 0, len(m.actions))
	for _, act := range m.actions {
		if act.category == category {
			filtered = append(filtered, act)
		}
	}
	return filtered
}

func (m *model) categoryEntries() []string {
	if len(m.categories) <= 1 {
		return nil
	}
	return m.categories[1:]
}

func (m *model) selectedCategoryEntry() (string, bool) {
	entries := m.categoryEntries()
	if len(entries) == 0 {
		return "", false
	}
	if m.cursor < 0 {
		m.cursor = 0
	}
	if m.cursor >= len(entries) {
		m.cursor = len(entries) - 1
	}
	return entries[m.cursor], true
}

func (m *model) selectedAction() (action, bool) {
	filtered := m.filteredActions()
	if len(filtered) == 0 {
		return action{}, false
	}
	if m.cursor < 0 {
		m.cursor = 0
	}
	if m.cursor >= len(filtered) {
		m.cursor = len(filtered) - 1
	}
	return filtered[m.cursor], true
}

func (m *model) currentCategory() string {
	return m.categories[m.categoryIndex]
}

func (m *model) actionLabel(act action) string {
	prefix := act.category + " / "
	if act.category != "" && strings.HasPrefix(act.title, prefix) {
		return strings.TrimPrefix(act.title, prefix)
	}
	return act.title
}

func (act action) isAddonAction() bool {
	return strings.TrimSpace(act.addonManifest) != ""
}

func (m *model) displayPath(path string) string {
	path = strings.TrimSpace(path)
	if path == "" {
		return "."
	}
	rel, err := filepath.Rel(m.baseDir, path)
	if err == nil {
		if rel == "." {
			return "."
		}
		if rel != "" && !strings.HasPrefix(rel, "..") {
			return rel
		}
	}
	return path
}

func (m *model) actionOutputIntroLines(act action) []string {
	lines := []string{}
	if act.isAddonAction() {
		lines = append(lines, "Addon: "+blankFallback(act.addonName, m.actionLabel(act)))
		lines = append(lines, "Manifest: "+m.displayPath(act.addonManifest))
		lines = append(lines, "Working dir: "+m.displayPath(blankFallback(strings.TrimSpace(act.workDir), m.baseDir)))
		lines = append(lines, "")
	}
	lines = append(lines, fmt.Sprintf("$ %s", strings.Join(act.command, " ")), "")
	return lines
}

func addonFailureHint(err error) string {
	if err == nil {
		return "Check the addon command, working_dir, and any script dependencies."
	}
	text := err.Error()
	switch {
	case strings.Contains(text, "working_dir"):
		return "Check the addon working_dir path in addon.json."
	case strings.Contains(text, "chdir"):
		return "The addon working_dir could not be entered. Check that the directory exists and is accessible."
	case strings.Contains(text, "executable file not found"):
		return "The command was not found in PATH. Use an installed binary or launch through bash."
	case strings.Contains(text, "permission denied"):
		return "The command or script is not executable from this environment."
	default:
		return "Check the addon command, working_dir, and any script dependencies."
	}
}

func (m *model) appendAddonFailureDetails(act action, err error) {
	m.appendOutput("Addon: " + blankFallback(act.addonName, m.actionLabel(act)))
	m.appendOutput("Manifest: " + m.displayPath(act.addonManifest))
	m.appendOutput("Working dir: " + m.displayPath(blankFallback(strings.TrimSpace(act.workDir), m.baseDir)))
	m.appendOutput("Hint: " + addonFailureHint(err))
	m.appendOutput("Hint: Review Logs/control.log for addon load warnings.")
}

func (m *model) openCategory(category string) {
	for i, name := range m.categories {
		if name == category {
			m.categoryIndex = i
			m.cursor = 0
			return
		}
	}
}

func (m *model) currentListLength() int {
	if m.currentCategory() == overviewCategory {
		return len(m.categoryEntries())
	}
	return len(m.filteredActions())
}

func (m *model) moveCursor(delta int) {
	total := m.currentListLength()
	if total == 0 {
		m.cursor = 0
		return
	}

	m.cursor += delta
	if m.cursor < 0 {
		m.cursor = 0
	}
	if m.cursor >= total {
		m.cursor = total - 1
	}
}

func (m *model) moveWorldCursor(delta int) {
	if len(m.worldOptions) == 0 {
		m.worldCursor = 0
		return
	}

	m.worldCursor += delta
	if m.worldCursor < 0 {
		m.worldCursor = 0
	}
	if m.worldCursor >= len(m.worldOptions) {
		m.worldCursor = len(m.worldOptions) - 1
	}
}

func (m *model) moveConfigCursor(delta int) {
	if len(m.configOptions) == 0 {
		m.configCursor = 0
		return
	}

	m.configCursor += delta
	if m.configCursor < 0 {
		m.configCursor = 0
	}
	if m.configCursor >= len(m.configOptions) {
		m.configCursor = len(m.configOptions) - 1
	}
}

func (m *model) moveModCursor(delta int) {
	if len(m.modOptions) == 0 {
		m.modCursor = 0
		return
	}

	m.modCursor += delta
	if m.modCursor < 0 {
		m.modCursor = 0
	}
	if m.modCursor >= len(m.modOptions) {
		m.modCursor = len(m.modOptions) - 1
	}
}

func (m *model) toggleCurrentMod() {
	if len(m.modOptions) == 0 {
		return
	}
	m.modOptions[m.modCursor].Enabled = !m.modOptions[m.modCursor].Enabled
}

func (m *model) setAllModsEnabled(enabled bool) {
	for i := range m.modOptions {
		m.modOptions[i].Enabled = enabled
	}
}

func (m *model) mouseOverActionPanel(x, y int) bool {
	panelX, panelY, panelWidth, panelHeight, _, _, _, _ := m.actionPanelGeometry()
	return x >= panelX && x < panelX+panelWidth && y >= panelY && y < panelY+panelHeight
}

func (m *model) mouseOverOutputPanel(x, y int) bool {
	panelX, panelY, panelWidth, panelHeight, _, _, _, _ := m.outputPanelGeometry()
	return x >= panelX && x < panelX+panelWidth && y >= panelY && y < panelY+panelHeight
}

func (m *model) actionPanelListIndexAt(y int) (int, bool) {
	_, _, _, _, _, contentY, _, contentHeight := m.actionPanelGeometry()
	relativeY := y - contentY
	if relativeY < 0 || relativeY >= contentHeight {
		return 0, false
	}

	hotkeyFootprint := panelBlockFootprint(m.renderHotkeyLegend(m.actionPanelTextWidth()))
	clickableRow := 3
	if m.currentCategory() == overviewCategory {
		entries := m.categoryEntries()
		if len(entries) == 0 {
			return 0, false
		}
		start, end := visibleWindow(len(entries), max(1, contentHeight-5-hotkeyFootprint), m.cursor)
		if start > 0 {
			if relativeY == clickableRow {
				return 0, false
			}
			clickableRow++
		}
		for i := start; i < end; i++ {
			if relativeY == clickableRow {
				return i, true
			}
			clickableRow++
		}
		return 0, false
	}

	actions := m.filteredActions()
	if len(actions) == 0 {
		return 0, false
	}
	start, end := visibleWindow(len(actions), max(1, contentHeight-5-hotkeyFootprint), m.cursor)
	if start > 0 {
		if relativeY == clickableRow {
			return 0, false
		}
		clickableRow++
	}
	for i := start; i < end; i++ {
		if relativeY == clickableRow {
			return i, true
		}
		clickableRow++
	}
	return 0, false
}

func (m *model) worldPickerIndexAt(y int) (int, bool) {
	_, _, _, _, _, contentY, _, contentHeight := m.outputPanelGeometry()
	relativeY := y - contentY
	if relativeY < 0 || relativeY >= contentHeight || len(m.worldOptions) == 0 {
		return 0, false
	}

	start, end := visibleWindow(len(m.worldOptions), max(1, contentHeight-6), m.worldCursor)
	row := 2
	if start > 0 {
		if relativeY == row {
			return 0, false
		}
		row++
	}
	for i := start; i < end; i++ {
		if relativeY == row || relativeY == row+1 {
			return i, true
		}
		row += 2
	}
	return 0, false
}

func (m *model) configPickerIndexAt(y int) (int, bool) {
	_, _, _, _, _, contentY, _, contentHeight := m.outputPanelGeometry()
	relativeY := y - contentY
	if relativeY < 0 || relativeY >= contentHeight || len(m.configOptions) == 0 {
		return 0, false
	}

	start, end := visibleWindow(len(m.configOptions), max(1, contentHeight-6), m.configCursor)
	row := 2
	if start > 0 {
		if relativeY == row {
			return 0, false
		}
		row++
	}
	for i := start; i < end; i++ {
		if relativeY == row || relativeY == row+1 {
			return i, true
		}
		row += 2
	}
	return 0, false
}

func (m *model) modPickerIndexAt(y int) (int, bool) {
	_, _, _, _, _, contentY, _, contentHeight := m.outputPanelGeometry()
	relativeY := y - contentY
	if relativeY < 0 || relativeY >= contentHeight || len(m.modOptions) == 0 {
		return 0, false
	}

	start, end := visibleWindow(len(m.modOptions), max(1, contentHeight-6), m.modCursor)
	row := 2
	if start > 0 {
		if relativeY == row {
			return 0, false
		}
		row++
	}
	for i := start; i < end; i++ {
		if relativeY == row {
			return i, true
		}
		row++
	}
	return 0, false
}

func (m *model) categoryActionCount(category string) int {
	count := 0
	for _, act := range m.actions {
		if act.category == category {
			count++
		}
	}
	return count
}

func (m *model) overviewNameWidth() int {
	width := 0
	for _, category := range m.categoryEntries() {
		if w := len([]rune(category)); w > width {
			width = w
		}
	}
	return width
}

func (m *model) categorySummary(category string) string {
	switch category {
	case "Server":
		return "Lifecycle controls, quick status, and active-world selection."
	case "Workshop":
		return "SteamCMD readiness, downloads, URL entry, installed-mod load control, sync, archive, and mod-config editing."
	case "Backup":
		return "World, config, and full snapshots plus retention cleanup."
	case "Monitor":
		return "Health dashboard, one-shot checks, and monitor log access."
	case "Diagnostics":
		return "Quick and deep validation across system, config, network, and logs."
	case "Maintenance":
		return "Routine upkeep tasks and lightweight admin summaries."
	default:
		return "Focused tools for this part of the server workflow."
	}
}

func (m *model) categoryActionPreview(category string, limit int) []string {
	if limit <= 0 {
		return nil
	}

	lines := make([]string, 0, limit)
	for _, act := range m.actions {
		if act.category != category {
			continue
		}
		if len(lines) < limit {
			lines = append(lines, m.actionLabel(act))
		}
		if len(lines) >= limit {
			break
		}
	}

	return lines
}

func (m *model) currentLogSource() logSource {
	return m.logSources[m.logSourceIndex]
}

func (m *model) modPickerSummary(width int) string {
	enabledCount := 0
	changedCount := 0
	for _, mod := range m.modOptions {
		if mod.Enabled {
			enabledCount++
		}
		if mod.Enabled != mod.OriginalEnabled {
			changedCount++
		}
	}

	summary := fmt.Sprintf("%d of %d mods enabled", enabledCount, len(m.modOptions))
	if changedCount > 0 {
		summary += fmt.Sprintf("  |  %d unsaved change(s)", changedCount)
	}
	return fitLine(summary, width)
}

func (m *model) currentOutputXOffset() int {
	if m.outputMode == outputModeCommand {
		return m.commandXOffset
	}
	return m.logXOffset
}

func (m *model) setCurrentOutputXOffset(offset int) {
	if offset < 0 {
		offset = 0
	}
	if m.outputMode == outputModeCommand {
		m.commandXOffset = offset
		return
	}
	m.logXOffset = offset
}

func (m *model) currentOutputLines() []string {
	return m.currentOutputRawLines()
}

func (m *model) currentOutputRawLines() []string {
	if m.outputMode == outputModeCommand {
		if len(m.outputLines) == 0 {
			return []string{"No output yet."}
		}
		return m.outputLines
	}
	if len(m.logLines) == 0 {
		return []string{"No output yet."}
	}
	return m.logLines
}

func (m *model) headerHeight() int {
	height := 1
	if len(m.headerStatusBits()) > 0 {
		height++
	}
	if m.statusError != "" {
		height++
	}
	return height
}

func (m *model) rightColumnLayout() (leftTotalWidth, rightTotalWidth, statusTotalHeight, outputTotalHeight int) {
	leftTotalWidth = actionPanelTotalWidth
	rightTotalWidth = m.width - leftTotalWidth
	if rightTotalWidth < 44 {
		rightTotalWidth = 44
	}

	totalHeight := m.bodyHeight()
	statusTotalHeight = clamp((totalHeight/2)-1, 11, 14)
	if m.currentCategory() == overviewCategory {
		statusTotalHeight += 3
	}
	maxStatusHeight := max(6, totalHeight-8)
	if statusTotalHeight > maxStatusHeight {
		statusTotalHeight = maxStatusHeight
	}
	if statusTotalHeight >= totalHeight {
		statusTotalHeight = max(6, totalHeight/2)
	}
	outputTotalHeight = max(8, totalHeight-statusTotalHeight)
	return
}

func (m *model) outputContentHeight() int {
	_, _, _, outputTotalHeight := m.rightColumnLayout()
	return max(1, availablePanelContentHeight(outputTotalHeight))
}

func (m *model) outputContentWidth() int {
	_, rightTotalWidth, _, _ := m.rightColumnLayout()
	rightWidth := availablePanelContentWidth(rightTotalWidth)
	return panelInnerTextWidth(rightWidth)
}

func (m *model) actionPanelTextWidth() int {
	leftTotalWidth, _, _, _ := m.rightColumnLayout()
	panelWidth := availablePanelContentWidth(leftTotalWidth)
	return panelInnerTextWidth(panelWidth)
}

func (m *model) actionPanelGeometry() (panelX, panelY, panelWidth, panelHeight, contentX, contentY, contentWidth, contentHeight int) {
	leftTotalWidth, _, _, _ := m.rightColumnLayout()
	panelX = 0
	panelY = m.headerHeight()
	panelWidth = leftTotalWidth
	panelHeight = m.bodyHeight()
	contentX = panelX + 2
	contentY = panelY + 1
	contentWidth = m.actionPanelTextWidth()
	contentHeight = max(1, availablePanelContentHeight(panelHeight))
	return
}

func (m *model) outputPanelGeometry() (panelX, panelY, panelWidth, panelHeight, contentX, contentY, contentWidth, contentHeight int) {
	leftTotalWidth, rightTotalWidth, statusTotalHeight, outputTotalHeight := m.rightColumnLayout()
	panelX = leftTotalWidth
	panelY = m.headerHeight() + statusTotalHeight
	panelWidth = rightTotalWidth
	panelHeight = outputTotalHeight
	contentX = panelX + 2
	contentY = panelY + 1
	contentWidth = m.outputContentWidth()
	contentHeight = m.outputContentHeight()
	return
}

func (m *model) shiftOutputScroll(delta int) {
	width := m.outputContentWidth()
	height := m.outputContentHeight()
	view := m.buildOutputView(width, height)
	maxOffset := view.maxOffset
	offset := m.currentOutputXOffset() + delta
	if offset < 0 {
		offset = 0
	}
	if offset > maxOffset {
		offset = maxOffset
	}
	m.setCurrentOutputXOffset(offset)
}

func (m *model) buildOutputView(width, height int) outputView {
	view := outputView{
		title:    "Log Tail",
		lines:    m.logLines,
		subtitle: m.currentLogSource().label,
	}
	if m.outputMode == outputModeCommand {
		view.title = "Command Output"
		view.lines = m.outputLines
		view.subtitle = fmt.Sprintf("Current log source: %s", m.currentLogSource().label)
	}
	if m.outputMode == outputModeLogs && len(view.lines) == 0 {
		m.setCurrentOutputXOffset(0)
		view.emptyState = "Waiting for " + m.currentLogSource().label
		view.indicator = renderOutputIndicator(0, 0, width)
		return view
	}
	if m.outputMode == outputModeCommand && len(view.lines) == 0 {
		m.setCurrentOutputXOffset(0)
		view.emptyState = "Command output will appear here."
		view.indicator = renderOutputIndicator(0, 0, width)
		return view
	}
	if len(view.lines) == 0 {
		view.lines = []string{"No output yet."}
	}

	textRows := 3
	visibleSlots := max(1, height-textRows)
	visible := tailLines(view.lines, visibleSlots)
	view.maxOffset = maxOutputOffset(visible, width)

	view.offset = m.currentOutputXOffset()
	if view.offset > view.maxOffset {
		view.offset = view.maxOffset
		m.setCurrentOutputXOffset(view.offset)
	}

	view.lines = sliceLinesHorizontallyWithIndicators(visible, view.offset, width)
	view.indicator = renderOutputIndicator(view.offset, view.maxOffset, width)
	return view
}

func (m *model) setFooter(text string, ttl time.Duration) {
	m.footer = text
	m.footerTimestamp = time.Now().Add(ttl)
}

func (m *model) renderSelectionRows(width, height int) []string {
	if width <= 0 {
		return nil
	}

	if m.currentCategory() == overviewCategory {
		category, ok := m.selectedCategoryEntry()
		if !ok {
			return nil
		}

		rows := []string{
			sectionTitleStyle.Render("Selected Section"),
		}
		preview := m.categoryActionPreview(category, max(1, m.selectionBlockHeight(height)-1))
		if len(preview) == 0 {
			for _, line := range wrapLine(m.categorySummary(category), width) {
				rows = append(rows, sectionMutedStyle.Render(line))
			}
			return rows
		}
		for _, line := range preview {
			rows = append(rows, sectionMutedStyle.Render(fitLine(line, width)))
		}
		return rows
	}

	act, ok := m.selectedAction()
	if !ok {
		return nil
	}

	rows := []string{
		sectionTitleStyle.Render("Selected Action"),
	}
	for _, line := range wrapLine(act.description, width) {
		rows = append(rows, sectionMutedStyle.Render(line))
	}
	if act.isAddonAction() {
		rows = append(rows, "")
		rows = append(rows, sectionMutedStyle.Render(fitLine("Addon: "+blankFallback(act.addonName, m.actionLabel(act)), width)))
		rows = append(rows, sectionMutedStyle.Render(fitLine("Manifest: "+m.displayPath(act.addonManifest), width)))
		rows = append(rows, sectionMutedStyle.Render(fitLine("Working dir: "+m.displayPath(blankFallback(strings.TrimSpace(act.workDir), m.baseDir)), width)))
	}
	return rows
}

func (m *model) renderSnapshotRows(width int) []string {
	if width <= 0 {
		return nil
	}

	rows := []string{
		sectionTitleStyle.Render("Server Snapshot"),
		renderSnapshotDataRow(0, width, formatSnapshotPair(width, "PID", blankFallback(m.status.PID, "not running"), "World", blankFallback(m.status.World, "none"))),
		renderSnapshotDataRow(1, width, formatSnapshotPair(width, "Players", blankFallback(m.status.Players, "n/a"), "Mods", fmt.Sprintf("%d", m.status.ModCount))),
		renderSnapshotDataRow(2, width, formatSnapshotPair(width, "Backups", fmt.Sprintf("%d", m.status.WorldBackups), "Disk", blankFallback(m.status.DiskBusy, "n/a"))),
		panelDivider(width),
		renderSnapshotDataRow(3, width, formatSnapshotPair(width, blankFallback(m.status.TempLabel, "Temp"), blankFallback(m.status.TempValue, "n/a"), "CPU", blankFallback(m.status.CPU, "n/a"))),
		renderSnapshotDataRow(4, width, formatSnapshotPair(width, "Mem", blankFallback(m.status.Memory, "n/a"), "Uptime", blankFallback(m.status.Uptime, "n/a"))),
	}
	return rows
}

func (m *model) appendOutput(line string) {
	line = strings.TrimRight(line, "\n")
	if line == "" {
		line = " "
	}
	m.outputLines = append(m.outputLines, line)
	if len(m.outputLines) > 2000 {
		m.outputLines = m.outputLines[len(m.outputLines)-2000:]
	}
}

func visibleWindow(total, visible, cursor int) (int, int) {
	if total <= visible {
		return 0, total
	}
	start := cursor - visible/2
	if start < 0 {
		start = 0
	}
	end := start + visible
	if end > total {
		end = total
		start = end - visible
	}
	return start, end
}

func availablePanelContentHeight(totalHeight int) int {
	return max(1, totalHeight-panelVerticalChrome)
}

func availablePanelContentWidth(totalWidth int) int {
	return max(1, totalWidth-panelHorizontalChrome)
}

func panelInnerTextWidth(panelWidth int) int {
	return max(1, panelWidth-panelHorizontalPadding)
}

func (m *model) selectionBlockHeight(totalHeight int) int {
	if m.currentCategory() == overviewCategory {
		switch {
		case totalHeight <= 9:
			return 4
		case totalHeight <= 12:
			return 5
		default:
			return 6
		}
	}

	switch {
	case totalHeight <= 9:
		return 2
	case totalHeight <= 12:
		return 3
	default:
		return 4
	}
}

func normalizePanelBlock(lines []string, height int) []string {
	if height <= 0 {
		return nil
	}
	if len(lines) == 0 {
		return make([]string, height)
	}
	if len(lines) > height {
		return truncatePanelLines(lines, height)
	}

	block := append([]string{}, lines...)
	for len(block) < height {
		block = append(block, "")
	}
	return block
}

func (m *model) appendBottomPanelBlock(lines, block []string, height int) []string {
	if height <= 0 {
		return nil
	}
	if len(block) == 0 {
		return truncatePanelLines(lines, height)
	}

	required := len(block)
	if len(lines) > 0 {
		required++
	}
	if len(lines)+required > height {
		return truncatePanelLines(lines, height)
	}

	rows := append([]string{}, lines...)
	for len(rows)+required < height {
		rows = append(rows, "")
	}
	if len(rows) > 0 {
		rows = append(rows, "")
	}
	rows = append(rows, block...)
	return truncatePanelLines(rows, height)
}

func panelBlockFootprint(block []string) int {
	if len(block) == 0 {
		return 0
	}
	return len(block) + 1
}

func panelDivider(width int) string {
	if width <= 0 {
		return ""
	}
	return panelDividerStyle.Render(strings.Repeat("─", width))
}

func formatSnapshotPair(width int, leftLabel, leftValue, rightLabel, rightValue string) string {
	left := formatSnapshotField(leftLabel, leftValue, width)
	if rightLabel == "" {
		return left
	}

	right := formatSnapshotField(rightLabel, rightValue, width)
	separator := " │ "
	separatorWidth := len([]rune(separator))
	if width <= 0 || width < 28 {
		return fitLine(left+" | "+right, width)
	}

	usableWidth := width - separatorWidth
	leftWidth := 21
	rightWidth := usableWidth - leftWidth
	if rightWidth > 22 {
		rightWidth = 22
	}
	if rightWidth < 14 {
		rightWidth = 14
		leftWidth = usableWidth - rightWidth
	}
	if leftWidth < 14 {
		leftWidth = 14
		rightWidth = usableWidth - leftWidth
	}
	left = formatSnapshotField(leftLabel, leftValue, leftWidth)
	right = formatSnapshotField(rightLabel, rightValue, rightWidth)
	block := fitAndPadLine(left, leftWidth) + separator + fitAndPadLine(right, rightWidth)
	return fitAndPadLine(block, width)
}

func fitAndPadLine(line string, width int) string {
	fitted := fitLine(line, width)
	padding := width - len([]rune(fitted))
	if padding <= 0 {
		return fitted
	}
	return fitted + strings.Repeat(" ", padding)
}

func formatSnapshotField(label, value string, width int) string {
	label = strings.TrimSpace(label)
	value = strings.TrimSpace(value)
	if width <= 0 {
		return ""
	}
	if value == "" {
		return fitLine(label, width)
	}

	const labelWidth = 8
	return fitLine(fmt.Sprintf("%-*s %s", labelWidth, label, value), width)
}

func renderSnapshotDataRow(index, width int, line string) string {
	if index%2 == 0 {
		return snapshotRowEvenStyle.Width(width).Render(fitLine(line, width))
	}
	return snapshotRowOddStyle.Width(width).Render(fitLine(line, width))
}

func maxOutputOffset(lines []string, width int) int {
	if width <= 0 {
		return 0
	}
	maxWidth := 0
	for _, line := range lines {
		lineWidth := len([]rune(line))
		if lineWidth > maxWidth {
			maxWidth = lineWidth
		}
	}
	if maxWidth <= width {
		return 0
	}
	return maxWidth - width
}

func sliceLinesHorizontallyWithIndicators(lines []string, offset, width int) []string {
	if width <= 0 {
		return lines
	}
	sliced := make([]string, 0, len(lines))
	for _, line := range lines {
		sliced = append(sliced, sliceLineHorizontallyWithIndicators(line, offset, width))
	}
	return sliced
}

func sliceLineHorizontallyWithIndicators(line string, offset, width int) string {
	if width <= 0 {
		return ""
	}
	runes := []rune(line)
	if offset >= len(runes) {
		return ""
	}
	if offset < 0 {
		offset = 0
	}
	end := offset + width
	if end > len(runes) {
		end = len(runes)
	}
	segment := []rune(string(runes[offset:end]))
	if len(segment) == 0 {
		return ""
	}
	if offset > 0 {
		segment[0] = '←'
	}
	if end < len(runes) {
		segment[len(segment)-1] = '→'
	}
	return string(segment)
}

func renderOutputIndicator(offset, maxOffset, width int) string {
	if width <= 0 {
		return ""
	}
	start := offset + 1
	end := offset + width
	total := width + maxOffset
	if total < width {
		total = width
	}
	if end > total {
		end = total
	}
	if start < 1 {
		start = 1
	}
	return fmt.Sprintf("Viewing columns %d-%d of %d  |  Shift+Arrows", start, end, total)
}

func truncatePanelLines(lines []string, height int) []string {
	if height <= 0 || len(lines) <= height {
		return lines
	}
	if height == 1 {
		return lines[:1]
	}

	truncated := append([]string{}, lines[:height]...)
	truncated[height-1] = sectionMutedStyle.Render("…")
	return truncated
}

func wrapPanelLines(lines []string, width int) []string {
	if width <= 0 {
		return lines
	}

	wrapped := make([]string, 0, len(lines))
	for _, line := range lines {
		wrapped = append(wrapped, wrapLine(line, width)...)
	}
	return wrapped
}

func wrapLine(line string, width int) []string {
	if width <= 0 {
		return []string{line}
	}
	if line == "" {
		return []string{""}
	}

	parts := strings.Fields(line)
	if len(parts) == 0 {
		return []string{""}
	}

	wrapped := make([]string, 0, 1)
	current := ""
	for _, part := range parts {
		if current == "" {
			if len([]rune(part)) <= width {
				current = part
				continue
			}
			wrapped = append(wrapped, breakLongWord(part, width)...)
			continue
		}

		candidate := current + " " + part
		if len([]rune(candidate)) <= width {
			current = candidate
			continue
		}

		wrapped = append(wrapped, current)
		if len([]rune(part)) <= width {
			current = part
			continue
		}
		wrapped = append(wrapped, breakLongWord(part, width)...)
		current = ""
	}

	if current != "" {
		wrapped = append(wrapped, current)
	}
	if len(wrapped) == 0 {
		return []string{""}
	}
	return wrapped
}

func breakLongWord(word string, width int) []string {
	if width <= 0 {
		return []string{word}
	}

	runes := []rune(word)
	chunks := make([]string, 0, (len(runes)/width)+1)
	for len(runes) > width {
		chunks = append(chunks, string(runes[:width]))
		runes = runes[width:]
	}
	if len(runes) > 0 {
		chunks = append(chunks, string(runes))
	}
	if len(chunks) == 0 {
		return []string{""}
	}
	return chunks
}

var spinnerFrames = []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}

var (
	outerPanelStyle = lipgloss.NewStyle().Padding(0, 1)

	panelStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(lipgloss.Color("#334155")).
			Padding(0, 1).
			MarginRight(1)

	headerTitleStyle = lipgloss.NewStyle().
				Bold(true).
				Foreground(lipgloss.Color("#F8FAFC"))

	headerGapStyle = lipgloss.NewStyle().Width(1)

	headerSubtleStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("#94A3B8"))

	headerMutedStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("#64748B"))

	headerSeparatorStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("#475569"))

	panelDividerStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("#334155"))

	snapshotRowEvenStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("#E2E8F0")).
				Background(lipgloss.Color("#0D1726"))

	snapshotRowOddStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("#D7E3F4")).
				Background(lipgloss.Color("#101C2E"))

	outputHeaderTitleStyle = lipgloss.NewStyle().
				Bold(true).
				Foreground(lipgloss.Color("#E0F2FE")).
				Background(lipgloss.Color("#0F2740"))

	outputHeaderMetaStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("#BFDBFE")).
				Background(lipgloss.Color("#0B1E33"))

	outputBodyStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#E2E8F0"))

	outputPlaceholderStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("#475569")).
				Faint(true)

	outputIndicatorStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("#93C5FD")).
				Background(lipgloss.Color("#0B1E33"))

	inputFieldStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#E2E8F0")).
			Background(lipgloss.Color("#0B1E33"))

	sectionTitleStyle = lipgloss.NewStyle().
				Bold(true).
				Foreground(lipgloss.Color("#7DD3FC"))

	sectionMutedStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("#94A3B8"))

	hotkeyTitleStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("#64748B")).
				Faint(true)

	hotkeyActiveKeyStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("#A7B4C5"))

	hotkeyActiveDescStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("#7C8DA1"))

	hotkeyInactiveKeyStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("#64748B")).
				Faint(true)

	hotkeyInactiveDescStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("#475569")).
				Faint(true)

	actionStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#E2E8F0"))

	actionDescStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#94A3B8"))

	selectedActionStyle = lipgloss.NewStyle().
				Bold(true).
				Foreground(lipgloss.Color("#0F172A")).
				Background(lipgloss.Color("#7DD3FC"))

	selectedActionDescStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("#7DD3FC"))

	stateOnlineStyle = lipgloss.NewStyle().
				Bold(true).
				Foreground(lipgloss.Color("#16A34A"))

	stateOfflineStyle = lipgloss.NewStyle().
				Bold(true).
				Foreground(lipgloss.Color("#EF4444"))

	runningStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("#F59E0B"))

	errorStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("#FCA5A5"))
	infoStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("#FDE68A"))
)

func defaultActions() []action {
	return []action{
		{category: "Server", title: "Server / Show Status", description: "Run the existing server status script.", command: []string{"bash", "Scripts/hub/tmod-control.sh", "status"}},
		{category: "Server", title: "Server / Start Server", description: "Start the server without leaving the TUI.", command: []string{"bash", "Scripts/hub/tmod-control.sh", "start"}},
		{category: "Server", title: "Server / Stop Server", description: "Stop the running server cleanly.", command: []string{"bash", "Scripts/hub/tmod-control.sh", "stop"}, confirmText: "Stop the running server?"},
		{category: "Server", title: "Server / Restart Server", description: "Restart the server through the backend script.", command: []string{"bash", "Scripts/hub/tmod-control.sh", "restart"}, confirmText: "Restart the server now?"},
		{category: "Server", title: "Server / Select Active World", description: "Choose the world file without using the old shell picker.", kind: actionSelectWorld},
		{category: "Server", title: "Server / Start With World Select", description: "Pick a world first, then start the server.", kind: actionSelectWorld, startAfterSelect: true},

		{category: "Workshop", title: "Workshop / Status", description: "Check SteamCMD and workshop readiness.", command: []string{"bash", "Scripts/steam/tmod-workshop.sh", "status"}},
		{category: "Workshop", title: "Workshop / Init", description: "Initialize workshop config and local files.", command: []string{"bash", "Scripts/steam/tmod-workshop.sh", "init"}},
		{category: "Workshop", title: "Workshop / Download Mods", description: "Download queued workshop mods.", command: []string{"bash", "Scripts/steam/tmod-workshop.sh", "download"}},
		{category: "Workshop", title: "Workshop / Sync Mods", description: "Copy workshop mods into Mods/ without prompts.", command: []string{"bash", "Scripts/steam/tmod-workshop.sh", "sync", "--yes"}},
		{category: "Workshop", title: "Workshop / List Downloads", description: "Show the downloaded workshop mod table.", command: []string{"bash", "Scripts/steam/tmod-workshop.sh", "list"}},
		{category: "Workshop", title: "Workshop / Add Mod by URL or ID", description: "Paste a Steam Workshop URL or numeric ID and add it to mod_ids.txt.", kind: actionAddWorkshopMod},
		{category: "Workshop", title: "Workshop / Manage Installed Mods", description: "Toggle which installed mods load at server start, then save enabled.json.", kind: actionManageInstalledMods},
		{category: "Workshop", title: "Workshop / Archive Old Versions", description: "Archive old incompatible workshop builds.", command: []string{"bash", "Scripts/steam/tmod-workshop.sh", "archive", "--yes"}, confirmText: "Archive old workshop versions now?"},
		{category: "Workshop", title: "Workshop / Cleanup Downloads", description: "Clean incomplete workshop downloads.", command: []string{"bash", "Scripts/steam/tmod-workshop.sh", "cleanup"}},
		{category: "Workshop", title: "Workshop / Show Queued Mod IDs", description: "Display mod_ids.txt with resolved names.", command: []string{"bash", "Scripts/steam/tmod-workshop.sh", "mods", "ids"}},
		{category: "Workshop", title: "Workshop / List Installed Mods", description: "Show enabled and disabled installed mods.", command: []string{"bash", "Scripts/steam/tmod-workshop.sh", "mods", "list"}},
		{category: "Workshop", title: "Workshop / Edit Mod Configs", description: "Pick a mod config file and open it in your terminal editor.", kind: actionEditModConfig},

		{category: "Backup", title: "Backup / Status", description: "Inspect backup counts and retention state.", command: []string{"bash", "Scripts/backup/tmod-backup.sh", "status"}},
		{category: "Backup", title: "Backup / World Backup", description: "Create a world backup archive.", command: []string{"bash", "Scripts/backup/tmod-backup.sh", "worlds"}},
		{category: "Backup", title: "Backup / Config Backup", description: "Create a config backup archive.", command: []string{"bash", "Scripts/backup/tmod-backup.sh", "configs"}},
		{category: "Backup", title: "Backup / Full Backup", description: "Create a full server snapshot.", command: []string{"bash", "Scripts/backup/tmod-backup.sh", "full"}},
		{category: "Backup", title: "Backup / Auto Backup", description: "Run worlds, configs, and full backup in sequence.", command: []string{"bash", "Scripts/backup/tmod-backup.sh", "auto"}},
		{category: "Backup", title: "Backup / List All", description: "List all current backup archives.", command: []string{"bash", "Scripts/backup/tmod-backup.sh", "list", "all"}},
		{category: "Backup", title: "Backup / Cleanup Old Backups", description: "Apply the retention policy now.", command: []string{"bash", "Scripts/backup/tmod-backup.sh", "cleanup"}},

		{category: "Monitor", title: "Monitor / Status Dashboard", description: "Run the backend status dashboard.", command: []string{"bash", "Scripts/core/tmod-monitor.sh", "status"}},
		{category: "Monitor", title: "Monitor / Health Check", description: "Run a single health check.", command: []string{"bash", "Scripts/core/tmod-monitor.sh", "check"}},
		{category: "Monitor", title: "Monitor / Show Logs", description: "Show the recent monitor log entries.", command: []string{"bash", "Scripts/core/tmod-monitor.sh", "logs"}},

		{category: "Diagnostics", title: "Diagnostics / Quick", description: "Run the quick diagnostics flow.", command: []string{"bash", "Scripts/diag/tmod-diagnostics.sh", "quick"}},
		{category: "Diagnostics", title: "Diagnostics / Full", description: "Run the full diagnostics report.", command: []string{"bash", "Scripts/diag/tmod-diagnostics.sh", "full"}},
		{category: "Diagnostics", title: "Diagnostics / System", description: "Gather OS, memory, and disk facts.", command: []string{"bash", "Scripts/diag/tmod-diagnostics.sh", "system"}},
		{category: "Diagnostics", title: "Diagnostics / Directories", description: "Validate the project directory layout.", command: []string{"bash", "Scripts/diag/tmod-diagnostics.sh", "directories"}},
		{category: "Diagnostics", title: "Diagnostics / Binaries", description: "Inspect the engine and runtime binaries.", command: []string{"bash", "Scripts/diag/tmod-diagnostics.sh", "binaries"}},
		{category: "Diagnostics", title: "Diagnostics / Config", description: "Check the server configuration state.", command: []string{"bash", "Scripts/diag/tmod-diagnostics.sh", "config"}},
		{category: "Diagnostics", title: "Diagnostics / Dependencies", description: "Check core command dependencies.", command: []string{"bash", "Scripts/diag/tmod-diagnostics.sh", "dependencies"}},
		{category: "Diagnostics", title: "Diagnostics / Processes", description: "Inspect server and helper processes.", command: []string{"bash", "Scripts/diag/tmod-diagnostics.sh", "processes"}},
		{category: "Diagnostics", title: "Diagnostics / Network", description: "Inspect ports and network assumptions.", command: []string{"bash", "Scripts/diag/tmod-diagnostics.sh", "network"}},
		{category: "Diagnostics", title: "Diagnostics / Logs", description: "Analyze recent logs for issues.", command: []string{"bash", "Scripts/diag/tmod-diagnostics.sh", "logs"}},
		{category: "Diagnostics", title: "Diagnostics / Scripts", description: "Validate script availability and paths.", command: []string{"bash", "Scripts/diag/tmod-diagnostics.sh", "scripts"}},
		{category: "Diagnostics", title: "Diagnostics / Security", description: "Run the security-oriented checks.", command: []string{"bash", "Scripts/diag/tmod-diagnostics.sh", "security"}},
		{category: "Diagnostics", title: "Diagnostics / Performance", description: "Run the performance-focused checks.", command: []string{"bash", "Scripts/diag/tmod-diagnostics.sh", "performance"}},
		{category: "Diagnostics", title: "Diagnostics / Report", description: "Generate the diagnostics report file.", command: []string{"bash", "Scripts/diag/tmod-diagnostics.sh", "report"}},

		{category: "Maintenance", title: "Maintenance / Run All Tasks", description: "Run backup cleanup, log rotation, sync, and mod checks.", command: []string{"bash", "Scripts/hub/tmod-control.sh", "maintenance"}, confirmText: "Run the full maintenance sequence now?"},
		{category: "Maintenance", title: "Maintenance / Health Snapshot", description: "Run the lightweight admin health summary.", command: []string{"bash", "Scripts/hub/tmod-control.sh", "health"}},
		{category: "Maintenance", title: "Maintenance / Scripts Status", description: "Check the backend script surface from the shell hub.", command: []string{"bash", "Scripts/hub/tmod-control.sh", "scripts"}},
	}
}

func categoriesForActions(actions []action) []string {
	categories := []string{overviewCategory}
	seen := map[string]bool{
		overviewCategory: true,
	}

	builtInOrder := []string{"Server", "Workshop", "Backup", "Monitor", "Diagnostics", "Maintenance"}
	for _, category := range builtInOrder {
		if !actionCategoryPresent(actions, category) {
			continue
		}
		categories = append(categories, category)
		seen[category] = true
	}

	for _, act := range actions {
		category := strings.TrimSpace(act.category)
		if category == "" || seen[category] {
			continue
		}
		categories = append(categories, category)
		seen[category] = true
	}

	return categories
}

func actionCategoryPresent(actions []action, category string) bool {
	for _, act := range actions {
		if act.category == category {
			return true
		}
	}
	return false
}

func boolBadge(ok bool) string {
	if ok {
		return stateOnlineStyle.Render("online")
	}
	return stateOfflineStyle.Render("offline")
}
