import AppKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    enum MenuBarDisplayMode: String, CaseIterable {
        case elapsed
        case earnings
        case typingTime
        case charactersPerMinute
        case wordsPerMinute
        case characters
        case mouseDistance
        case aiTotalTokens
        case aiTokensPerSecond
        case aiTokensToday
        case diskRead
        case diskWritten
        case diskWear
        case iconOnly

        var title: String {
            switch self {
            case .elapsed:
                return "Timer"
            case .earnings:
                return "Money"
            case .typingTime:
                return "Type Time"
            case .charactersPerMinute:
                return "CPM"
            case .wordsPerMinute:
                return "WPM"
            case .characters:
                return "Chars"
            case .mouseDistance:
                return "Mouse"
            case .aiTotalTokens:
                return "AI Total"
            case .aiTokensPerSecond:
                return "AI /s"
            case .aiTokensToday:
                return "AI Today"
            case .diskRead:
                return "Disk Read"
            case .diskWritten:
                return "Disk Write"
            case .diskWear:
                return "SSD Wear"
            case .iconOnly:
                return "Icon"
            }
        }
    }

    private enum DefaultsKey {
        static let menuBarDisplayMode = "menuBarDisplayMode"
        static let hourlyRate = "hourlyRate"
        static let dayHistory = "dayHistory"
        static let dismissedOnboarding = "dismissedOnboarding"
        static let aiUsageSummaryCache = "aiUsageSummaryCache"
    }

    private static let defaultHourlyRate: Double = 50

    private struct ActiveTypingSession {
        let startedAt: Date
        let context: CaptureContext
        var lastInputAt: Date
        var characterCount: Int
    }

    private struct ActiveMouseSession {
        let startedAt: Date
        var lastMovedAt: Date
        var distance: Double
    }

    var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            persistSettings()
            refreshStatusItem()
        }
    }

    var hourlyRate: Double {
        didSet {
            if hourlyRate < 0 {
                hourlyRate = 0
                return
            }

            persistSettings()
            refreshStatusItem()
            persistHistory()
        }
    }

    private(set) var isRunning: Bool
    private(set) var logEntries: [TimerLogEntry] = []
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var resetCount = 0
    private(set) var launchedAt: Date
    private(set) var currentTime: Date
    private(set) var sessionRunDurations: [TimeInterval] = []
    private(set) var totalPausedDuration: TimeInterval = 0
    private(set) var longestRunDuration: TimeInterval = 0
    private(set) var lastResetElapsed: TimeInterval?
    private(set) var dayHistory: [DailyWorkSummary]
    private(set) var typingPermissionState: CapturePermissionState = .unknown
    private(set) var typingStoredSummary: TypingSummary = .zero
    private(set) var mouseStoredSummary: MouseSummary = .zero
    private(set) var aiUsageSummary: AIUsageSummary = .zero
    private(set) var aiUsageAvailable = false
    private(set) var diskHealthSummary: DiskHealthSummary = .zero
    private(set) var diskHealthAvailable = false
    private(set) var wisprFlowSummary: WisprFlowSummary = .zero
    private(set) var wisprFlowAvailable = false
    private(set) var launchAtLoginStatus: LaunchAtLoginManager.StatusSummary = .unavailable

    let recoveryWindowManager = RecoveryWindowManager()

    private let statusItemController: StatusItemController?
    private let calendar = Calendar.autoupdatingCurrent
    private let typingCaptureService = TypingCaptureService()
    private let mouseCaptureService = MouseCaptureService()
    private let aiUsageMonitor = AIUsageMonitor()
    private let diskHealthMonitor = DiskHealthMonitor()
    private let wisprFlowMonitor = WisprFlowMonitor()
    private let typingStore: TypingStore?

    private var tickerTask: Task<Void, Never>?
    private var isStarted = false
    private var accumulatedElapsed: TimeInterval = 0
    private var runningSince: Date?
    private var pausedSince: Date?
    private var currentDayStart: Date
    private var activeTypingSession: ActiveTypingSession?
    private var activeMouseSession: ActiveMouseSession?
    private var lastTypingCaptureRetryAt: Date?
    private var lastAIUsageRefreshRequestAt = Date.distantPast
    private var lastDiskHealthRefreshRequestAt = Date.distantPast
    private var lastWisprFlowRefreshRequestAt = Date.distantPast
    private var hasCachedAIUsageSummary = false

    private let typingIdleThreshold: TimeInterval = 5
    private let mouseIdleThreshold: TimeInterval = 2
    private let typingCaptureRetryInterval: TimeInterval = 5
    private let aiUsageRefreshInterval: TimeInterval = 3
    private let diskHealthRefreshInterval: TimeInterval = 60
    private let wisprFlowRefreshInterval: TimeInterval = 30
    private let liveTickInterval: Duration = .milliseconds(250)
    private var dismissedOnboarding = false

    init(now: Date = .now, installsStatusItem: Bool = true, typingDatabaseURL: URL? = nil) {
        let typingStore = try? Self.makeTypingStore(enabled: installsStatusItem, databaseURL: typingDatabaseURL)
        let storedMode = (try? typingStore?.stringSetting(for: DefaultsKey.menuBarDisplayMode))
            ?? UserDefaults.standard.string(forKey: DefaultsKey.menuBarDisplayMode)
        let storedHourlyRate = (try? typingStore?.doubleSetting(for: DefaultsKey.hourlyRate))
            ?? ((UserDefaults.standard.object(forKey: DefaultsKey.hourlyRate) != nil)
                ? UserDefaults.standard.double(forKey: DefaultsKey.hourlyRate)
                : Self.defaultHourlyRate)
        let storedHistory = (try? typingStore?.loadDailySummaries()) ?? nil
        let dismissedOnboarding = UserDefaults.standard.bool(forKey: DefaultsKey.dismissedOnboarding)
        let initialMode = MenuBarDisplayMode(rawValue: storedMode ?? "") ?? .elapsed
        let initialDayStart = Calendar.autoupdatingCurrent.startOfDay(for: now)
        let statusItemController = installsStatusItem ? StatusItemController() : nil

        self.menuBarDisplayMode = initialMode
        self.hourlyRate = max(0, storedHourlyRate)
        self.isRunning = true
        self.launchedAt = initialDayStart
        self.currentTime = now
        self.dayHistory = (storedHistory?.isEmpty == false) ? (storedHistory ?? []) : Self.loadLegacyHistory()
        self.currentDayStart = initialDayStart
        self.runningSince = now
        self.statusItemController = statusItemController
        self.typingStore = typingStore
        self.dismissedOnboarding = dismissedOnboarding
        self.launchAtLoginStatus = installsStatusItem ? LaunchAtLoginManager.currentStatus() : .unavailable
        if let cachedAIUsageSummary = Self.loadCachedAIUsageSummary(from: typingStore) {
            self.aiUsageSummary = cachedAIUsageSummary
            self.aiUsageAvailable = true
            self.hasCachedAIUsageSummary = true
        }
        if let typingStore {
            self.typingStoredSummary = (try? typingStore.typingSummary(from: initialDayStart, to: now)) ?? .zero
            self.typingPermissionState = .ready
        }

        if let session = (try? typingStore?.loadSession()) ?? Self.loadLegacySession() {
            restore(from: session, now: now)
        }
        DebugTrace.log("AppModel init installsStatusItem=\(installsStatusItem) mode=\(initialMode.rawValue)")

        if let statusItemController {
            statusItemController.onLeftClick = { [weak self] in
                Task { @MainActor in
                    self?.toggleRunning()
                }
            }
            statusItemController.onDoubleLeftClick = { [weak self, weak statusItemController] in
                Task { @MainActor in
                    self?.openControlPanel(relativeTo: statusItemController?.button)
                }
            }
            statusItemController.onRightClick = { [weak self, weak statusItemController] in
                Task { @MainActor in
                    self?.openControlPanel(relativeTo: statusItemController?.button)
                }
            }
        }

        typingCaptureService.onInput = { [weak self] input in
            Task { @MainActor in
                self?.recordTypingInput(input, at: .now)
            }
        }
        typingCaptureService.onHotKey = { [weak self] in
            Task { @MainActor in
                self?.openControlPanel()
            }
        }
        mouseCaptureService.onSample = { [weak self] sample in
            Task { @MainActor in
                self?.recordMouseMovement(sample, at: .now)
            }
        }
        aiUsageMonitor.onAvailabilityChange = { [weak self] isAvailable in
            Task { @MainActor in
                guard let self else { return }
                self.aiUsageAvailable = isAvailable || self.hasCachedAIUsageSummary
                self.refreshStatusItem()
            }
        }
        aiUsageMonitor.onSummary = { [weak self] summary in
            Task { @MainActor in
                guard let self else { return }
                self.aiUsageSummary = Self.mergedAIUsageSummary(
                    current: self.aiUsageSummary,
                    incoming: summary
                )
                self.aiUsageAvailable = true
                self.hasCachedAIUsageSummary = true
                self.persistCachedAIUsageSummary(self.aiUsageSummary)
                self.refreshStatusItem()
            }
        }
        diskHealthMonitor.onAvailabilityChange = { [weak self] isAvailable in
            Task { @MainActor in
                self?.diskHealthAvailable = isAvailable
                self?.refreshStatusItem()
            }
        }
        diskHealthMonitor.onSummary = { [weak self] summary in
            Task { @MainActor in
                self?.diskHealthSummary = summary
                self?.refreshStatusItem()
            }
        }
        wisprFlowMonitor.onAvailabilityChange = { [weak self] isAvailable in
            Task { @MainActor in
                self?.wisprFlowAvailable = isAvailable
            }
        }
        wisprFlowMonitor.onSummary = { [weak self] summary in
            Task { @MainActor in
                self?.wisprFlowSummary = summary
            }
        }

        rollDayIfNeeded(now: now)
        currentTime = now
        persistSettings()
        persistHistory()
        persistSession()
    }

    var elapsedTime: TimeInterval {
        elapsed(at: currentTime)
    }

    var elapsedText: String {
        Self.formatElapsed(elapsedTime)
    }

    var cumulativeRunTime: TimeInterval {
        cumulativeRunTime(at: currentTime)
    }

    var cumulativeRunText: String {
        Self.formatElapsed(cumulativeRunTime)
    }

    var launchDurationText: String {
        Self.formatElapsed(currentTime.timeIntervalSince(launchedAt))
    }

    var totalPausedText: String {
        Self.formatElapsed(totalPausedTime)
    }

    var totalPausedTime: TimeInterval {
        let inFlightPause = (!isRunning && pausedSince != nil) ? currentPauseDuration(at: currentTime) : 0
        return totalPausedDuration + inFlightPause
    }

    var totalToggleCount: Int {
        pauseCount + resumeCount
    }

    var actionCount: Int {
        logEntries.count
    }

    var completedRunCount: Int {
        sessionRunDurations.count
    }

    var averageRunDuration: TimeInterval {
        guard !sessionRunDurations.isEmpty else {
            return 0
        }
        return sessionRunDurations.reduce(0, +) / Double(sessionRunDurations.count)
    }

    var averageRunText: String {
        Self.formatElapsed(averageRunDuration)
    }

    var longestRunText: String {
        Self.formatElapsed(longestRunDuration)
    }

    var currentPhaseDuration: TimeInterval {
        isRunning ? currentRunDuration(at: currentTime) : currentPauseDuration(at: currentTime)
    }

    var currentPhaseText: String {
        Self.formatElapsed(currentPhaseDuration)
    }

    var currentPhaseLabel: String {
        isRunning ? "Current Run" : "Current Pause"
    }

    var activeShare: Double {
        let sessionLength = currentTime.timeIntervalSince(currentDayStart)
        guard sessionLength > 0 else {
            return isRunning ? 1 : 0
        }
        return min(max(cumulativeRunTime / sessionLength, 0), 1)
    }

    var activeShareText: String {
        "\(Int((activeShare * 100).rounded()))%"
    }

    var sessionStartedText: String {
        Self.dayFormatter.string(from: currentDayStart)
    }

    var lastResetText: String {
        guard let lastResetElapsed else {
            return "None yet"
        }
        return Self.formatElapsed(lastResetElapsed)
    }

    var stateLabel: String {
        isRunning ? "Running" : "Paused"
    }

    var lastActionSummary: String {
        guard let last = logEntries.first else {
            return "No actions yet."
        }
        return "\(last.title) at \(Self.timestampFormatter.string(from: last.occurredAt))"
    }

    var currentEarnings: Double {
        (cumulativeRunTime / 3600) * hourlyRate
    }

    var currentEarningsText: String {
        Self.formatLiveCurrency(currentEarnings)
    }

    var hourlyRateText: String {
        Self.formatCurrency(hourlyRate) + "/hr"
    }

    var topBarText: String {
        switch menuBarDisplayMode {
        case .elapsed:
            return elapsedText
        case .earnings:
            return currentEarningsText
        case .typingTime:
            return typingTimeText
        case .charactersPerMinute:
            return typingCharactersPerMinuteText + " CPM"
        case .wordsPerMinute:
            return typingWordsPerMinuteText + " WPM"
        case .characters:
            return Self.formatCompactCount(typingSummary.characterCount)
        case .mouseDistance:
            return mouseDistanceText
        case .aiTotalTokens:
            return aiCombinedTokensText
        case .aiTokensPerSecond:
            return aiTokensPerSecondText
        case .aiTokensToday:
            return aiTodayTokensText
        case .diskRead:
            return diskReadText
        case .diskWritten:
            return diskWrittenText
        case .diskWear:
            return diskWearText
        case .iconOnly:
            return elapsedText
        }
    }

    var todaySummary: DailyWorkSummary {
        DailyWorkSummary(
            dayStart: currentDayStart,
            workedSeconds: cumulativeRunTime,
            earningsAmount: currentEarnings,
            pauseCount: pauseCount,
            resetCount: resetCount,
            mouseDistance: mouseSummary.distance
        )
    }

    var dailySummaries: [DailyWorkSummary] {
        var summaries = dayHistory.filter { !calendar.isDate($0.dayStart, inSameDayAs: currentDayStart) }
        summaries.insert(todaySummary, at: 0)
        return summaries.sorted { $0.dayStart > $1.dayStart }
    }

    var isTyping: Bool {
        guard let activeTypingSession else {
            return false
        }
        return currentTime.timeIntervalSince(activeTypingSession.lastInputAt) < typingIdleThreshold
    }

    var isMouseMoving: Bool {
        guard let activeMouseSession else {
            return false
        }
        return currentTime.timeIntervalSince(activeMouseSession.lastMovedAt) < mouseIdleThreshold
    }

    var typingStatusLabel: String {
        switch typingPermissionState {
        case .unknown:
            return "Checking"
        case .ready:
            return isTyping ? "Typing" : "Idle"
        case .missingAccessibility:
            return "Needs Accessibility"
        case .missingInputMonitoring:
            return "Needs Input Monitoring"
        case .failedToInstallTap:
            return "Tap Failed"
        }
    }

    var typingStatusDetail: String {
        if !isInstalledInApplications {
            return "Move WorkTimer.app into Applications before granting permissions. Running from Downloads or a translocated path can break permission persistence."
        }

        switch typingPermissionState {
        case .unknown:
            return "Preparing keyboard monitoring."
        case .ready:
            return "Typing time keeps short pauses under 5 seconds inside the same session."
        case .missingAccessibility:
            return "Enable Accessibility for WorkTimer, then reopen the app once."
        case .missingInputMonitoring:
            return "Enable Input Monitoring for WorkTimer, then reopen the app once."
        case .failedToInstallTap:
            return "WorkTimer could not install the keyboard listener. Reopen after turning on both privacy switches."
        }
    }

    var needsTypingPermissions: Bool {
        switch typingPermissionState {
        case .ready:
            return false
        case .unknown, .missingAccessibility, .missingInputMonitoring, .failedToInstallTap:
            return true
        }
    }

    var isInstalledInApplications: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    var typingSummary: TypingSummary {
        var duration = typingStoredSummary.duration
        var characters = typingStoredSummary.characterCount
        if let activeTypingSession {
            duration += activeTypingDuration(at: currentTime, for: activeTypingSession)
            characters += activeTypingSession.characterCount
        }
        return TypingSummary(duration: duration, characterCount: characters)
    }

    var typingTimeText: String {
        Self.formatElapsed(typingSummary.duration)
    }

    var typingCharacterCountText: String {
        "\(typingSummary.characterCount)"
    }

    var typingCharactersPerMinute: Double {
        let minutes = typingSummary.duration / 60
        guard minutes > 0 else {
            return 0
        }
        return Double(typingSummary.characterCount) / minutes
    }

    var typingCharactersPerMinuteText: String {
        "\(Int(typingCharactersPerMinute.rounded()))"
    }

    var typingWordsPerMinute: Double {
        typingCharactersPerMinute / 5
    }

    var typingWordsPerMinuteText: String {
        "\(Int(typingWordsPerMinute.rounded()))"
    }

    var mouseSummary: MouseSummary {
        var duration = mouseStoredSummary.duration
        var distance = mouseStoredSummary.distance
        if let activeMouseSession {
            duration += activeMouseDuration(at: currentTime, for: activeMouseSession)
            distance += activeMouseSession.distance
        }
        return MouseSummary(duration: duration, distance: distance)
    }

    var mouseMoveTimeText: String {
        Self.formatElapsed(mouseSummary.duration)
    }

    var mouseDistanceText: String {
        Self.formatDistance(mouseSummary.distance)
    }

    var mouseDistancePerMinute: Double {
        let minutes = mouseSummary.duration / 60
        guard minutes > 0 else {
            return 0
        }
        return mouseSummary.distance / minutes
    }

    var mouseDistancePerMinuteText: String {
        Self.formatDistance(mouseDistancePerMinute)
    }

    var mouseStatusLabel: String {
        isMouseMoving ? "Moving" : "Still"
    }

    var aiStatusLabel: String {
        aiUsageAvailable ? "Live" : "Unavailable"
    }

    var aiCombinedTokensText: String {
        guard aiUsageAvailable else { return "--" }
        return Self.formatCompactInt64(aiUsageSummary.combined.tokens)
    }

    var aiTodayTokensText: String {
        guard aiUsageAvailable else { return "--" }
        return Self.formatCompactInt64(aiUsageSummary.combined.todayTokens)
    }

    var aiTokensPerSecondText: String {
        guard aiUsageAvailable else { return "--" }
        let displayRate = Self.preferredAITokensPerSecondDisplay(for: aiUsageSummary)
        return "\(Self.formatTokensPerSecond(displayRate))/s"
    }

    var aiRateSeries: [Double] {
        Self.smoothedAISeries(aiUsageSummary.lastThirtyMinutesRateSeries)
    }

    var aiCodexTokensText: String {
        guard aiUsageAvailable else { return "--" }
        return Self.formatCompactInt64(aiUsageSummary.codex.tokens)
    }

    var aiClaudeTokensText: String {
        guard aiUsageAvailable else { return "--" }
        return Self.formatCompactInt64(aiUsageSummary.claude.tokens)
    }

    var aiWatchedFilesText: String {
        guard aiUsageAvailable else { return "--" }
        return "\(aiUsageSummary.watchedCodexFiles + aiUsageSummary.watchedClaudeFiles)"
    }

    var diskStatusLabel: String {
        diskHealthAvailable ? diskHealthSummary.smartStatus : "Unavailable"
    }

    var diskReadText: String {
        guard diskHealthAvailable else { return "--" }
        return diskHealthSummary.readText
    }

    var diskWrittenText: String {
        guard diskHealthAvailable else { return "--" }
        return diskHealthSummary.writtenText
    }

    var diskWearText: String {
        guard diskHealthAvailable else { return "--" }
        return diskHealthSummary.wearText
    }

    var diskHostReadCommandsText: String {
        guard diskHealthAvailable else { return "--" }
        return diskHealthSummary.hostReadCommandsText
    }

    var diskHostWriteCommandsText: String {
        guard diskHealthAvailable else { return "--" }
        return diskHealthSummary.hostWriteCommandsText
    }

    var diskPowerOnText: String {
        guard diskHealthAvailable else { return "--" }
        return diskHealthSummary.powerOnText
    }

    var shouldShowOnboardingCard: Bool {
        !dismissedOnboarding || !isInstalledInApplications || needsTypingPermissions || launchAtLoginStatus != .enabled
    }

    var onboardingStatusLabel: String {
        if !isInstalledInApplications {
            return "Needs Setup"
        }
        if needsTypingPermissions {
            return "Permissions"
        }
        if launchAtLoginStatus != .enabled {
            return "Login Item"
        }
        return "Ready"
    }

    var onboardingChecklist: [(title: String, detail: String, complete: Bool)] {
        [
            (
                title: "Move to Applications",
                detail: isInstalledInApplications
                    ? "WorkTimer is installed in Applications."
                    : "Move WorkTimer.app into Applications first so macOS keeps permissions stable.",
                complete: isInstalledInApplications
            ),
            (
                title: "Grant typing + mouse access",
                detail: needsTypingPermissions
                    ? typingStatusDetail
                    : "Accessibility and Input Monitoring are ready.",
                complete: !needsTypingPermissions
            ),
            (
                title: "Approve launch at login",
                detail: launchAtLoginStatus.detail,
                complete: launchAtLoginStatus == .enabled
            ),
        ]
    }

    var wisprFlowStatusLabel: String {
        wisprFlowAvailable ? "Live" : "Unavailable"
    }

    var wisprWordsTodayText: String {
        guard wisprFlowAvailable else { return "--" }
        return wisprFlowSummary.wordsTodayText
    }

    var wisprDictationDurationTodayText: String {
        guard wisprFlowAvailable else { return "--" }
        return wisprFlowSummary.dictationDurationTodayText
    }

    var wisprClipsTodayText: String {
        guard wisprFlowAvailable else { return "--" }
        return wisprFlowSummary.clipsTodayText
    }

    var showIconOnly: Bool {
        get { menuBarDisplayMode == .iconOnly }
        set { menuBarDisplayMode = newValue ? .iconOnly : .elapsed }
    }

    var summaryText: String {
        [
            "State: \(stateLabel)",
            "Today: \(sessionStartedText)",
            "Current timer: \(elapsedText)",
            "Today focus: \(cumulativeRunText)",
            "Paused time: \(totalPausedText)",
            "Longest run: \(longestRunText)",
            "Hourly rate: \(hourlyRateText)",
            "Current pay: \(currentEarningsText)",
            "Mouse travel: \(mouseDistanceText)",
            "Mouse time: \(mouseMoveTimeText)",
            "Wispr words today: \(wisprWordsTodayText)",
            "Active share: \(activeShareText)",
            "Resets: \(resetCount)",
            "Actions logged: \(actionCount)",
        ].joined(separator: "\n")
    }

    func installRecoveryPanel<Content: View>(@ViewBuilder content: () -> Content) {
        let controller = NSHostingController(rootView: content())
        recoveryWindowManager.install(contentViewController: controller)
    }

    func startIfNeeded() {
        guard !isStarted else {
            return
        }

        isStarted = true
        DebugTrace.log("AppModel startIfNeeded")
        updateCurrentTime(.now)
        startTypingCapture()
        startMouseCapture()
        aiUsageMonitor.start()
        diskHealthMonitor.start()
        wisprFlowMonitor.start()
        if statusItemController != nil {
            refreshLaunchAtLoginStatus()
        }

        tickerTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: liveTickInterval)
                await self.tick()
            }
        }

        if shouldAutoOpenOnLaunch {
            openControlPanel()
        }
    }

    func toggleRunning(at now: Date = .now) {
        rollDayIfNeeded(now: now)
        let elapsedBeforeToggle = elapsed(at: now)
        currentTime = now

        if isRunning {
            finalizeCurrentRun(at: now)
            accumulatedElapsed = elapsedBeforeToggle
            runningSince = nil
            isRunning = false
            pausedSince = now
            pauseCount += 1
            appendLog(.paused, occurredAt: now, elapsedSnapshot: elapsedBeforeToggle)
        } else {
            if let pausedSince {
                totalPausedDuration += max(0, now.timeIntervalSince(pausedSince))
                self.pausedSince = nil
            }
            runningSince = now
            isRunning = true
            resumeCount += 1
            appendLog(.resumed, occurredAt: now, elapsedSnapshot: elapsedBeforeToggle)
        }

        refreshStatusItem()
        persistSession()
    }

    func resetTimer(at now: Date = .now) {
        rollDayIfNeeded(now: now)
        let elapsedBeforeReset = elapsed(at: now)
        currentTime = now
        resetCount += 1
        lastResetElapsed = elapsedBeforeReset

        if isRunning {
            finalizeCurrentRun(at: now)
        } else if let pausedSince {
            totalPausedDuration += max(0, now.timeIntervalSince(pausedSince))
        }

        appendLog(.reset, occurredAt: now, elapsedSnapshot: elapsedBeforeReset)
        accumulatedElapsed = 0
        runningSince = isRunning ? now : nil
        pausedSince = isRunning ? nil : now
        refreshStatusItem()
        persistSession()
    }

    func resetAndStart(at now: Date = .now) {
        let shouldResume = !isRunning
        resetTimer(at: now)
        if shouldResume {
            toggleRunning(at: now)
        }
    }

    func clearLog() {
        logEntries.removeAll()
        persistSession()
    }

    func copySummary() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(summaryText, forType: .string)
    }

    func setWorkedDuration(_ duration: TimeInterval, at now: Date = .now) {
        rollDayIfNeeded(now: now)
        currentTime = now
        let targetDuration = max(0, duration)
        sessionRunDurations = targetDuration > 0 ? [targetDuration] : []
        longestRunDuration = targetDuration
        accumulatedElapsed = targetDuration
        if isRunning {
            runningSince = now
            pausedSince = nil
        } else {
            runningSince = nil
            pausedSince = now
        }
        persistHistory()
        persistSession()
        refreshStatusItem()
    }

    func openControlPanel(relativeTo button: NSStatusBarButton? = nil) {
        refreshTypingCapture(promptIfNeeded: false, revealPanelOnFailure: false)
        updateCurrentTime(.now)
        recoveryWindowManager.show(relativeTo: button)
    }

    func hideControlPanel() {
        recoveryWindowManager.hide()
    }

    func advance(to now: Date) {
        updateCurrentTime(now)
    }

    func requestTypingPermissions() {
        guard isInstalledInApplications else {
            openApplicationsFolder()
            return
        }
        refreshTypingCapture(promptIfNeeded: true, revealPanelOnFailure: true)
        openTypingPermissionPanes()
    }

    func openTypingPermissionPanes() {
        let accessibilityURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        let inputMonitoringURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(accessibilityURL)
        NSWorkspace.shared.open(inputMonitoringURL)
    }

    func openApplicationsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
    }

    func openSystemSettings() {
        let targetURL: URL
        switch typingPermissionState {
        case .missingAccessibility:
            targetURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .missingInputMonitoring:
            targetURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        case .unknown, .ready, .failedToInstallTap:
            targetURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        }

        NSWorkspace.shared.open(targetURL)
    }

    func openLoginItemsSettings() {
        let loginItemsURL = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
        NSWorkspace.shared.open(loginItemsURL)
    }

    func dismissOnboarding() {
        dismissedOnboarding = true
        UserDefaults.standard.set(true, forKey: DefaultsKey.dismissedOnboarding)
    }

    func recordTypingInput(_ input: TypingInput, at now: Date = .now) {
        guard typingPermissionState == .ready else {
            return
        }

        currentTime = now
        let characterIncrement = Self.characterIncrement(for: input.mutation)

        if let activeTypingSession {
            let contextChanged = activeTypingSession.context != input.context
            let exceededIdleThreshold = now.timeIntervalSince(activeTypingSession.lastInputAt) >= typingIdleThreshold

            if contextChanged || exceededIdleThreshold {
                commitTypingSession(activeTypingSession, at: now)
                self.activeTypingSession = nil
            }
        }

        if var activeTypingSession = activeTypingSession {
            activeTypingSession.lastInputAt = now
            activeTypingSession.characterCount += characterIncrement
            self.activeTypingSession = activeTypingSession
        } else {
            self.activeTypingSession = ActiveTypingSession(
                startedAt: now,
                context: input.context,
                lastInputAt: now,
                characterCount: characterIncrement
            )
        }
    }

    func recordMouseMovement(_ sample: MouseMovementSample, at now: Date = .now) {
        guard sample.estimatedMillimeters > 0 else {
            return
        }

        currentTime = now

        if let activeMouseSession,
           now.timeIntervalSince(activeMouseSession.lastMovedAt) >= mouseIdleThreshold {
            commitMouseSession(activeMouseSession, at: now)
            self.activeMouseSession = nil
        }

        if var activeMouseSession {
            activeMouseSession.lastMovedAt = now
            activeMouseSession.distance += sample.estimatedMillimeters
            self.activeMouseSession = activeMouseSession
        } else {
            self.activeMouseSession = ActiveMouseSession(
                startedAt: now,
                lastMovedAt: now,
                distance: sample.estimatedMillimeters
            )
        }
    }

    private func tick() async {
        let now = Date.now
        updateCurrentTime(now)
        if now.timeIntervalSince(lastAIUsageRefreshRequestAt) >= aiUsageRefreshInterval {
            lastAIUsageRefreshRequestAt = now
            aiUsageMonitor.tick()
        }
        if now.timeIntervalSince(lastDiskHealthRefreshRequestAt) >= diskHealthRefreshInterval {
            lastDiskHealthRefreshRequestAt = now
            diskHealthMonitor.tick()
        }
        if now.timeIntervalSince(lastWisprFlowRefreshRequestAt) >= wisprFlowRefreshInterval {
            lastWisprFlowRefreshRequestAt = now
            wisprFlowMonitor.tick()
        }
        if statusItemController != nil {
            refreshLaunchAtLoginStatus()
        }
    }

    private var shouldAutoOpenOnLaunch: Bool {
        !dismissedOnboarding
    }

    private func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = LaunchAtLoginManager.currentStatus()
    }

    private func updateCurrentTime(_ now: Date) {
        rollDayIfNeeded(now: now)
        currentTime = now
        retryTypingCaptureIfNeeded(at: now)
        finalizeTypingIfIdle(at: now)
        finalizeMouseIfIdle(at: now)
        refreshStatusItem()
        persistSession()
    }

    private func retryTypingCaptureIfNeeded(at now: Date) {
        guard typingPermissionState != .ready else {
            lastTypingCaptureRetryAt = nil
            return
        }

        if let lastTypingCaptureRetryAt,
           now.timeIntervalSince(lastTypingCaptureRetryAt) < typingCaptureRetryInterval
        {
            return
        }

        lastTypingCaptureRetryAt = now
        refreshTypingCapture(promptIfNeeded: false, revealPanelOnFailure: false)
    }

    private func currentRunDuration(at now: Date) -> TimeInterval {
        guard let runningSince else {
            return 0
        }
        return max(0, now.timeIntervalSince(runningSince))
    }

    private func currentPauseDuration(at now: Date) -> TimeInterval {
        guard let pausedSince else {
            return 0
        }
        return max(0, now.timeIntervalSince(pausedSince))
    }

    private func cumulativeRunTime(at now: Date) -> TimeInterval {
        let inFlightRun = isRunning ? currentRunDuration(at: now) : 0
        return sessionRunDurations.reduce(0, +) + inFlightRun
    }

    private func elapsed(at now: Date) -> TimeInterval {
        guard isRunning, let runningSince else {
            return accumulatedElapsed
        }
        return accumulatedElapsed + now.timeIntervalSince(runningSince)
    }

    private func finalizeCurrentRun(at now: Date) {
        let runDuration = currentRunDuration(at: now)
        guard runDuration > 0 else {
            return
        }
        sessionRunDurations.append(runDuration)
        longestRunDuration = max(longestRunDuration, runDuration)
    }

    private func rollDayIfNeeded(now: Date) {
        let newDayStart = calendar.startOfDay(for: now)
        guard newDayStart > currentDayStart else {
            return
        }

        if let activeTypingSession {
            commitTypingSession(activeTypingSession, at: newDayStart)
            self.activeTypingSession = nil
        }
        if let activeMouseSession {
            commitMouseSession(activeMouseSession, at: newDayStart)
            self.activeMouseSession = nil
        }

        archiveCurrentDay(until: newDayStart)

        let wasRunning = isRunning
        currentDayStart = newDayStart
        launchedAt = newDayStart
        currentTime = now
        logEntries.removeAll()
        pauseCount = 0
        resumeCount = 0
        resetCount = 0
        sessionRunDurations.removeAll()
        totalPausedDuration = 0
        longestRunDuration = 0
        lastResetElapsed = nil
        accumulatedElapsed = 0

        if wasRunning {
            runningSince = newDayStart
            pausedSince = nil
        } else {
            runningSince = nil
            pausedSince = newDayStart
        }

        if let typingStore {
            typingStoredSummary = (try? typingStore.typingSummary(from: newDayStart, to: now)) ?? .zero
        } else {
            typingStoredSummary = .zero
        }
        mouseStoredSummary = .zero
        persistSession()
    }

    private func startTypingCapture() {
        refreshTypingCapture(promptIfNeeded: false, revealPanelOnFailure: false)
    }

    private func startMouseCapture() {
        let installed = mouseCaptureService.start()
        DebugTrace.log("startMouseCapture installed=\(installed)")
    }

    private func refreshTypingCapture(promptIfNeeded: Bool, revealPanelOnFailure: Bool) {
        let state = typingCaptureService.permissionState(promptIfNeeded: promptIfNeeded)
        typingPermissionState = state
        DebugTrace.log(
            "refreshTypingCapture permissionState=\(String(describing: state)) prompt=\(promptIfNeeded) reveal=\(revealPanelOnFailure)"
        )
        guard state == .ready else {
            if revealPanelOnFailure {
                DispatchQueue.main.async { [weak self] in
                    self?.recoveryWindowManager.show(relativeTo: self?.statusItemController?.button)
                }
            }
            return
        }

        let startState = typingCaptureService.start()
        typingPermissionState = startState
        DebugTrace.log("refreshTypingCapture startState=\(String(describing: startState))")
        if startState == .ready, let typingStore {
            lastTypingCaptureRetryAt = nil
            typingStoredSummary = (try? typingStore.typingSummary(from: currentDayStart, to: currentTime)) ?? .zero
        } else if revealPanelOnFailure {
            DispatchQueue.main.async { [weak self] in
                self?.recoveryWindowManager.show(relativeTo: self?.statusItemController?.button)
            }
        }
    }

    private func finalizeTypingIfIdle(at now: Date) {
        guard let activeTypingSession else {
            return
        }
        guard now.timeIntervalSince(activeTypingSession.lastInputAt) >= typingIdleThreshold else {
            return
        }

        commitTypingSession(activeTypingSession, at: now)
        self.activeTypingSession = nil
    }

    private func finalizeMouseIfIdle(at now: Date) {
        guard let activeMouseSession else {
            return
        }
        guard now.timeIntervalSince(activeMouseSession.lastMovedAt) >= mouseIdleThreshold else {
            return
        }

        commitMouseSession(activeMouseSession, at: now)
        self.activeMouseSession = nil
    }

    private func commitTypingSession(_ session: ActiveTypingSession, at now: Date) {
        guard session.characterCount > 0 else {
            return
        }

        let endedAt = actualTypingEndedAt(for: session)
        guard endedAt > session.startedAt else {
            return
        }

        let record = TypingSessionRecord(
            id: UUID(),
            startedAt: session.startedAt,
            endedAt: endedAt,
            context: session.context,
            characterCount: session.characterCount
        )

        do {
            try typingStore?.insert(record)
            typingStoredSummary = TypingSummary(
                duration: typingStoredSummary.duration + record.duration,
                characterCount: typingStoredSummary.characterCount + record.characterCount
            )
        } catch {
            DebugTrace.log("commitTypingSession failed error=\(error.localizedDescription)")
        }
    }

    private func activeTypingDuration(at now: Date, for session: ActiveTypingSession) -> TimeInterval {
        let effectiveEnd = min(now, session.lastInputAt.addingTimeInterval(typingIdleThreshold))
        return max(0, effectiveEnd.timeIntervalSince(session.startedAt))
    }

    private func actualTypingEndedAt(for session: ActiveTypingSession) -> Date {
        max(session.lastInputAt, session.startedAt.addingTimeInterval(1))
    }

    private func commitMouseSession(_ session: ActiveMouseSession, at now: Date) {
        guard session.distance > 0 else {
            return
        }

        let endedAt = min(now, session.lastMovedAt.addingTimeInterval(mouseIdleThreshold))
        guard endedAt > session.startedAt else {
            return
        }

        mouseStoredSummary = MouseSummary(
            duration: mouseStoredSummary.duration + endedAt.timeIntervalSince(session.startedAt),
            distance: mouseStoredSummary.distance + session.distance
        )
    }

    private func activeMouseDuration(at now: Date, for session: ActiveMouseSession) -> TimeInterval {
        let effectiveEnd = min(now, session.lastMovedAt.addingTimeInterval(mouseIdleThreshold))
        return max(0, effectiveEnd.timeIntervalSince(session.startedAt))
    }

    private func archiveCurrentDay(until boundary: Date) {
        let workedSeconds = cumulativeRunTime(at: boundary)
        guard workedSeconds > 0 || !logEntries.isEmpty || resetCount > 0 || mouseSummary.distance > 0 else {
            return
        }

        let summary = DailyWorkSummary(
            dayStart: currentDayStart,
            workedSeconds: workedSeconds,
            earningsAmount: (workedSeconds / 3600) * hourlyRate,
            pauseCount: pauseCount,
            resetCount: resetCount,
            mouseDistance: mouseSummary.distance
        )

        if let existingIndex = dayHistory.firstIndex(where: { calendar.isDate($0.dayStart, inSameDayAs: currentDayStart) }) {
            dayHistory[existingIndex] = summary
        } else {
            dayHistory.insert(summary, at: 0)
        }

        dayHistory.sort { $0.dayStart > $1.dayStart }
        if dayHistory.count > 120 {
            dayHistory.removeLast(dayHistory.count - 120)
        }
        persistHistory()
    }

    private func appendLog(_ kind: TimerLogEntry.Kind, occurredAt: Date, elapsedSnapshot: TimeInterval) {
        logEntries.insert(
            TimerLogEntry(kind: kind, occurredAt: occurredAt, elapsedSnapshot: elapsedSnapshot),
            at: 0
        )
        if logEntries.count > 250 {
            logEntries.removeLast(logEntries.count - 250)
        }
    }

    private func refreshStatusItem() {
        statusItemController?.update(
            displayText: topBarText,
            isRunning: isRunning,
            displayMode: menuBarDisplayMode
        )
    }

    private func persistHistory() {
        if typingStore == nil {
            guard let data = try? JSONEncoder().encode(dayHistory) else {
                return
            }
            UserDefaults.standard.set(data, forKey: DefaultsKey.dayHistory)
            return
        }

        do {
            try typingStore?.saveDailySummaries(dayHistory)
        } catch {
            DebugTrace.log("persistHistory failed error=\(error.localizedDescription)")
        }
    }

    private func persistSession() {
        let session = PersistedSession(
            isRunning: isRunning,
            logEntries: logEntries,
            pauseCount: pauseCount,
            resumeCount: resumeCount,
            resetCount: resetCount,
            launchedAt: launchedAt,
            currentTime: currentTime,
            sessionRunDurations: sessionRunDurations,
            totalPausedDuration: totalPausedDuration,
            longestRunDuration: longestRunDuration,
            lastResetElapsed: lastResetElapsed,
            accumulatedElapsed: accumulatedElapsed,
            runningSince: runningSince,
            pausedSince: pausedSince,
            currentDayStart: currentDayStart,
            mouseStoredDuration: mouseStoredSummary.duration,
            mouseStoredDistance: mouseStoredSummary.distance,
            activeMouseStartedAt: activeMouseSession?.startedAt,
            activeMouseLastMovedAt: activeMouseSession?.lastMovedAt,
            activeMouseDistance: activeMouseSession?.distance
        )

        if typingStore == nil {
            guard let data = try? JSONEncoder().encode(session) else {
                return
            }
            do {
                let url = try Self.sessionFileURL()
                try data.write(to: url, options: .atomic)
            } catch {
                DebugTrace.log("persistSession failed error=\(error.localizedDescription)")
            }
            return
        }

        do {
            try typingStore?.saveSession(session)
        } catch {
            DebugTrace.log("persistSession failed error=\(error.localizedDescription)")
        }
    }

    private func persistSettings() {
        if typingStore == nil {
            UserDefaults.standard.set(menuBarDisplayMode.rawValue, forKey: DefaultsKey.menuBarDisplayMode)
            UserDefaults.standard.set(hourlyRate, forKey: DefaultsKey.hourlyRate)
            return
        }

        do {
            try typingStore?.setString(menuBarDisplayMode.rawValue, for: DefaultsKey.menuBarDisplayMode)
            try typingStore?.setDouble(hourlyRate, for: DefaultsKey.hourlyRate)
        } catch {
            DebugTrace.log("persistSettings failed error=\(error.localizedDescription)")
        }
    }

    private func persistCachedAIUsageSummary(_ summary: AIUsageSummary) {
        guard let data = try? JSONEncoder().encode(summary),
              let string = String(data: data, encoding: .utf8)
        else {
            return
        }

        UserDefaults.standard.set(string, forKey: DefaultsKey.aiUsageSummaryCache)
        try? typingStore?.setString(string, for: DefaultsKey.aiUsageSummaryCache)
    }

    private static func loadLegacyHistory() -> [DailyWorkSummary] {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.dayHistory),
              let summaries = try? JSONDecoder().decode([DailyWorkSummary].self, from: data)
        else {
            return []
        }
        return summaries.sorted { $0.dayStart > $1.dayStart }
    }

    private static func loadLegacySession() -> PersistedSession? {
        guard let url = try? sessionFileURL(),
              let data = try? Data(contentsOf: url),
              let session = try? JSONDecoder().decode(PersistedSession.self, from: data)
        else {
            return nil
        }

        return session
    }

    private static func loadCachedAIUsageSummary(from typingStore: TypingStore?) -> AIUsageSummary? {
        let cachedString = (try? typingStore?.stringSetting(for: DefaultsKey.aiUsageSummaryCache))
            ?? UserDefaults.standard.string(forKey: DefaultsKey.aiUsageSummaryCache)
        guard let cachedString,
              let data = cachedString.data(using: .utf8),
              let summary = try? JSONDecoder().decode(AIUsageSummary.self, from: data)
        else {
            return nil
        }
        return summary
    }

    private static func makeTypingStore(enabled: Bool, databaseURL: URL?) throws -> TypingStore? {
        if let databaseURL {
            return try TypingStore(databaseURL: databaseURL)
        }

        guard enabled else {
            return nil
        }
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("WorkTimer", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("worktimer.sqlite", isDirectory: false)
        try migrateLegacyDatabaseIfNeeded(in: directory, targetURL: databaseURL)
        return try TypingStore(databaseURL: databaseURL)
    }

    private static func migrateLegacyDatabaseIfNeeded(in directory: URL, targetURL: URL) throws {
        guard !FileManager.default.fileExists(atPath: targetURL.path) else {
            return
        }

        let legacyURL = directory.appendingPathComponent("typing.sqlite", isDirectory: false)
        guard FileManager.default.fileExists(atPath: legacyURL.path) else {
            return
        }

        try FileManager.default.moveItem(at: legacyURL, to: targetURL)

        let fileManager = FileManager.default
        for suffix in ["-shm", "-wal"] {
            let legacySidecar = URL(fileURLWithPath: legacyURL.path + suffix)
            let targetSidecar = URL(fileURLWithPath: targetURL.path + suffix)
            if fileManager.fileExists(atPath: legacySidecar.path) {
                try? fileManager.moveItem(at: legacySidecar, to: targetSidecar)
            }
        }
    }

    private static func characterIncrement(for mutation: TypingMutation) -> Int {
        switch mutation {
        case let .text(text):
            return text.count
        case .newline, .tab:
            return 1
        case .backspace:
            return 0
        }
    }

    private func restore(from session: PersistedSession, now: Date) {
        isRunning = session.isRunning
        logEntries = session.logEntries
        pauseCount = session.pauseCount
        resumeCount = session.resumeCount
        resetCount = session.resetCount
        launchedAt = session.launchedAt
        currentTime = max(now, session.currentTime)
        sessionRunDurations = session.sessionRunDurations
        totalPausedDuration = session.totalPausedDuration
        longestRunDuration = session.longestRunDuration
        lastResetElapsed = session.lastResetElapsed
        accumulatedElapsed = session.accumulatedElapsed
        runningSince = session.runningSince
        pausedSince = session.pausedSince
        currentDayStart = session.currentDayStart
        mouseStoredSummary = MouseSummary(
            duration: session.mouseStoredDuration ?? 0,
            distance: session.mouseStoredDistance ?? 0
        )
        if let startedAt = session.activeMouseStartedAt,
           let lastMovedAt = session.activeMouseLastMovedAt,
           let distance = session.activeMouseDistance {
            activeMouseSession = ActiveMouseSession(
                startedAt: startedAt,
                lastMovedAt: lastMovedAt,
                distance: distance
            )
        } else {
            activeMouseSession = nil
        }
    }

    nonisolated private static func sessionFileURL() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("WorkTimer", isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        return directory.appendingPathComponent("session.json", isDirectory: false)
    }

    nonisolated static func formatElapsed(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return "\(hours):" + String(format: "%02d:%02d", minutes, seconds)
    }

    nonisolated static func formatCurrency(_ amount: Double) -> String {
        let currencyCode = Locale.autoupdatingCurrent.currency?.identifier ?? "USD"
        return amount.formatted(
            .currency(code: currencyCode)
                .precision(.fractionLength(2))
        )
    }

    nonisolated static func formatLiveCurrency(_ amount: Double) -> String {
        let currencyCode = Locale.autoupdatingCurrent.currency?.identifier ?? "USD"
        let safeAmount = max(0, amount)

        let fractionDigits: Int
        switch safeAmount {
        case 0..<1:
            fractionDigits = 4
        case 1..<10:
            fractionDigits = 3
        default:
            fractionDigits = 2
        }

        return safeAmount.formatted(
            .currency(code: currencyCode)
                .precision(.fractionLength(fractionDigits))
        )
    }

    nonisolated static func formatDistance(_ distance: Double) -> String {
        let safeMillimeters = max(0, distance)
        let feet = safeMillimeters / 304.8
        if feet >= 1_000 {
            let miles = feet / 5_280
            if miles >= 10 {
                return String(format: "%.1f mi", miles)
            }
            return String(format: "%.2f mi", miles)
        }
        if feet >= 100 {
            return String(format: "%.0f ft", feet)
        }
        if feet >= 10 {
            return String(format: "%.1f ft", feet)
        }
        return String(format: "%.2f ft", feet)
    }

    nonisolated static func formatCompactCount(_ value: Int) -> String {
        let safeValue = max(0, value)
        switch safeValue {
        case 1_000_000...:
            let millions = Double(safeValue) / 1_000_000
            return String(format: millions >= 10 ? "%.0fM" : "%.1fM", millions)
        case 1_000...:
            let thousands = Double(safeValue) / 1_000
            return String(format: thousands >= 10 ? "%.0fk" : "%.1fk", thousands)
        default:
            return "\(safeValue)"
        }
    }

    nonisolated static func formatCompactInt64(_ value: Int64) -> String {
        let absValue = abs(Double(value))
        if absValue >= 1_000_000_000 {
            return String(format: "%.2fB", Double(value) / 1_000_000_000)
        }
        if absValue >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if absValue >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    nonisolated static func formatTokensPerSecond(_ value: Double) -> String {
        let safeValue = max(0, value)
        switch safeValue {
        case 0:
            return "0.00"
        case 0..<0.01:
            return "<0.01"
        case 0.01..<0.1:
            return String(format: "%.2f", safeValue)
        case 0.1..<10:
            return String(format: "%.1f", safeValue)
        case 10..<1_000:
            return "\(Int(safeValue.rounded()))"
        case 1_000..<1_000_000:
            let thousands = safeValue / 1_000
            return String(format: thousands >= 10 ? "%.0fK" : "%.1fK", thousands)
        case 1_000_000..<1_000_000_000:
            let millions = safeValue / 1_000_000
            return String(format: millions >= 10 ? "%.0fM" : "%.1fM", millions)
        default:
            let billions = safeValue / 1_000_000_000
            return String(format: billions >= 10 ? "%.0fB" : "%.2fB", billions)
        }
    }

    nonisolated static func preferredAITokensPerSecondDisplay(for summary: AIUsageSummary) -> Double {
        let oneMinute = max(0, summary.lastMinuteAverageTokensPerSecond)
        let fiveMinutes = max(0, summary.lastFiveMinutesAverageTokensPerSecond)
        let fifteenMinutes = max(0, summary.lastFifteenMinutesAverageTokensPerSecond)
        let hour = max(0, summary.lastHourAverageTokensPerSecond)
        let visibleThreshold = 0.01

        if oneMinute >= visibleThreshold {
            return oneMinute
        }

        var candidates = [oneMinute, fiveMinutes, hour]
        if summary.hasRecentSupersetSessionActivity {
            candidates.append(fifteenMinutes)
        }

        let positiveCandidates = candidates.filter { $0 > 0 }
        return positiveCandidates.max() ?? 0
    }

    nonisolated static func mergedAIUsageSummary(current: AIUsageSummary, incoming: AIUsageSummary) -> AIUsageSummary {
        guard shouldPreserveCurrentAIRates(current: current, incoming: incoming) else {
            return incoming
        }

        return AIUsageSummary(
            combined: incoming.combined,
            codex: incoming.codex,
            claude: incoming.claude,
            lastMinuteAverageTokensPerSecond: current.lastMinuteAverageTokensPerSecond,
            lastFiveMinutesAverageTokensPerSecond: current.lastFiveMinutesAverageTokensPerSecond,
            lastFifteenMinutesAverageTokensPerSecond: current.lastFifteenMinutesAverageTokensPerSecond,
            lastHourAverageTokensPerSecond: current.lastHourAverageTokensPerSecond,
            lastThirtyMinutesRateSeries: current.lastThirtyMinutesRateSeries,
            hasRecentSupersetSessionActivity: incoming.hasRecentSupersetSessionActivity || current.hasRecentSupersetSessionActivity,
            watchedCodexFiles: incoming.watchedCodexFiles,
            watchedClaudeFiles: incoming.watchedClaudeFiles
        )
    }

    private nonisolated static func shouldPreserveCurrentAIRates(current: AIUsageSummary, incoming: AIUsageSummary) -> Bool {
        guard incoming.hasRecentSupersetSessionActivity else {
            return false
        }

        let incomingLooksIdle =
            incoming.lastMinuteAverageTokensPerSecond <= 0 &&
            incoming.lastFiveMinutesAverageTokensPerSecond <= 0 &&
            incoming.lastFifteenMinutesAverageTokensPerSecond <= 0 &&
            incoming.lastHourAverageTokensPerSecond <= 0 &&
            incoming.lastThirtyMinutesRateSeries.allSatisfy { $0 <= 0 }
        guard incomingLooksIdle else {
            return false
        }

        let currentHasSignal =
            current.lastMinuteAverageTokensPerSecond > 0 ||
            current.lastFiveMinutesAverageTokensPerSecond > 0 ||
            current.lastFifteenMinutesAverageTokensPerSecond > 0 ||
            current.lastHourAverageTokensPerSecond > 0 ||
            current.lastThirtyMinutesRateSeries.contains(where: { $0 > 0 })
        guard currentHasSignal else {
            return false
        }

        return incoming.combined.tokens >= current.combined.tokens
    }

    nonisolated static func smoothedAISeries(_ values: [Double]) -> [Double] {
        guard !values.isEmpty else {
            return []
        }

        var smoothed: [Double] = []
        smoothed.reserveCapacity(values.count)
        var previous = max(0, values[0])
        smoothed.append(previous)

        for value in values.dropFirst() {
            let safeValue = max(0, value)
            let blended = (previous * 0.72) + (safeValue * 0.28)
            smoothed.append(blended)
            previous = blended
        }

        return smoothed
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

}

struct PersistedSession: Codable, Equatable {
    let isRunning: Bool
    let logEntries: [TimerLogEntry]
    let pauseCount: Int
    let resumeCount: Int
    let resetCount: Int
    let launchedAt: Date
    let currentTime: Date
    let sessionRunDurations: [TimeInterval]
    let totalPausedDuration: TimeInterval
    let longestRunDuration: TimeInterval
    let lastResetElapsed: TimeInterval?
    let accumulatedElapsed: TimeInterval
    let runningSince: Date?
    let pausedSince: Date?
    let currentDayStart: Date
    let mouseStoredDuration: TimeInterval?
    let mouseStoredDistance: Double?
    let activeMouseStartedAt: Date?
    let activeMouseLastMovedAt: Date?
    let activeMouseDistance: Double?
}

struct TimerLogEntry: Identifiable, Codable, Equatable {
    enum Kind: String, Codable, Equatable {
        case paused
        case resumed
        case reset

        var title: String {
            switch self {
            case .paused:
                return "Paused"
            case .resumed:
                return "Resumed"
            case .reset:
                return "Reset"
            }
        }
    }

    let id: UUID
    let kind: Kind
    let occurredAt: Date
    let elapsedSnapshot: TimeInterval

    init(id: UUID = UUID(), kind: Kind, occurredAt: Date, elapsedSnapshot: TimeInterval) {
        self.id = id
        self.kind = kind
        self.occurredAt = occurredAt
        self.elapsedSnapshot = elapsedSnapshot
    }

    var title: String {
        kind.title
    }
}

struct DailyWorkSummary: Identifiable, Codable, Equatable {
    let dayStart: Date
    let workedSeconds: TimeInterval
    let earningsAmount: Double
    let pauseCount: Int
    let resetCount: Int
    let mouseDistance: Double?

    var id: Date { dayStart }

    var dayTitle: String {
        if Calendar.autoupdatingCurrent.isDateInToday(dayStart) {
            return "Today"
        }
        if Calendar.autoupdatingCurrent.isDateInYesterday(dayStart) {
            return "Yesterday"
        }
        return dayStart.formatted(date: .abbreviated, time: .omitted)
    }

    var workedText: String {
        AppModel.formatElapsed(workedSeconds)
    }

    var earningsText: String {
        AppModel.formatCurrency(earningsAmount)
    }

    var mouseDistanceText: String {
        AppModel.formatDistance(mouseDistance ?? 0)
    }
}
