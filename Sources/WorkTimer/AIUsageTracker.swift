import Foundation

struct AIUsageComponentSummary: Equatable, Sendable {
    let tokens: Int64
    let todayTokens: Int64
}

struct AIUsageSummary: Equatable, Sendable {
    let combined: AIUsageComponentSummary
    let codex: AIUsageComponentSummary
    let claude: AIUsageComponentSummary
    let lastMinuteAverageTokensPerSecond: Double
    let lastFiveMinutesAverageTokensPerSecond: Double
    let lastFifteenMinutesAverageTokensPerSecond: Double
    let hasRecentSupersetSessionActivity: Bool
    let watchedCodexFiles: Int
    let watchedClaudeFiles: Int

    static let zero = AIUsageSummary(
        combined: AIUsageComponentSummary(tokens: 0, todayTokens: 0),
        codex: AIUsageComponentSummary(tokens: 0, todayTokens: 0),
        claude: AIUsageComponentSummary(tokens: 0, todayTokens: 0),
        lastMinuteAverageTokensPerSecond: 0,
        lastFiveMinutesAverageTokensPerSecond: 0,
        lastFifteenMinutesAverageTokensPerSecond: 0,
        hasRecentSupersetSessionActivity: false,
        watchedCodexFiles: 0,
        watchedClaudeFiles: 0
    )
}

private struct AIUsageSnapshotTotals {
    let totalTokens: Int64
    let totalCost: Double
}

private struct CodexRawUsage {
    let inputTokens: Int64
    let cachedInputTokens: Int64
    let outputTokens: Int64
    let reasoningOutputTokens: Int64
    let totalTokens: Int64
}

private final class AITrackedFile {
    let url: URL
    var offset: UInt64 = 0
    var buffer = ""
    var previousCodexTotal: CodexRawUsage?

    init(url: URL) {
        self.url = url
    }
}

private struct AIRateSample {
    let date: Date
    let tokenDelta: Int64
}

final class AIUsageTracker {
    let siteRoot: URL
    let codexRoot: URL
    let claudeRoot: URL
    let supersetSessionLogRoot: URL

    private let fileManager = FileManager.default
    private let now: () -> Date

    private let codexUsageURL: URL
    private let claudeUsageURL: URL

    private let codexSnapshot: AIUsageSnapshotTotals
    private let claudeSnapshot: AIUsageSnapshotTotals
    private let codexCutoffDate: Date
    private let claudeCutoffDate: Date
    private let codexTodaySnapshotTokens: Int64
    private let claudeTodaySnapshotTokens: Int64

    private var codexLiveTokens: Int64 = 0
    private var claudeLiveTokens: Int64 = 0
    private var codexLiveTodayTokens: Int64 = 0
    private var claudeLiveTodayTokens: Int64 = 0

    private var codexFiles: [URL: AITrackedFile] = [:]
    private var claudeFiles: [URL: AITrackedFile] = [:]
    private var lastCodexDiscovery = Date.distantPast
    private var lastClaudeDiscovery = Date.distantPast
    private var rateSamples: [AIRateSample] = []

    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(siteRoot: URL, codexRoot: URL? = nil, claudeRoot: URL? = nil, supersetSessionLogRoot: URL? = nil, now: @escaping () -> Date = Date.init) throws {
        self.siteRoot = siteRoot
        self.codexRoot = codexRoot ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        self.claudeRoot = claudeRoot ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        self.supersetSessionLogRoot = supersetSessionLogRoot ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".superset/session-logs", isDirectory: true)
        self.now = now

        codexUsageURL = siteRoot.appendingPathComponent("usage-data/codex-usage.json", isDirectory: false)
        claudeUsageURL = siteRoot.appendingPathComponent("usage-data/claude-usage.json", isDirectory: false)

        codexSnapshot = try Self.loadSnapshot(from: codexUsageURL, tokenKey: "totalTokens", costKey: "costUSD")
        claudeSnapshot = try Self.loadSnapshot(from: claudeUsageURL, tokenKey: "totalTokens", costKey: "totalCost")
        codexCutoffDate = try Self.modificationDate(for: codexUsageURL)
        claudeCutoffDate = try Self.modificationDate(for: claudeUsageURL)
        codexTodaySnapshotTokens = try Self.loadTodayTokens(from: codexUsageURL, now: now)
        claudeTodaySnapshotTokens = try Self.loadTodayTokens(from: claudeUsageURL, now: now)
    }

    func bootstrap() throws {
        try discoverCodex(force: true)
        try discoverClaude(force: true)
    }

    func tick() throws {
        try discoverCodex(force: false)
        try discoverClaude(force: false)
        try poll(files: codexFiles, processor: processCodexChunk(_:chunk:))
        try poll(files: claudeFiles, processor: processClaudeChunk(_:chunk:))
    }

    func summary() -> AIUsageSummary {
        let codexTokens = codexSnapshot.totalTokens + codexLiveTokens
        let claudeTokens = claudeSnapshot.totalTokens + claudeLiveTokens
        let codexTodayTokens = codexTodaySnapshotTokens + codexLiveTodayTokens
        let claudeTodayTokens = claudeTodaySnapshotTokens + claudeLiveTodayTokens
        return AIUsageSummary(
            combined: AIUsageComponentSummary(tokens: codexTokens + claudeTokens, todayTokens: codexTodayTokens + claudeTodayTokens),
            codex: AIUsageComponentSummary(tokens: codexTokens, todayTokens: codexTodayTokens),
            claude: AIUsageComponentSummary(tokens: claudeTokens, todayTokens: claudeTodayTokens),
            lastMinuteAverageTokensPerSecond: averageTokensPerSecond(within: 60),
            lastFiveMinutesAverageTokensPerSecond: averageTokensPerSecond(within: 300),
            lastFifteenMinutesAverageTokensPerSecond: averageTokensPerSecond(within: 900),
            hasRecentSupersetSessionActivity: hasRecentSupersetSessionActivity(within: 120),
            watchedCodexFiles: codexFiles.count,
            watchedClaudeFiles: claudeFiles.count
        )
    }

    static func defaultSiteRoot() -> URL? {
        if let override = ProcessInfo.processInfo.environment["WORKTIMER_AI_USAGE_SITE_ROOT"], !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        let candidates = [
            URL(fileURLWithPath: "/Users/nickita/code/nickita-khylkouski.github.io", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("code/nickita-khylkouski.github.io", isDirectory: true),
        ]

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func discoverCodex(force: Bool) throws {
        if !force, now().timeIntervalSince(lastCodexDiscovery) < 2 {
            return
        }
        lastCodexDiscovery = now()

        let candidates = try enumerateRecentJSONLFiles(root: codexRoot, cutoff: codexCutoffDate.addingTimeInterval(-2), limit: 24)
        for candidate in candidates where codexFiles[candidate.url] == nil {
            let tracked = AITrackedFile(url: candidate.url)
            codexFiles[candidate.url] = tracked
            try scanWholeFile(tracked: tracked, processor: processCodexChunk(_:chunk:))
        }
    }

    private func discoverClaude(force: Bool) throws {
        if !force, now().timeIntervalSince(lastClaudeDiscovery) < 10 {
            return
        }
        lastClaudeDiscovery = now()

        let candidates = try enumerateRecentJSONLFiles(root: claudeRoot, cutoff: claudeCutoffDate.addingTimeInterval(-2), limit: 32)
        for candidate in candidates where claudeFiles[candidate.url] == nil {
            let tracked = AITrackedFile(url: candidate.url)
            claudeFiles[candidate.url] = tracked
            try scanWholeFile(tracked: tracked, processor: processClaudeChunk(_:chunk:))
        }
    }

    private func enumerateRecentJSONLFiles(root: URL, cutoff: Date, limit: Int) throws -> [(url: URL, mtime: Date)] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [(URL, Date)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values.isRegularFile == true, let mtime = values.contentModificationDate, mtime >= cutoff else {
                continue
            }
            results.append((url, mtime))
        }
        return results.sorted { $0.1 > $1.1 }.prefix(limit).map { $0 }
    }

    private func scanWholeFile(tracked: AITrackedFile, processor: (AITrackedFile, String) throws -> Void) throws {
        let data = try Data(contentsOf: tracked.url)
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        try processor(tracked, text.hasSuffix("\n") ? text : text + "\n")
        tracked.offset = UInt64(data.count)
    }

    private func poll(files: [URL: AITrackedFile], processor: (AITrackedFile, String) throws -> Void) throws {
        for tracked in files.values {
            let values = try tracked.url.resourceValues(forKeys: [.fileSizeKey])
            let size = UInt64(values.fileSize ?? 0)

            if size < tracked.offset {
                tracked.offset = 0
                tracked.buffer = ""
                tracked.previousCodexTotal = nil
                try scanWholeFile(tracked: tracked, processor: processor)
                continue
            }

            guard size > tracked.offset else { continue }
            let handle = try FileHandle(forReadingFrom: tracked.url)
            defer { try? handle.close() }
            try handle.seek(toOffset: tracked.offset)
            let data = try handle.readToEnd() ?? Data()
            tracked.offset = size
            try processor(tracked, String(decoding: data, as: UTF8.self))
        }
    }

    private func completeLines(for tracked: AITrackedFile, chunk: String) -> [String] {
        let combined = tracked.buffer + chunk
        guard !combined.isEmpty else { return [] }

        var lines = combined.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if combined.hasSuffix("\n") {
            tracked.buffer = ""
        } else {
            tracked.buffer = lines.popLast() ?? ""
        }
        return lines.filter { !$0.isEmpty }
    }

    private func processCodexChunk(_ tracked: AITrackedFile, chunk: String) throws {
        for line in completeLines(for: tracked, chunk: chunk) {
            guard
                let data = line.data(using: .utf8),
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let timestampString = object["timestamp"] as? String,
                let timestamp = parseTimestamp(timestampString)
            else {
                continue
            }

            guard object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count"
            else {
                continue
            }

            let info = payload["info"] as? [String: Any]
            let totalUsage = Self.codexRawUsage(from: info?["total_token_usage"])
            let lastUsage = Self.codexRawUsage(from: info?["last_token_usage"])
            let raw: CodexRawUsage?
            if let totalUsage, let previous = tracked.previousCodexTotal {
                raw = Self.codexDelta(current: totalUsage, previous: previous)
            } else {
                raw = lastUsage ?? totalUsage
            }
            if let totalUsage {
                tracked.previousCodexTotal = totalUsage
            }
            guard let raw, timestamp > codexCutoffDate, raw.totalTokens > 0 else {
                continue
            }

            codexLiveTokens += raw.totalTokens
            recordRateSample(at: timestamp, tokenDelta: raw.totalTokens)
            if Calendar.current.isDate(timestamp, inSameDayAs: now()) {
                codexLiveTodayTokens += raw.totalTokens
            }
        }
    }

    private func processClaudeChunk(_ tracked: AITrackedFile, chunk: String) throws {
        for line in completeLines(for: tracked, chunk: chunk) {
            guard
                let data = line.data(using: .utf8),
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let timestampString = object["timestamp"] as? String,
                let timestamp = parseTimestamp(timestampString),
                timestamp > claudeCutoffDate,
                let message = object["message"] as? [String: Any],
                let usage = message["usage"] as? [String: Any]
            else {
                continue
            }

            let total =
                Self.int64(usage["input_tokens"]) +
                Self.int64(usage["output_tokens"]) +
                Self.int64(usage["cache_creation_input_tokens"]) +
                Self.int64(usage["cache_read_input_tokens"])
            guard total > 0 else { continue }
            claudeLiveTokens += total
            recordRateSample(at: timestamp, tokenDelta: total)
            if Calendar.current.isDate(timestamp, inSameDayAs: now()) {
                claudeLiveTodayTokens += total
            }
        }
    }

    private func parseTimestamp(_ value: String) -> Date? {
        if let date = isoFormatter.date(from: value) {
            return date
        }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: value)
    }

    private static func codexRawUsage(from value: Any?) -> CodexRawUsage? {
        guard let dict = value as? [String: Any] else { return nil }
        let input = int64(dict["input_tokens"])
        let cached = int64(dict["cached_input_tokens"] ?? dict["cache_read_input_tokens"])
        let output = int64(dict["output_tokens"])
        let reasoning = int64(dict["reasoning_output_tokens"])
        let explicitTotal = int64(dict["total_tokens"])
        let total = explicitTotal > 0 ? explicitTotal : (input + output)
        return CodexRawUsage(
            inputTokens: input,
            cachedInputTokens: cached,
            outputTokens: output,
            reasoningOutputTokens: reasoning,
            totalTokens: total
        )
    }

    private static func codexDelta(current: CodexRawUsage?, previous: CodexRawUsage?) -> CodexRawUsage? {
        guard let current else { return nil }
        guard let previous else { return current }
        return CodexRawUsage(
            inputTokens: max(current.inputTokens - previous.inputTokens, 0),
            cachedInputTokens: max(current.cachedInputTokens - previous.cachedInputTokens, 0),
            outputTokens: max(current.outputTokens - previous.outputTokens, 0),
            reasoningOutputTokens: max(current.reasoningOutputTokens - previous.reasoningOutputTokens, 0),
            totalTokens: max(current.totalTokens - previous.totalTokens, 0)
        )
    }

    private static func loadSnapshot(from url: URL, tokenKey: String, costKey: String) throws -> AIUsageSnapshotTotals {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let totals = object?["totals"] as? [String: Any] ?? [:]
        return AIUsageSnapshotTotals(
            totalTokens: int64(totals[tokenKey]),
            totalCost: double(totals[costKey])
        )
    }

    private static func loadTodayTokens(from url: URL, now: () -> Date) throws -> Int64 {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let daily = object?["daily"] as? [[String: Any]] ?? []
        let calendar = Calendar.current
        for row in daily.reversed() {
            guard
                let rawDate = row["date"] as? String,
                let parsedDate = parseDailyDate(rawDate),
                calendar.isDate(parsedDate, inSameDayAs: now())
            else {
                continue
            }
            return int64(row["totalTokens"])
        }
        return 0
    }

    private static func parseDailyDate(_ value: String) -> Date? {
        let isoFormatter = DateFormatter()
        isoFormatter.locale = Locale(identifier: "en_US_POSIX")
        isoFormatter.timeZone = TimeZone.current
        isoFormatter.dateFormat = "yyyy-MM-dd"
        if let date = isoFormatter.date(from: value) {
            return date
        }

        let spokenFormatter = DateFormatter()
        spokenFormatter.locale = Locale(identifier: "en_US_POSIX")
        spokenFormatter.timeZone = TimeZone.current
        spokenFormatter.dateFormat = "MMM dd, yyyy"
        return spokenFormatter.date(from: value)
    }

    private static func modificationDate(for url: URL) throws -> Date {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
        return values.contentModificationDate ?? .distantPast
    }

    private static func int64(_ value: Any?) -> Int64 {
        switch value {
        case let int as Int:
            return Int64(int)
        case let int64 as Int64:
            return int64
        case let double as Double:
            return Int64(double)
        case let string as String:
            return Int64(string) ?? 0
        case let number as NSNumber:
            return number.int64Value
        default:
            return 0
        }
    }

    private static func double(_ value: Any?) -> Double {
        switch value {
        case let double as Double:
            return double
        case let int as Int:
            return Double(int)
        case let string as String:
            return Double(string) ?? 0
        case let number as NSNumber:
            return number.doubleValue
        default:
            return 0
        }
    }

    private func recordRateSample(at date: Date, tokenDelta: Int64) {
        let sample = AIRateSample(date: date, tokenDelta: max(tokenDelta, 0))
        rateSamples.append(sample)
        let cutoff = now().addingTimeInterval(-900)
        rateSamples.removeAll { $0.date < cutoff }
    }

    private func averageTokensPerSecond(within interval: TimeInterval) -> Double {
        let cutoff = now().addingTimeInterval(-interval)
        let recent = rateSamples.filter { $0.date >= cutoff }
        guard let first = recent.first else {
            return 0
        }
        let total = recent.reduce(into: Int64(0)) { partial, sample in
            partial += max(sample.tokenDelta, 0)
        }
        guard total > 0 else {
            return 0
        }
        let elapsed = max(now().timeIntervalSince(first.date), 1)
        return Double(total) / elapsed
    }

    private func hasRecentSupersetSessionActivity(within interval: TimeInterval) -> Bool {
        guard
            let latest = try? latestModificationDate(in: supersetSessionLogRoot)
        else {
            return false
        }
        return now().timeIntervalSince(latest) <= interval
    }

    private func latestModificationDate(in root: URL) throws -> Date? {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var latest: Date?
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values.isRegularFile == true, let modifiedAt = values.contentModificationDate else {
                continue
            }
            if latest == nil || modifiedAt > latest! {
                latest = modifiedAt
            }
        }
        return latest
    }
}

final class AIUsageMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "worktimer.ai-usage", qos: .utility)
    private let minimumRefreshInterval: TimeInterval
    private var tracker: AIUsageTracker?
    private var tickInFlight = false
    private var lastRefreshAt = Date.distantPast

    var onSummary: ((AIUsageSummary) -> Void)?
    var onAvailabilityChange: ((Bool) -> Void)?

    init(minimumRefreshInterval: TimeInterval = 3) {
        self.minimumRefreshInterval = minimumRefreshInterval
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            guard let siteRoot = AIUsageTracker.defaultSiteRoot() else {
                DispatchQueue.main.async {
                    self.onAvailabilityChange?(false)
                }
                return
            }

            do {
                let tracker = try AIUsageTracker(siteRoot: siteRoot)
                try tracker.bootstrap()
                let summary = tracker.summary()
                self.tracker = tracker
                self.lastRefreshAt = Date()
                DispatchQueue.main.async {
                    self.onAvailabilityChange?(true)
                    self.onSummary?(summary)
                }
            } catch {
                DispatchQueue.main.async {
                    self.onAvailabilityChange?(false)
                }
            }
        }
    }

    func tick() {
        queue.async { [weak self] in
            guard let self, let tracker = self.tracker, !self.tickInFlight else { return }
            let now = Date()
            guard now.timeIntervalSince(self.lastRefreshAt) >= self.minimumRefreshInterval else {
                return
            }
            self.tickInFlight = true
            self.lastRefreshAt = now
            defer { self.tickInFlight = false }

            do {
                try tracker.tick()
                let summary = tracker.summary()
                DispatchQueue.main.async {
                    self.onSummary?(summary)
                }
            } catch {
                DispatchQueue.main.async {
                    self.onAvailabilityChange?(false)
                }
            }
        }
    }
}
