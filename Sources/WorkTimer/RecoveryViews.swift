import AppKit
import SwiftUI

struct TimerPanelView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var hourlyRateInput = ""
    @State private var workedTimeDigits = ""
    @State private var isEditingWorkedTime = false
    @State private var inputExpanded = true
    @State private var aiExpanded = false
    @State private var diskExpanded = false
    @State private var historyExpanded = true
    @State private var logExpanded = false
    @State private var topBarPickerExpanded = false
    @FocusState private var hourlyRateFieldFocused: Bool
    @FocusState private var workedTimeFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerCard
                controlsRow
                if model.shouldShowOnboardingCard {
                    onboardingCard
                }
                topBarCard
                payCard
                typingCard
                aiCard
                diskCard
                historyCard
                logCard
            }
            .padding(14)
        }
        .frame(minWidth: 344, idealWidth: 368, maxWidth: 440, minHeight: 420, idealHeight: 520, maxHeight: 760, alignment: .topLeading)
        .background(theme.windowBackground)
        .foregroundStyle(theme.primary)
        .preferredColorScheme(model.preferredColorScheme)
        .scrollIndicators(.visible)
        .onAppear {
            syncHourlyRateInput()
            syncWorkedTimeInput()
        }
        .onChange(of: hourlyRateFieldFocused) { _, isFocused in
            if !isFocused {
                commitHourlyRateInput()
            }
        }
        .onChange(of: workedTimeFieldFocused) { _, isFocused in
            if !isFocused {
                commitWorkedTimeInput()
                isEditingWorkedTime = false
            }
        }
        .onChange(of: model.hourlyRate) { _, _ in
            guard !hourlyRateFieldFocused else {
                return
            }
            syncHourlyRateInput()
        }
        .onChange(of: model.cumulativeRunText) { _, _ in
            guard !workedTimeFieldFocused else {
                return
            }
            syncWorkedTimeInput()
        }
        .onExitCommand {
            model.hideControlPanel()
        }
    }

    private var onboardingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Setup")
                Spacer()
                Text(model.onboardingProgressText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondary)
                Button("Later") {
                    model.dismissOnboarding()
                }
                .buttonStyle(TextPanelButtonStyle(theme: theme))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(model.onboardingHeadline)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.primary)

                Text(model.onboardingDescription)
                    .font(.caption)
                    .foregroundStyle(theme.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(model.onboardingChecklist.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text(item.complete ? "Done" : "\(index + 1)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(item.complete ? theme.inversePrimary : theme.primary)
                            .frame(width: 28, height: 22)
                            .background(item.complete ? theme.accent : theme.mutedFill)
                            .clipShape(Capsule())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(theme.secondary)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Button(model.onboardingPrimaryActionTitle) {
                    model.performPrimaryOnboardingAction()
                }
                .buttonStyle(PrimaryPanelButtonStyle(theme: theme))

                if let secondaryTitle = model.onboardingSecondaryActionTitle {
                    Button(secondaryTitle) {
                        model.performSecondaryOnboardingAction()
                    }
                    .buttonStyle(SecondaryPanelButtonStyle(theme: theme))
                }
            }
        }
        .panelCard(theme: theme)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WorkTimer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.secondary)

                    HStack(alignment: .center, spacing: 8) {
                        Text(model.elapsedText)
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        Button {
                            toggleWorkedTimeEditor()
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isEditingWorkedTime ? theme.accent : theme.secondary)
                                .frame(width: 24, height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(isEditingWorkedTime ? theme.accent.opacity(0.14) : theme.cardFill)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(isEditingWorkedTime ? theme.accent : theme.stroke, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    if isEditingWorkedTime {
                        HStack(spacing: 8) {
                            TextField("h:mm:ss", text: workedTimeInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .focused($workedTimeFieldFocused)
                                .onSubmit {
                                    saveWorkedTimeEdit()
                                }

                            Button("Set") {
                                saveWorkedTimeEdit()
                            }
                            .buttonStyle(MiniPanelButtonStyle(theme: theme))
                        }
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Button {
                        model.appearanceMode = nextAppearanceMode(after: model.appearanceMode)
                    } label: {
                        Image(systemName: appearanceSymbol)
                    }
                    .buttonStyle(IconPanelButtonStyle(theme: theme))
                    .help("Switch appearance")

                    Button {
                        model.resetTimer()
                    } label: {
                        Text("Reset")
                    }
                    .buttonStyle(MiniPanelButtonStyle(theme: theme))
                    .keyboardShortcut("r", modifiers: [.command])
                }
            }

            HStack(spacing: 8) {
                CompactMetric(label: "Status", value: model.stateLabel)
                CompactMetric(label: "Today", value: model.cumulativeRunText)
                CompactMetric(label: "Pay", value: model.currentEarningsText)
            }
        }
        .panelCard(theme: theme)
    }

    private var controlsRow: some View {
        HStack(spacing: 8) {
            Button(model.isRunning ? "Pause" : "Resume") {
                model.toggleRunning()
            }
            .buttonStyle(PrimaryPanelButtonStyle(theme: theme))
            .keyboardShortcut("p", modifiers: [.command])

            Button("Hide") {
                model.hideControlPanel()
            }
            .buttonStyle(SecondaryPanelButtonStyle(theme: theme))

            Spacer(minLength: 0)

            Button("Copy") {
                model.copySummary()
            }
            .buttonStyle(TextPanelButtonStyle(theme: theme))
            .keyboardShortcut("c", modifiers: [.command])
        }
    }

    private var payCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Pay")

            VStack(alignment: .leading, spacing: 8) {
                Text("Per hour")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondary)

                HStack(spacing: 6) {
                    Text("$")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.secondary)

                    TextField("0", text: $hourlyRateInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .focused($hourlyRateFieldFocused)
                        .onChange(of: hourlyRateInput) { _, newValue in
                            let sanitized = sanitizedHourlyRateInput(newValue)
                            if sanitized != newValue {
                                hourlyRateInput = sanitized
                            }
                        }
                        .onSubmit {
                            commitHourlyRateInput()
                        }
                }
            }
        }
        .panelCard(theme: theme)
    }

    private var topBarCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Top bar")

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    topBarPickerExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Show in menu bar")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(theme.secondary)
                        Text(model.menuBarDisplayMode.title)
                            .font(.system(size: 20, weight: .bold, design: .default))
                            .foregroundStyle(theme.primary)
                        Text(topBarModePreview(model.menuBarDisplayMode))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.secondary)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: topBarPickerExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.primary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(theme.cardFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(topBarPickerExpanded ? theme.primary.opacity(0.35) : theme.stroke, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if topBarPickerExpanded {
                VStack(spacing: 6) {
                    ForEach(AppModel.MenuBarDisplayMode.allCases, id: \.self) { mode in
                        Button {
                            model.menuBarDisplayMode = mode
                            withAnimation(.easeInOut(duration: 0.18)) {
                                topBarPickerExpanded = false
                            }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(theme.primary)
                                    Text(topBarModePreview(mode))
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(theme.secondary)
                                }

                                Spacer(minLength: 8)

                                if model.menuBarDisplayMode == mode {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(theme.primary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(model.menuBarDisplayMode == mode ? theme.mutedFill : theme.windowBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(model.menuBarDisplayMode == mode ? theme.primary.opacity(0.28) : theme.stroke, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            StatRow(label: "Preview", value: model.topBarText)
                .padding(.top, 2)

            if model.menuBarDisplayMode == .aiTokensPerSecond {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Last 30 minutes")
                    AIRateSparkline(values: model.aiRateSeries, trailingLabel: "30m")
                        .frame(height: 56)
                }
                .padding(.top, 2)
            }
        }
        .panelCard(theme: theme)
    }

    private var aiCard: some View {
        ExpandablePanel(isExpanded: $aiExpanded) {
                cardHeader(title: "AI Usage", status: model.aiStatusLabel, emphasized: model.aiUsageAvailable, isExpanded: aiExpanded)
        } content: {
                Text(
                    model.aiUsageAvailable
                        ? "Live Codex and Claude usage pulled from local usage snapshots and session logs."
                        : "AI usage is unavailable until WorkTimer can find the local usage-data snapshots and session folders."
                )
                .font(.caption)
                .foregroundStyle(theme.secondary)

                VStack(spacing: 8) {
                    StatRow(label: "Combined", value: model.aiCombinedTokensText)
                    StatRow(label: "Today", value: model.aiTodayTokensText)
                    StatRow(label: "Rate", value: model.aiTokensPerSecondText)
                    StatRow(label: "Codex", value: model.aiCodexTokensText)
                    StatRow(label: "Claude", value: model.aiClaudeTokensText)
                    StatRow(label: "Watched files", value: model.aiWatchedFilesText)
                }
                .padding(.top, 6)
        }
    }

    private var diskCard: some View {
        ExpandablePanel(isExpanded: $diskExpanded) {
            cardHeader(title: "Disk", status: model.diskStatusLabel, emphasized: model.diskHealthAvailable, isExpanded: diskExpanded)
        } content: {
                Text(
                    model.diskHealthAvailable
                        ? "Internal SSD counters from diskutil SMART fields."
                        : "Disk counters are unavailable on this Mac right now."
                )
                .font(.caption)
                .foregroundStyle(theme.secondary)

                VStack(spacing: 8) {
                    StatRow(label: "Read", value: model.diskReadText)
                    StatRow(label: "Written", value: model.diskWrittenText)
                    StatRow(label: "Read cmds", value: model.diskHostReadCommandsText)
                    StatRow(label: "Write cmds", value: model.diskHostWriteCommandsText)
                    StatRow(label: "Wear", value: model.diskWearText)
                    StatRow(label: "Power on", value: model.diskPowerOnText)
                }
                .padding(.top, 6)
        }
    }

    private var typingCard: some View {
        ExpandablePanel(isExpanded: $inputExpanded) {
            cardHeader(title: "Input", status: model.typingStatusLabel, emphasized: model.isTyping, isExpanded: inputExpanded)
        } content: {
                Text(model.typingStatusDetail)
                    .font(.caption)
                    .foregroundStyle(theme.secondary)

                if !model.isInstalledInApplications {
                    Button("Open Applications Folder") {
                        model.openApplicationsFolder()
                    }
                    .buttonStyle(SecondaryPanelButtonStyle(theme: theme))
                }

                if model.needsTypingPermissions {
                    HStack(spacing: 8) {
                        Button("Request + Open Settings") {
                            model.requestTypingPermissions()
                        }
                        .buttonStyle(SecondaryPanelButtonStyle(theme: theme))

                        Button("Open Both Panes") {
                            model.openTypingPermissionPanes()
                        }
                        .buttonStyle(TextPanelButtonStyle(theme: theme))
                    }

                    Text("WorkTimer retries automatically. If stats still do not start after a few seconds, reopen the app once.")
                        .font(.caption)
                        .foregroundStyle(theme.secondary)
                }

                VStack(spacing: 8) {
                    StatRow(label: "Typing time", value: model.typingTimeText)
                    StatRow(label: "Characters", value: model.typingCharacterCountText)
                    StatRow(label: "CPM", value: model.typingCharactersPerMinuteText)
                    StatRow(label: "WPM", value: model.typingWordsPerMinuteText)
                }
                .padding(.top, 4)

                Divider()

                Group {
                    subSectionHeader(title: "Mouse", status: model.mouseStatusLabel, emphasized: model.isMouseMoving)
                    Text("Tracks how far the cursor travels across mouse moves and drags during the day.")
                        .font(.caption)
                        .foregroundStyle(theme.secondary)

                    VStack(spacing: 8) {
                        StatRow(label: "Travel", value: model.mouseDistanceText)
                        StatRow(label: "Move time", value: model.mouseMoveTimeText)
                        StatRow(label: "Travel / min", value: model.mouseDistancePerMinuteText)
                    }
                }

                Divider()

                Group {
                    subSectionHeader(title: "Wispr Flow", status: model.wisprFlowStatusLabel, emphasized: model.wisprFlowAvailable)
                    Text(
                        model.wisprFlowAvailable
                            ? "Reads today’s dictation totals from the local Wispr Flow history database."
                            : "Wispr Flow stats show up automatically when a local flow.sqlite database is available."
                    )
                    .font(.caption)
                    .foregroundStyle(theme.secondary)

                    VStack(spacing: 8) {
                        StatRow(label: "Words today", value: model.wisprWordsTodayText)
                        StatRow(label: "Dictation time", value: model.wisprDictationDurationTodayText)
                        StatRow(label: "Clips today", value: model.wisprClipsTodayText)
                    }
                }
        }
    }

    private func syncHourlyRateInput() {
        hourlyRateInput = Self.moneyFormatter.string(from: NSNumber(value: model.hourlyRate)) ?? "0.00"
    }

    private func syncWorkedTimeInput() {
        workedTimeDigits = digitsForWorkedTime(model.cumulativeRunTime)
    }

    private func commitHourlyRateInput() {
        let cleaned = sanitizedHourlyRateInput(hourlyRateInput)
        let parsedValue = Double(cleaned) ?? 0
        model.hourlyRate = parsedValue
        syncHourlyRateInput()
    }

    private func commitWorkedTimeInput() {
        guard let parsedValue = parseWorkedTimeDigits(workedTimeDigits) else {
            syncWorkedTimeInput()
            return
        }
        model.setWorkedDuration(parsedValue)
        syncWorkedTimeInput()
    }

    private func toggleWorkedTimeEditor() {
        if isEditingWorkedTime {
            saveWorkedTimeEdit()
            return
        }

        syncWorkedTimeInput()
        isEditingWorkedTime = true
        DispatchQueue.main.async {
            workedTimeFieldFocused = true
        }
    }

    private func saveWorkedTimeEdit() {
        commitWorkedTimeInput()
        isEditingWorkedTime = false
        workedTimeFieldFocused = false
    }

    private func sanitizedHourlyRateInput(_ raw: String) -> String {
        var result = ""
        var hasDecimalSeparator = false

        for character in raw {
            if character.isNumber {
                result.append(character)
                continue
            }

            if character == ".", !hasDecimalSeparator {
                hasDecimalSeparator = true
                result.append(character)
            }
        }

        return result
    }

    private var workedTimeInput: Binding<String> {
        Binding(
            get: { formatWorkedTimeDigits(workedTimeDigits) },
            set: { newValue in
                workedTimeDigits = sanitizedWorkedTimeDigits(newValue)
            }
        )
    }

    private func sanitizedWorkedTimeDigits(_ raw: String) -> String {
        String(raw.filter(\.isNumber).suffix(9))
    }

    private func parseWorkedTimeDigits(_ digits: String) -> TimeInterval? {
        let cleaned = sanitizedWorkedTimeDigits(digits)
        guard !cleaned.isEmpty else {
            return 0
        }

        let padded = cleaned.count >= 6
            ? cleaned
            : String(repeating: "0", count: 6 - cleaned.count) + cleaned

        let secondsDigits = String(padded.suffix(2))
        let minutesDigits = String(padded.dropLast(2).suffix(2))
        let hoursDigits = String(padded.dropLast(4))

        guard let hours = Int(hoursDigits),
              let minutes = Int(minutesDigits),
              let seconds = Int(secondsDigits)
        else {
            return nil
        }

        return TimeInterval((hours * 3600) + (minutes * 60) + seconds)
    }

    private func formatWorkedTimeDigits(_ digits: String) -> String {
        let cleaned = sanitizedWorkedTimeDigits(digits)
        guard !cleaned.isEmpty else {
            return "0:00:00"
        }

        let padded = cleaned.count >= 6
            ? cleaned
            : String(repeating: "0", count: 6 - cleaned.count) + cleaned

        let secondsDigits = String(padded.suffix(2))
        let minutesDigits = String(padded.dropLast(2).suffix(2))
        let hoursDigits = String(padded.dropLast(4))
        let normalizedHours = String(Int(hoursDigits) ?? 0)
        return "\(normalizedHours):\(minutesDigits):\(secondsDigits)"
    }

    private func digitsForWorkedTime(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return "\(hours)\(String(format: "%02d%02d", minutes, seconds))"
    }

    private static let moneyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    private var historyCard: some View {
        ExpandablePanel(isExpanded: $historyExpanded) {
            cardHeader(title: "Daily Log", status: "Auto resets each day", emphasized: false, isExpanded: historyExpanded)
        } content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.dailySummaries) { summary in
                            Button {
                                model.openDailySummary(summary)
                            } label: {
                                HistoryRow(summary: summary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 150)
        }
    }

    private var logCard: some View {
        ExpandablePanel(isExpanded: $logExpanded) {
            cardHeader(title: "Actions", status: "\(model.logEntries.count) entries", emphasized: false, isExpanded: logExpanded)
        } content: {
                HStack {
                    Spacer()
                    Button("Clear") {
                        model.clearLog()
                    }
                    .buttonStyle(TextPanelButtonStyle(theme: theme))
                    .disabled(model.logEntries.isEmpty)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if model.logEntries.isEmpty {
                            Text("Pause, resume, or reset to add entries.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(model.logEntries) { entry in
                                SimpleLogRow(entry: entry)
                            }
                        }
                    }
                }
                .frame(maxHeight: 112)
        }
    }

    @ViewBuilder
    private func cardHeader(title: String, status: String, emphasized: Bool, isExpanded: Bool) -> some View {
        HStack {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondary)
            SectionLabel(title)
            Spacer()
            Text(status)
                .font(.caption.weight(.semibold))
                .foregroundStyle(emphasized ? theme.primary : theme.secondary)
        }
    }

    @ViewBuilder
    private func subSectionHeader(title: String, status: String, emphasized: Bool) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondary)
            Spacer()
            Text(status)
                .font(.caption.weight(.semibold))
                .foregroundStyle(emphasized ? theme.primary : theme.secondary)
        }
    }

    private var appearanceSymbol: String {
        switch model.appearanceMode {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.fill"
        }
    }

    private func nextAppearanceMode(after mode: AppModel.AppearanceMode) -> AppModel.AppearanceMode {
        switch mode {
        case .system:
            return .light
        case .light:
            return .dark
        case .dark:
            return .system
        }
    }

    private func topBarModePreview(_ mode: AppModel.MenuBarDisplayMode) -> String {
        switch mode {
        case .elapsed:
            return model.elapsedText
        case .earnings:
            return model.currentEarningsText
        case .typingTime:
            return model.typingTimeText
        case .charactersPerMinute:
            return "\(model.typingCharactersPerMinuteText) CPM"
        case .wordsPerMinute:
            return "\(model.typingWordsPerMinuteText) WPM"
        case .characters:
            return model.typingCharacterCountText
        case .mouseDistance:
            return model.mouseDistanceText
        case .aiTotalTokens:
            return model.aiCombinedTokensText
        case .aiTokensPerSecond:
            return model.aiTokensPerSecondText
        case .aiTokensToday:
            return model.aiTodayTokensText
        case .diskRead:
            return model.diskReadText
        case .diskWritten:
            return model.diskWrittenText
        case .diskWear:
            return model.diskWearText
        case .iconOnly:
            return "icon"
        }
    }

    private var theme: PanelTheme {
        PanelTheme(colorScheme: colorScheme)
    }
}

struct DailySummaryPanelView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let summary = model.selectedDailySummary {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(summary.dayTitle)
                                .font(.title2.weight(.bold))
                            Text(summary.dayStart.formatted(date: .complete, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(theme.secondary)
                        }

                        dayCard(title: "Work") {
                            detailRow("Worked", summary.workedText)
                            detailRow("Pay", summary.earningsText)
                            detailRow("Hourly", summary.hourlyRateText)
                            detailRow("Paused", summary.pausedText)
                            detailRow("Longest run", summary.longestRunText)
                            detailRow("Active share", summary.activeShareText)
                            detailRow("Pauses", "\(summary.pauseCount)")
                            detailRow("Resets", "\(summary.resetCount)")
                        }

                        dayCard(title: "Input") {
                            detailRow("Typing time", summary.typingTimeText)
                            detailRow("Characters", summary.typingCharacterCountText)
                            detailRow("WPM", summary.typingWordsPerMinuteText)
                            detailRow("Mouse travel", summary.mouseDistanceText)
                            detailRow("Mouse time", summary.mouseMoveTimeText)
                        }

                        dayCard(title: "Wispr Flow") {
                            detailRow("Words", summary.wisprWordsTodayText)
                            detailRow("Dictation", summary.wisprDictationTimeText)
                            detailRow("Clips", summary.wisprClipsTodayText)
                        }

                        HStack {
                            Spacer()
                            Button("Close") {
                                model.hideDailySummary()
                            }
                            .buttonStyle(SecondaryPanelButtonStyle(theme: theme))
                        }
                    }
                    .padding(14)
                }
                .background(theme.windowBackground)
                .foregroundStyle(theme.primary)
            } else {
                VStack(spacing: 10) {
                    Text("No day selected")
                        .font(.headline)
                    Button("Close") {
                        model.hideDailySummary()
                    }
                    .buttonStyle(SecondaryPanelButtonStyle(theme: theme))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.windowBackground)
                .foregroundStyle(theme.primary)
            }
        }
        .frame(minWidth: 390, idealWidth: 430, minHeight: 460, idealHeight: 560, maxHeight: .infinity, alignment: .topLeading)
        .preferredColorScheme(model.preferredColorScheme)
    }

    private func dayCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondary)
            content()
        }
        .panelCard(theme: theme)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.primary)
        }
    }

    private var theme: PanelTheme {
        PanelTheme(colorScheme: colorScheme)
    }
}

private struct PanelTheme {
    let colorScheme: ColorScheme

    var windowBackground: Color { colorScheme == .dark ? .black : .white }
    var primary: Color { colorScheme == .dark ? .white : .black }
    var secondary: Color { colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.66) }
    var tertiary: Color { colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.45) }
    var cardFill: Color { colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05) }
    var mutedFill: Color { colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.1) }
    var stroke: Color { colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.14) }
    var accent: Color { colorScheme == .dark ? .white : .black }
    var inversePrimary: Color { colorScheme == .dark ? .black : .white }
}

private struct CompactMetric: View {
    let label: String
    let value: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.66))
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatRow: View {
    let label: String
    let value: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.66))

            Spacer(minLength: 8)

            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

private struct HistoryRow: View {
    let summary: DailyWorkSummary
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.dayTitle)
                    .font(.subheadline.weight(.semibold))
                Text("\(summary.workedText) • \(summary.mouseDistanceText)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.66))
            }

            Spacer(minLength: 8)

            Text(summary.earningsText)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct SimpleLogRow: View {
    let entry: TimerLogEntry
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(entry.title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.66))
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.occurredAt.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                Text("Timer \(AppModel.formatElapsed(entry.elapsedSnapshot))")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.66))
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct SectionLabel: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.66))
    }
}

private struct PrimaryPanelButtonStyle: ButtonStyle {
    let theme: PanelTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(theme.inversePrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(configuration.isPressed ? theme.accent.opacity(0.82) : theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SecondaryPanelButtonStyle: ButtonStyle {
    let theme: PanelTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(theme.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(configuration.isPressed ? theme.mutedFill : theme.cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(theme.stroke, lineWidth: 1)
            )
    }
}

private struct MiniPanelButtonStyle: ButtonStyle {
    let theme: PanelTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(configuration.isPressed ? theme.mutedFill : theme.cardFill)
            .overlay(
                Capsule()
                    .stroke(theme.stroke, lineWidth: 1)
            )
    }
}

private struct TextPanelButtonStyle: ButtonStyle {
    let theme: PanelTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(configuration.isPressed ? theme.accent.opacity(0.72) : theme.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
    }
}

private struct SelectionChipButtonStyle: ButtonStyle {
    let theme: PanelTheme
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? theme.inversePrimary : theme.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? theme.accent.opacity(configuration.isPressed ? 0.82 : 1)
                            : theme.cardFill.opacity(configuration.isPressed ? 0.85 : 1)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? theme.accent : theme.stroke, lineWidth: 1)
            )
    }
}

private struct IconPanelButtonStyle: ButtonStyle {
    let theme: PanelTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.primary)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? theme.mutedFill : theme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.stroke, lineWidth: 1)
            )
    }
}

private struct ExpandablePanel<Header: View, Content: View>: View {
    @Binding var isExpanded: Bool
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                header()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .panelCard(theme: PanelTheme(colorScheme: colorScheme))
    }
}

private struct AIRateSparkline: View {
    let values: [Double]
    let trailingLabel: String
    @State private var hoveredIndex: Int?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let maxValue = graphScaleMax(for: values)
            let points = values.enumerated().map { index, value in
                CGPoint(
                    x: xPosition(for: index, width: geometry.size.width, count: values.count),
                    y: yPosition(for: value, height: geometry.size.height, maxValue: maxValue)
                )
            }

            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))

                if let hoveredIndex,
                   hoveredIndex < points.count {
                    let hoveredPoint = points[hoveredIndex]

                    Path { path in
                        path.move(to: CGPoint(x: hoveredPoint.x, y: 4))
                        path.addLine(to: CGPoint(x: hoveredPoint.x, y: geometry.size.height - 8))
                    }
                    .stroke(
                        colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )

                    Circle()
                        .fill(colorScheme == .dark ? Color.white : Color.black)
                        .frame(width: 6, height: 6)
                        .position(hoveredPoint)
                }

                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: geometry.size.height))
                    path.addLine(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                    if let last = points.last {
                        path.addLine(to: CGPoint(x: last.x, y: geometry.size.height))
                    }
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            (colorScheme == .dark ? Color.white : Color.black).opacity(0.18),
                            (colorScheme == .dark ? Color.white : Color.black).opacity(0.03),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(colorScheme == .dark ? Color.white : Color.black, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                if let hoveredIndex,
                   hoveredIndex < values.count {
                    hoverLabel(for: hoveredIndex)
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }

                HStack {
                    Text("0")
                    Spacer()
                    Text(trailingLabel)
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.66))
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case let .active(location):
                    hoveredIndex = hoveredIndex(for: location.x, width: geometry.size.width, count: values.count)
                case .ended:
                    hoveredIndex = nil
                }
            }
        }
    }

    @ViewBuilder
    private func hoverLabel(for index: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(AppModel.formatTokensPerSecond(values[index]))/s")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
            Text(relativeTimeText(for: index, count: values.count))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.66))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(colorScheme == .dark ? Color.black.opacity(0.96) : Color.white.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.14), lineWidth: 1)
        )
    }

    private func xPosition(for index: Int, width: CGFloat, count: Int) -> CGFloat {
        guard count > 1 else { return width / 2 }
        return CGFloat(index) / CGFloat(count - 1) * width
    }

    private func hoveredIndex(for x: CGFloat, width: CGFloat, count: Int) -> Int? {
        guard count > 0, width > 0 else {
            return nil
        }

        let normalized = min(max(x / width, 0), 1)
        return Int((normalized * CGFloat(count - 1)).rounded())
    }

    private func graphScaleMax(for values: [Double]) -> Double {
        let positiveValues = values.filter { $0 > 0 }
        guard !positiveValues.isEmpty else { return 0.01 }
        let sorted = positiveValues.sorted()
        let percentileIndex = min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.9))
        let percentileValue = sorted[percentileIndex]
        return max(percentileValue, positiveValues.max() ?? 0, 0.01) > percentileValue * 2
            ? max(percentileValue, 0.01)
            : max(sorted.last ?? percentileValue, 0.01)
    }

    private func yPosition(for value: Double, height: CGFloat, maxValue: Double) -> CGFloat {
        let normalized = min(max(value / maxValue, 0), 1)
        let topPadding: CGFloat = 4
        let bottomPadding: CGFloat = 8
        let drawableHeight = max(1, height - topPadding - bottomPadding)
        return topPadding + (1 - normalized) * drawableHeight
    }

    private func relativeTimeText(for index: Int, count: Int) -> String {
        guard count > 0 else {
            return "Now"
        }

        let minutesAgo = max(0, count - 1 - index)
        if minutesAgo == 0 {
            return "Now"
        }

        let sampleDate = Date().addingTimeInterval(TimeInterval(-minutesAgo * 60))
        return Self.hoverTimeFormatter.string(from: sampleDate)
    }

    private static let hoverTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

private extension View {
    func panelCard(theme: PanelTheme) -> some View {
        self
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(theme.stroke, lineWidth: 1)
            )
    }
}
