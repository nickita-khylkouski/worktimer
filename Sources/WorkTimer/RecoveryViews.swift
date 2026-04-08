import SwiftUI

struct TimerPanelView: View {
    @Bindable var model: AppModel
    @State private var hourlyRateInput = ""
    @State private var workedTimeDigits = ""
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
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WorkTimer")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.56))

                    Text(model.elapsedText)
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
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

            VStack(alignment: .leading, spacing: 6) {
                Text("Edit today")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.56))

                HStack(spacing: 8) {
                    TextField("h:mm:ss", text: workedTimeInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .focused($workedTimeFieldFocused)
                        .onSubmit {
                            commitWorkedTimeInput()
                        }

                    Button("Set") {
                        commitWorkedTimeInput()
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

                Text("Type digits. The separators stay in place.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.42))
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
                        .frame(height: 42)
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
        }
    }

    private func xPosition(for index: Int, width: CGFloat, count: Int) -> CGFloat {
        guard count > 1 else { return width / 2 }
        return CGFloat(index) / CGFloat(count - 1) * width
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
