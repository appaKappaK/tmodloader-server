package main

import (
	"fmt"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type actionKind int

const (
	actionRunCommand actionKind = iota
	actionSelectWorld
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
)

const overviewCategory = "Overview"
const panelVerticalChrome = 2
const panelHorizontalChrome = 3
const panelHorizontalPadding = 2

type action struct {
	category         string
	title            string
	description      string
	command          []string
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

type outputLineMsg struct {
	text string
}

type commandDoneMsg struct {
	action   string
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

	status      appStatus
	statusError string
	lastRefresh time.Time

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
}

type outputView struct {
	title        string
	subtitle     string
	lines        []string
	emptyState   string
	offset       int
	maxOffset    int
	showOverflow bool
}

func newModel(baseDir string) *model {
	return &model{
		baseDir:        baseDir,
		actions:        defaultActions(),
		categories:     []string{overviewCategory, "Server", "Workshop", "Backup", "Monitor", "Diagnostics", "Maintenance"},
		logSources:     defaultLogSources(baseDir),
		outputMode:     outputModeLogs,
		footer:         "↑/↓ move • Enter open/run • Esc back • wheel scrolls 1 item • q quit • Ctrl+C force quit",
		outputLines:    nil,
		categoryIndex:  0,
		cursor:         0,
		logSourceIndex: 0,
	}
}

func (m *model) footerActive() bool {
	return m.footer != "" && time.Now().Before(m.footerTimestamp)
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
		switch m.uiMode {
		case uiModeConfirm:
			return m, nil
		case uiModeWorldPicker:
			return m.handleWorldPickerMouse(msg)
		default:
			return m.handleNormalMouse(msg)
		}

	case tea.KeyMsg:
		switch m.uiMode {
		case uiModeConfirm:
			return m.handleConfirmKeys(msg)
		case uiModeWorldPicker:
			return m.handleWorldPickerKeys(msg)
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

	case outputLineMsg:
		m.appendOutput(msg.text)
		m.outputMode = outputModeCommand
		return m, nil

	case commandDoneMsg:
		m.running = false
		m.activeAction = ""
		m.activeSince = time.Time{}
		if msg.err != nil {
			m.appendOutput(fmt.Sprintf("✗ %s failed after %s: %v", msg.action, msg.duration.Round(time.Second), msg.err))
			m.setFooter(msg.action+" failed.", 4*time.Second)
		} else {
			m.appendOutput(fmt.Sprintf("✓ %s finished in %s", msg.action, msg.duration.Round(time.Second)))
			m.setFooter(msg.action+" finished successfully.", 4*time.Second)
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
		if m.running {
			m.setFooter("A command is already running.", 2*time.Second)
			return m, nil
		}
		if m.currentCategory() == overviewCategory {
			category, ok := m.selectedCategoryEntry()
			if !ok {
				return m, nil
			}
			m.openCategory(category)
			return m, nil
		}
		act, ok := m.selectedAction()
		if !ok {
			return m, nil
		}
		return m, m.triggerAction(act)
	case "r":
		m.setFooter("Refreshing status and current log…", 2*time.Second)
		return m, tea.Batch(refreshStatusCmd(m.baseDir), refreshLogCmd(m.currentLogSource()))
	case "l":
		m.logSourceIndex = (m.logSourceIndex + 1) % len(m.logSources)
		m.logXOffset = 0
		if m.outputMode == outputModeLogs {
			m.setFooter("Switched log source to "+m.currentLogSource().label+".", 2*time.Second)
			return m, refreshLogCmd(m.currentLogSource())
		}
		m.setFooter("Next log source: "+m.currentLogSource().label+". Press Tab to view.", 2*time.Second)
		return m, nil
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

func (m *model) handleNormalMouse(msg tea.MouseMsg) (tea.Model, tea.Cmd) {
	if msg.Action != tea.MouseActionPress {
		return m, nil
	}
	if m.mouseOverActionPanel(msg.X) {
		switch msg.Button {
		case tea.MouseButtonWheelUp:
			m.moveCursor(-1)
		case tea.MouseButtonWheelDown:
			m.moveCursor(1)
		}
		return m, nil
	}
	if !m.mouseOverOutputPanel(msg.X, msg.Y) {
		return m, nil
	}

	switch msg.Button {
	case tea.MouseButtonWheelLeft:
		m.shiftOutputScroll(-6)
	case tea.MouseButtonWheelRight:
		m.shiftOutputScroll(6)
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
		if len(m.worldOptions) == 0 {
			return m, nil
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
		return m, setWorldCmd(m.baseDir, selected, m.pendingAction.startAfterSelect)
	}

	return m, nil
}

func (m *model) handleWorldPickerMouse(msg tea.MouseMsg) (tea.Model, tea.Cmd) {
	if msg.Action != tea.MouseActionPress {
		return m, nil
	}

	switch msg.Button {
	case tea.MouseButtonWheelUp:
		m.moveWorldCursor(-1)
	case tea.MouseButtonWheelDown:
		m.moveWorldCursor(1)
	}

	return m, nil
}

func (m *model) triggerAction(act action) tea.Cmd {
	switch act.kind {
	case actionSelectWorld:
		return listWorldsCmd(m.baseDir, act.startAfterSelect)
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

	header := m.renderHeader()
	body := lipgloss.JoinHorizontal(lipgloss.Top, m.renderActionPanel(), m.renderRightColumn())
	return lipgloss.JoinVertical(lipgloss.Left, header, body)
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

	statusBits := []string{}

	if m.running {
		statusBits = append(statusBits, runningStyle.Render(spinnerFrames[m.spinnerIndex]+" "+m.activeAction))
	}

	headerLine := lipgloss.JoinHorizontal(
		lipgloss.Left,
		stateStyle.Render(stateText),
		headerGapStyle.Render(" "),
		title,
		headerGapStyle.Render(" "),
		subtitle,
	)
	statusLine := joinHeaderBits(statusBits)
	if m.footerActive() {
		available := m.width - lipgloss.Width(headerLine) - 4
		if available > 8 {
			headerLine = lipgloss.JoinHorizontal(
				lipgloss.Left,
				headerLine,
				infoStyle.Render(" • "+fitLine(m.footer, available)),
			)
		} else if statusLine == "" {
			statusLine = infoStyle.Render(fitLine(m.footer, m.width-4))
		} else {
			available = m.width - lipgloss.Width(statusLine) - 6
			if available > 4 {
				statusLine = lipgloss.JoinHorizontal(
					lipgloss.Left,
					statusLine,
					infoStyle.Render(" • "+fitLine(m.footer, available)),
				)
			}
		}
	}

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
	panelTotalWidth := clamp(m.width/3, 36, 52)
	panelWidth := availablePanelContentWidth(panelTotalWidth)
	textWidth := panelInnerTextWidth(panelWidth)
	contentHeight := availablePanelContentHeight(m.bodyHeight())
	if m.currentCategory() == overviewCategory {
		return m.renderOverviewPanel(panelWidth, contentHeight)
	}

	lines := []string{
		m.renderCategoryTabs(textWidth),
		panelDivider(textWidth),
		sectionTitleStyle.Render(m.currentCategory()),
	}

	filtered := m.filteredActions()
	visibleSlots := max(1, contentHeight-12)
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

	return panelStyle.Width(panelWidth).Height(contentHeight).Render(strings.Join(lines, "\n"))
}

func (m *model) renderOverviewPanel(panelWidth int, contentHeight int) string {
	textWidth := panelInnerTextWidth(panelWidth)
	lines := []string{
		m.renderCategoryTabs(textWidth),
		panelDivider(textWidth),
		sectionTitleStyle.Render("Sections"),
	}

	entries := m.categoryEntries()
	nameWidth := m.overviewNameWidth()
	visibleSlots := max(1, contentHeight-11)
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

	statusContentHeight := availablePanelContentHeight(statusTotalHeight)
	outputContentHeight := availablePanelContentHeight(outputTotalHeight)

	statusPanel := panelStyle.Width(rightWidth).Height(statusContentHeight).Render(m.renderStatusPanel(panelInnerTextWidth(rightWidth), statusContentHeight))
	outputPanel := panelStyle.Width(rightWidth).Height(outputContentHeight).Render(m.renderOutputPanel(panelInnerTextWidth(rightWidth), outputContentHeight))

	return lipgloss.JoinVertical(lipgloss.Left, statusPanel, outputPanel)
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
	}

	view := m.buildOutputView(width, height)

	rendered := []string{
		outputHeaderTitleStyle.Width(width).Render(view.title),
	}
	rendered = append(rendered, outputHeaderMetaStyle.Width(width).Render(fitLine(view.subtitle, width)))
	if view.emptyState != "" {
		bodyHeight := max(1, height-2)
		placeholder := lipgloss.Place(width, bodyHeight, lipgloss.Center, lipgloss.Center, outputPlaceholderStyle.Render(view.emptyState))
		rendered = append(rendered, placeholder)
		return strings.Join(rendered, "\n")
	}
	for _, line := range view.lines {
		rendered = append(rendered, outputBodyStyle.Render(fitLine(line, width)))
	}
	if view.showOverflow {
		rendered = append(rendered, outputIndicatorStyle.Render(fitLine(renderOutputIndicator(view.offset, view.maxOffset, width), width)))
	}
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

func (m *model) mouseOverActionPanel(x int) bool {
	panelWidth := clamp(m.width/3, 36, 52)
	return x <= panelWidth+3
}

func (m *model) mouseOverOutputPanel(x, y int) bool {
	panelX, panelY, panelWidth, panelHeight, _, _, _, _ := m.outputPanelGeometry()
	return x >= panelX && x < panelX+panelWidth && y >= panelY && y < panelY+panelHeight
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
		return "SteamCMD readiness, downloads, sync, archive, and installed-mod views."
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
	if m.running {
		height++
	}
	if m.statusError != "" {
		height++
	}
	return height
}

func (m *model) rightColumnLayout() (leftTotalWidth, rightTotalWidth, statusTotalHeight, outputTotalHeight int) {
	leftTotalWidth = clamp(m.width/3, 36, 52)
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
		subtitle: fmt.Sprintf("%s  |  Shift+Arrows", m.currentLogSource().label),
	}
	if m.outputMode == outputModeCommand {
		view.title = "Command Output"
		view.lines = m.outputLines
		view.subtitle = fmt.Sprintf("Tab  |  %s", m.currentLogSource().label)
	}
	if m.outputMode == outputModeLogs && len(view.lines) == 0 {
		m.setCurrentOutputXOffset(0)
		view.emptyState = "Waiting for " + m.currentLogSource().label
		return view
	}
	if m.outputMode == outputModeCommand && len(view.lines) == 0 {
		m.setCurrentOutputXOffset(0)
		view.emptyState = "Command output will appear here."
		return view
	}
	if len(view.lines) == 0 {
		view.lines = []string{"No output yet."}
	}

	textRows := 2
	visibleSlots := max(1, height-textRows)
	visible := tailLines(view.lines, visibleSlots)
	view.maxOffset = maxOutputOffset(visible, width)
	view.showOverflow = view.maxOffset > 0
	if view.showOverflow {
		visibleSlots = max(1, height-textRows-1)
		visible = tailLines(view.lines, visibleSlots)
		view.maxOffset = maxOutputOffset(visible, width)
	}

	view.offset = m.currentOutputXOffset()
	if view.offset > view.maxOffset {
		view.offset = view.maxOffset
		m.setCurrentOutputXOffset(view.offset)
	}

	view.lines = sliceLinesHorizontallyWithIndicators(visible, view.offset, width)
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
	return rows
}

func (m *model) renderSnapshotRows(width int) []string {
	if width <= 0 {
		return nil
	}

	state := "OFFLINE"
	if m.status.Online {
		state = "ONLINE"
	}

	rows := []string{
		sectionTitleStyle.Render("Server Snapshot"),
		renderSnapshotDataRow(0, width, formatSnapshotPair(width, "State", state, "PID", blankFallback(m.status.PID, "not running"))),
		renderSnapshotDataRow(1, width, formatSnapshotPair(width, "World", blankFallback(m.status.World, "none"), "Players", blankFallback(m.status.Players, "0"))),
		renderSnapshotDataRow(2, width, formatSnapshotPair(width, "Mods", fmt.Sprintf("%d", m.status.ModCount), "Backups", fmt.Sprintf("%d", m.status.WorldBackups))),
		panelDivider(width),
		renderSnapshotDataRow(3, width, formatSnapshotPair(width, blankFallback(m.status.TempLabel, "Temp"), blankFallback(m.status.TempValue, "n/a"), "CPU", blankFallback(m.status.CPU, "0%"))),
		renderSnapshotDataRow(4, width, formatSnapshotPair(width, "Mem", blankFallback(m.status.Memory, "0%"), "Uptime", blankFallback(m.status.Uptime, "0m"))),
		renderSnapshotDataRow(5, width, formatSnapshotPair(width, "Disk", blankFallback(m.status.DiskBusy, "n/a"), "", "")),
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
	leftWidth := usableWidth * 44 / 100
	if leftWidth < 14 {
		leftWidth = 14
	}
	if leftWidth > usableWidth-14 {
		leftWidth = usableWidth - 14
	}
	rightWidth := usableWidth - leftWidth
	left = formatSnapshotField(leftLabel, leftValue, leftWidth)
	right = formatSnapshotField(rightLabel, rightValue, rightWidth)
	return fitAndPadLine(left, leftWidth) + separator + fitLine(right, rightWidth)
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
	if maxOffset <= 0 {
		return ""
	}
	start := offset + 1
	end := offset + width
	total := width + maxOffset
	if end > total {
		end = total
	}
	return fmt.Sprintf("Horizontal scroll %d-%d of %d  |  Shift+Arrows", start, end, total)
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

	sectionTitleStyle = lipgloss.NewStyle().
				Bold(true).
				Foreground(lipgloss.Color("#7DD3FC"))

	sectionMutedStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("#94A3B8"))

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
		{category: "Workshop", title: "Workshop / Archive Old Versions", description: "Archive old incompatible workshop builds.", command: []string{"bash", "Scripts/steam/tmod-workshop.sh", "archive", "--yes"}, confirmText: "Archive old workshop versions now?"},
		{category: "Workshop", title: "Workshop / Cleanup Downloads", description: "Clean incomplete workshop downloads.", command: []string{"bash", "Scripts/steam/tmod-workshop.sh", "cleanup"}},
		{category: "Workshop", title: "Workshop / Show Queued Mod IDs", description: "Display mod_ids.txt with resolved names.", command: []string{"bash", "Scripts/steam/tmod-workshop.sh", "mods", "ids"}},
		{category: "Workshop", title: "Workshop / List Installed Mods", description: "Show enabled and disabled installed mods.", command: []string{"bash", "Scripts/steam/tmod-workshop.sh", "mods", "list"}},

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
		{category: "Maintenance", title: "Maintenance / Scripts Status", description: "Check the backend script surface from the legacy admin command.", command: []string{"bash", "Scripts/hub/tmod-control.sh", "scripts"}},
	}
}

func boolBadge(ok bool) string {
	if ok {
		return stateOnlineStyle.Render("online")
	}
	return stateOfflineStyle.Render("offline")
}
