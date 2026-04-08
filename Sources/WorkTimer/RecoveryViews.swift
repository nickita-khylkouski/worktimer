import SwiftUI

struct TimerPanelView: View {
    @Bindable var model: AppModel
    @State private var hourlyRateInput = ""
    @State private var workedTimeDigits = ""
    @State private var isEditingWorkedTime = false
    @FocusState private var hourlyRateFieldFocused: Bool
    @FocusState private var workedTimeFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                headerCard
                payCard
                if model.shouldShowOnboardingCard {
                    onboardingCard
                }
                topBarCard
                controlsRow
                typingCard
                aiCard
                diskCard
                historyCard
                logCard
            }
            .padding(12)
        }
        .frame(width: 332, height: 438, alignment: .topLeading)
        .background(Color.black)
        .foregroundStyle(.white)
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
                Text(model.onboardingStatusLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                Button("Hide") {
                    model.dismissOnboarding()
                }
                .buttonStyle(TextPanelButtonStyle())
            }

            Text("New users should follow this once: move the app into Applications, grant access from here, then confirm login-item approval if macOS asks.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.56))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(model.onboardingChecklist.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text(item.complete ? "Done" : "Next")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(item.complete ? .black : .white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(item.complete ? Color.white : Color.white.opacity(0.08))
                            .clipShape(Capsule())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 12, weight: .semibold))
                            Text(item.detail)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.56))
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                if !model.isInstalledInApplications {
                    Button("Applications") {
                        model.openApplicationsFolder()
                    }
                    .buttonStyle(SecondaryPanelButtonStyle())
                }

                if model.needsTypingPermissions {
                    Button("Grant Access") {
                        model.requestTypingPermissions()
                    }
                    .buttonStyle(SecondaryPanelButtonStyle())
                }

                if model.launchAtLoginStatus != .enabled {
                    Button("Login Items") {
                        model.openLoginItemsSettings()
                    }
                    .buttonStyle(TextPanelButtonStyle())
                }
            }
        }
        .panelCard()
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WorkTimer")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.56))

                    HStack(alignment: .center, spacing: 8) {
                        Text(model.elapsedText)
                            .font(.system(size: 26, weight: .bold, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        Button {
                            toggleWorkedTimeEditor()
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isEditingWorkedTime ? .black : .white.opacity(0.82))
                                .frame(width: 24, height: 24)
                                .background(isEditingWorkedTime ? Color.white : Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(
                                            isEditingWorkedTime ? Color.white : Color.white.opacity(0.08),
                                            lineWidth: 1
                                        )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    if isEditingWorkedTime {
                        HStack(spacing: 8) {
                            TextField("h:mm:ss", text: workedTimeInput)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .focused($workedTimeFieldFocused)
                                .onSubmit {
                                    saveWorkedTimeEdit()
                                }

                            Button("Set") {
                                saveWorkedTimeEdit()
                            }
                            .buttonStyle(MiniPanelButtonStyle())
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.045))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }

                Spacer(minLength: 8)

                Button {
                    model.resetTimer()
                } label: {
                    Text("Reset")
                }
                .buttonStyle(MiniPanelButtonStyle())
            }

            HStack(spacing: 8) {
                CompactMetric(label: "Status", value: model.stateLabel)
                CompactMetric(label: "Today", value: model.cumulativeRunText)
                CompactMetric(label: "Pay", value: model.currentEarningsText)
            }
        }
        .panelCard()
    }

    private var controlsRow: some View {
        HStack(spacing: 8) {
            Button(model.isRunning ? "Pause" : "Resume") {
                model.toggleRunning()
            }
            .buttonStyle(PrimaryPanelButtonStyle())

            Button("Hide") {
                model.hideControlPanel()
            }
            .buttonStyle(SecondaryPanelButtonStyle())

            Spacer(minLength: 0)

            Button("Copy") {
                model.copySummary()
            }
            .buttonStyle(TextPanelButtonStyle())
        }
    }

    private var payCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Pay")

            VStack(alignment: .leading, spacing: 8) {
                Text("Per hour")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.56))

                HStack(spacing: 6) {
                    Text("$")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))

                    TextField("0", text: $hourlyRateInput)
                        .textFieldStyle(.plain)
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
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
        .panelCard()
    }

    private var topBarCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Top bar")

            LazyVGrid(columns: topBarModeColumns, spacing: 8) {
                ForEach(AppModel.MenuBarDisplayMode.allCases, id: \.self) { mode in
                    Button {
                        model.menuBarDisplayMode = mode
                    } label: {
                        Text(mode.title)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TopBarModeButtonStyle(isSelected: model.menuBarDisplayMode == mode))
                }
            }

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
        .panelCard()
    }

    private var aiCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("AI Usage")
                Spacer()
                Text(model.aiStatusLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(model.aiUsageAvailable ? .white : .white.opacity(0.56))
            }

            Text(
                model.aiUsageAvailable
                    ? "Live Codex and Claude usage pulled from local usage snapshots and session logs."
                    : "AI usage is unavailable until WorkTimer can find the local usage-data snapshots and session folders."
            )
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.56))

            VStack(spacing: 8) {
                StatRow(label: "Combined", value: model.aiCombinedTokensText)
                StatRow(label: "Today", value: model.aiTodayTokensText)
                StatRow(label: "Rate", value: model.aiTokensPerSecondText)
                StatRow(label: "Codex", value: model.aiCodexTokensText)
                StatRow(label: "Claude", value: model.aiClaudeTokensText)
                StatRow(label: "Watched files", value: model.aiWatchedFilesText)
            }
        }
        .panelCard()
    }

    private var diskCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Disk")
                Spacer()
                Text(model.diskStatusLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(model.diskHealthAvailable ? .white : .white.opacity(0.56))
            }

            Text(
                model.diskHealthAvailable
                    ? "Internal SSD counters from diskutil SMART fields."
                    : "Disk counters are unavailable on this Mac right now."
            )
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.56))

            VStack(spacing: 8) {
                StatRow(label: "Read", value: model.diskReadText)
                StatRow(label: "Written", value: model.diskWrittenText)
                StatRow(label: "Read cmds", value: model.diskHostReadCommandsText)
                StatRow(label: "Write cmds", value: model.diskHostWriteCommandsText)
                StatRow(label: "Wear", value: model.diskWearText)
                StatRow(label: "Power on", value: model.diskPowerOnText)
            }
        }
        .panelCard()
    }

    private var typingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Input")
                Spacer()
                Text(model.typingStatusLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(model.isTyping ? .white : .white.opacity(0.6))
            }

            Text(model.typingStatusDetail)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.56))

            if !model.isInstalledInApplications {
                Button("Open Applications Folder") {
                    model.openApplicationsFolder()
                }
                .buttonStyle(SecondaryPanelButtonStyle())
            }

            if model.needsTypingPermissions {
                HStack(spacing: 8) {
                    Button("Request + Open Settings") {
                        model.requestTypingPermissions()
                    }
                    .buttonStyle(SecondaryPanelButtonStyle())

                    Button("Open Both Panes") {
                        model.openTypingPermissionPanes()
                    }
                    .buttonStyle(TextPanelButtonStyle())
                }

                Text("WorkTimer retries automatically. If stats still do not start after a few seconds, reopen the app once.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.46))
            }

            VStack(spacing: 8) {
                StatRow(label: "Typing time", value: model.typingTimeText)
                StatRow(label: "Characters", value: model.typingCharacterCountText)
                StatRow(label: "CPM", value: model.typingCharactersPerMinuteText)
                StatRow(label: "WPM", value: model.typingWordsPerMinuteText)
            }

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            HStack {
                Text("Mouse")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.56))
                Spacer()
                Text(model.mouseStatusLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(model.isMouseMoving ? .white : .white.opacity(0.6))
            }

            Text("Tracks how far the cursor travels across mouse moves and drags during the day.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.56))

            VStack(spacing: 8) {
                StatRow(label: "Travel", value: model.mouseDistanceText)
                StatRow(label: "Move time", value: model.mouseMoveTimeText)
                StatRow(label: "Travel / min", value: model.mouseDistancePerMinuteText)
            }

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            HStack {
                Text("Wispr Flow")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.56))
                Spacer()
                Text(model.wisprFlowStatusLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(model.wisprFlowAvailable ? .white : .white.opacity(0.6))
            }

            Text(
                model.wisprFlowAvailable
                    ? "Reads today’s dictation totals from the local Wispr Flow history database."
                    : "Wispr Flow stats show up automatically when a local flow.sqlite database is available."
            )
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.56))

            VStack(spacing: 8) {
                StatRow(label: "Words today", value: model.wisprWordsTodayText)
                StatRow(label: "Dictation time", value: model.wisprDictationDurationTodayText)
                StatRow(label: "Clips today", value: model.wisprClipsTodayText)
            }
        }
        .panelCard()
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

    private var topBarModeColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
        ]
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Daily Log")
                Spacer()
                Text("Auto resets each day")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.dailySummaries) { summary in
                        HistoryRow(summary: summary)
                    }
                }
            }
            .frame(maxHeight: 150)
        }
        .panelCard()
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Actions")
                Spacer()
                Button("Clear") {
                    model.clearLog()
                }
                .buttonStyle(TextPanelButtonStyle())
                .disabled(model.logEntries.isEmpty)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if model.logEntries.isEmpty {
                        Text("Pause, resume, or reset to add entries.")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.56))
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
        .panelCard()
    }
}

private struct CompactMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.46))
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

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))

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

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.dayTitle)
                    .font(.system(size: 12, weight: .semibold))
                Text("\(summary.workedText) • \(summary.mouseDistanceText)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.58))
            }

            Spacer(minLength: 8)

            Text(summary.earningsText)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct SimpleLogRow: View {
    let entry: TimerLogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(entry.title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.68))
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.occurredAt.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                Text("Timer \(AppModel.formatElapsed(entry.elapsedSnapshot))")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.48))
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.56))
    }
}

private struct PrimaryPanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(configuration.isPressed ? Color.white.opacity(0.82) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SecondaryPanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(configuration.isPressed ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct MiniPanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(configuration.isPressed ? Color.white.opacity(0.14) : Color.white.opacity(0.06))
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(Capsule())
    }
}

private struct TextPanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(configuration.isPressed ? .white.opacity(0.68) : .white.opacity(0.84))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
    }
}

private struct TopBarModeButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isSelected ? .black : .white)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(backgroundColor(configuration: configuration))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.white : Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func backgroundColor(configuration: Configuration) -> Color {
        if configuration.isPressed {
            return isSelected ? Color.white.opacity(0.82) : Color.white.opacity(0.14)
        }
        return isSelected ? .white : Color.white.opacity(0.05)
    }
}

private struct AIRateSparkline: View {
    let values: [Double]
    let trailingLabel: String
    @State private var hoveredIndex: Int?

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
                    .fill(Color.white.opacity(0.04))

                if let hoveredIndex,
                   hoveredIndex < points.count {
                    let hoveredPoint = points[hoveredIndex]

                    Path { path in
                        path.move(to: CGPoint(x: hoveredPoint.x, y: 4))
                        path.addLine(to: CGPoint(x: hoveredPoint.x, y: geometry.size.height - 8))
                    }
                    .stroke(
                        Color.white.opacity(0.34),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )

                    Circle()
                        .fill(Color.white)
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
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.02)],
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
                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

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
                .foregroundStyle(.white.opacity(0.34))
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
                .foregroundStyle(.black)
            Text(relativeTimeText(for: index, count: values.count))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.black.opacity(0.72))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
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
    func panelCard() -> some View {
        self
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color.white.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
