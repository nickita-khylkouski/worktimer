import Foundation

struct AIUsageComponentSummary: Equatable, Sendable, Codable {
    let tokens: Int64
    let todayTokens: Int64
}

struct AIUsageSummary: Equatable, Sendable, Codable {
    let combined: AIUsageComponentSummary
    let codex: AIUsageComponentSummary
    let claude: AIUsageComponentSummary
    let lastMinuteAverageTokensPerSecond: Double
    let lastFiveMinutesAverageTokensPerSecond: Double
    let lastFifteenMinutesAverageTokensPerSecond: Double
    let lastHourAverageTokensPerSecond: Double
    let lastThirtyMinutesRateSeries: [Double]
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
        lastHourAverageTokensPerSecond: 0,
        lastThirtyMinutesRateSeries: Array(repeating: 0, count: 30),
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
    let siteRoot: URL?
    let codexRoot: URL
    let claudeRoot: URL
    let supersetSessionLogRoot: URL

    private let fileManager = FileManager.default
    private let now: () -> Date

    private let codexUsageURL: URL?
    private let claudeUsageURL: URL?

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

    private let codexDiscoveryLookback: TimeInterval = 60 * 60 * 24 * 2
    private let claudeDiscoveryLookback: TimeInterval = 60 * 60 * 24 * 7
    private let codexDiscoveryInterval: TimeInterval = 30
    private let claudeDiscoveryInterval: TimeInterval = 30
    private let codexBootstrapFileLimit = 12
    private let codexIncrementalFileLimit = 16

    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(siteRoot: URL? = nil, codexRoot: URL? = nil, claudeRoot: URL? = nil, supersetSessionLogRoot: URL? = nil, now: @escaping () -> Date = Date.init) throws {
        let resolvedSiteRoot = siteRoot ?? Self.defaultSiteRoot()
        self.siteRoot = resolvedSiteRoot
        self.codexRoot = codexRoot ?? Self.defaultCodexRoot()
        self.claudeRoot = claudeRoot ?? Self.defaultClaudeRoot()
        self.supersetSessionLogRoot = supersetSessionLogRoot ?? Self.defaultSupersetSessionLogRoot()
        self.now = now

        codexUsageURL = resolvedSiteRoot.flatMap { Self.resolveSnapshotURL(in: $0, fileName: "codex-usage.json") }
        claudeUsageURL = resolvedSiteRoot.flatMap { Self.resolveSnapshotURL(in: $0, fileName: "claude-usage.json") }

        if let codexUsageURL {
            codexSnapshot = try Self.loadSnapshot(from: codexUsageURL, tokenKey: "totalTokens", costKey: "costUSD")
            codexCutoffDate = try Self.modificationDate(for: codexUsageURL)
            codexTodaySnapshotTokens = try Self.loadTodayTokens(from: codexUsageURL, now: now)
        } else {
            codexSnapshot = AIUsageSnapshotTotals(totalTokens: 0, totalCost: 0)
            codexCutoffDate = .distantPast
            codexTodaySnapshotTokens = 0
        }

        if let claudeUsageURL {
            claudeSnapshot = try Self.loadSnapshot(from: claudeUsageURL, tokenKey: "totalTokens", costKey: "totalCost")
            claudeCutoffDate = try Self.modificationDate(for: claudeUsageURL)
            claudeTodaySnapshotTokens = try Self.loadTodayTokens(from: claudeUsageURL, now: now)
        } else {
            claudeSnapshot = AIUsageSnapshotTotals(totalTokens: 0, totalCost: 0)
            claudeCutoffDate = .distantPast
            claudeTodaySnapshotTokens = 0
        }
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
            lastHourAverageTokensPerSecond: averageTokensPerSecond(within: 3_600),
            lastThirtyMinutesRateSeries: rateSeries(within: 1_800, bucketCount: 30),
            hasRecentSupersetSessionActivity: hasRecentSupersetSessionActivity(within: 120),
            watchedCodexFiles: codexFiles.count,
            watchedClaudeFiles: claudeFiles.count
        )
    }

    static func defaultSiteRoot() -> URL? {
        if let override = ProcessInfo.processInfo.environment["WORKTIMER_AI_USAGE_SITE_ROOT"], !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            if resolveSnapshotURL(in: url, fileName: "codex-usage.json") != nil {
                return url
            }
        }

        let fileManager = FileManager.default
        var candidates: [URL] = []

        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        candidates.append(currentDirectory)
        candidates.append(currentDirectory.deletingLastPathComponent())
        candidates.append(fileManager.homeDirectoryForCurrentUser.appendingPathComponent("code", isDirectory: true))
        candidates.append(fileManager.homeDirectoryForCurrentUser.appendingPathComponent("code/nickita-khylkouski.github.io", isDirectory: true))

        if let codeRoots = try? fileManager.contentsOfDirectory(
            at: fileManager.homeDirectoryForCurrentUser.appendingPathComponent("code", isDirectory: true),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            candidates.append(contentsOf: codeRoots)
        }

        return candidates.first { resolveSnapshotURL(in: $0, fileName: "codex-usage.json") != nil }
    }

    static func defaultCodexRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["WORKTIMER_CODEX_ROOT"], !override.isEmpty {
            let url = normalizeSessionsRoot(URL(fileURLWithPath: override, isDirectory: true))
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"], !codexHome.isEmpty {
            let url = normalizeSessionsRoot(URL(fileURLWithPath: codexHome, isDirectory: true))
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let primaryRoot = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        if latestJSONLModificationDate(in: primaryRoot) != nil {
            return primaryRoot
        }

        var candidates: [URL] = [primaryRoot]

        let supersetWorktrees = home.appendingPathComponent(".superset/worktrees", isDirectory: true)
        if let enumerator = fileManager.enumerator(
            at: supersetWorktrees,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                guard url.lastPathComponent == "sessions", url.path.contains(".codex-isolated-home/.codex/sessions") else {
                    continue
                }
                candidates.append(url)
            }
        }

        return freshestExistingRoot(from: candidates) ?? candidates[0]
    }

    static func defaultClaudeRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["WORKTIMER_CLAUDE_ROOT"], !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    static func defaultSupersetSessionLogRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["WORKTIMER_SUPERSET_LOG_ROOT"], !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".superset/session-logs", isDirectory: true)
    }

    private func discoverCodex(force: Bool) throws {
        if !force, now().timeIntervalSince(lastCodexDiscovery) < codexDiscoveryInterval {
            return
        }
        lastCodexDiscovery = now()

        let candidates = try enumerateRecentJSONLFiles(
            root: codexRoot,
            cutoff: now().addingTimeInterval(-codexDiscoveryLookback),
            limit: force ? codexBootstrapFileLimit : codexIncrementalFileLimit
        )
        for candidate in candidates where codexFiles[candidate.url] == nil {
            let tracked = AITrackedFile(url: candidate.url)
            codexFiles[candidate.url] = tracked
            try scanWholeFile(tracked: tracked, processor: processCodexChunk(_:chunk:))
        }
    }

    private func discoverClaude(force: Bool) throws {
        if !force, now().timeIntervalSince(lastClaudeDiscovery) < claudeDiscoveryInterval {
            return
        }
        lastClaudeDiscovery = now()

        let candidates = try enumerateRecentJSONLFiles(
            root: claudeRoot,
            cutoff: now().addingTimeInterval(-claudeDiscoveryLookback),
            limit: 64
        )
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
                let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
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
            guard let raw, raw.totalTokens > 0 else {
                continue
            }

            recordRateSample(at: timestamp, tokenDelta: raw.totalTokens)
            if timestamp > codexCutoffDate {
                codexLiveTokens += raw.totalTokens
                if Calendar.current.isDate(timestamp, inSameDayAs: now()) {
                    codexLiveTodayTokens += raw.totalTokens
                }
            }
        }
    }

    private func processClaudeChunk(_ tracked: AITrackedFile, chunk: String) throws {
        for line in completeLines(for: tracked, chunk: chunk) {
            guard
                let data = line.data(using: .utf8),
                let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                let timestampString = object["timestamp"] as? String,
                let timestamp = parseTimestamp(timestampString),
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
            recordRateSample(at: timestamp, tokenDelta: total)
            if timestamp > claudeCutoffDate {
                claudeLiveTokens += total
                if Calendar.current.isDate(timestamp, inSameDayAs: now()) {
                    claudeLiveTodayTokens += total
                }
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
        let total = explicitTotal > 0 ? explicitTotal : (input + cached + output + reasoning)
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

    private static func resolveSnapshotURL(in root: URL, fileName: String) -> URL? {
        let candidates = [
            root.appendingPathComponent("usage-data/\(fileName)", isDirectory: false),
            root.appendingPathComponent("web/src/data/\(fileName)", isDirectory: false),
            root.appendingPathComponent("src/data/\(fileName)", isDirectory: false),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func freshestExistingRoot(from candidates: [URL]) -> URL? {
        let fileManager = FileManager.default
        var bestRoot: URL?
        var bestDate = Date.distantPast

        for candidate in candidates {
            guard fileManager.fileExists(atPath: candidate.path),
                  let date = latestJSONLModificationDate(in: candidate),
                  date > bestDate
            else {
                continue
            }
            bestDate = date
            bestRoot = candidate
        }

        return bestRoot
    }

    private static func latestJSONLModificationDate(in root: URL) -> Date? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var latest: Date?
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true, let modifiedAt = values?.contentModificationDate else {
                continue
            }
            if latest == nil || modifiedAt > latest! {
                latest = modifiedAt
            }
        }
        return latest
    }

    private static func normalizeSessionsRoot(_ url: URL) -> URL {
        if url.lastPathComponent == "sessions" {
            return url
        }
        if url.lastPathComponent == ".codex" {
            return url.appendingPathComponent("sessions", isDirectory: true)
        }
        return url
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
        let cutoff = now().addingTimeInterval(-3_600)
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

    private func rateSeries(within interval: TimeInterval, bucketCount: Int) -> [Double] {
        guard bucketCount > 0 else {
            return []
        }

        let end = now()
        let start = end.addingTimeInterval(-interval)
        let bucketDuration = interval / Double(bucketCount)
        guard bucketDuration > 0 else {
            return Array(repeating: 0, count: bucketCount)
        }

        var buckets = Array(repeating: Double(0), count: bucketCount)
        for sample in rateSamples where sample.date >= start && sample.date <= end {
            let rawIndex = Int(sample.date.timeIntervalSince(start) / bucketDuration)
            let index = max(0, min(bucketCount - 1, rawIndex))
            buckets[index] += Double(max(sample.tokenDelta, 0))
        }

        return buckets.map { $0 / bucketDuration }
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
            do {
                let summary = try self.bootstrapTrackerIfNeeded(force: true)
                self.lastRefreshAt = Date()
                DispatchQueue.main.async {
                    self.onAvailabilityChange?(true)
                    self.onSummary?(summary)
                }
            } catch {
                DebugTrace.log("AIUsageMonitor start failed error=\(String(describing: error))")
                DispatchQueue.main.async {
                    self.onAvailabilityChange?(false)
                }
            }
        }
    }

    func tick() {
        queue.async { [weak self] in
            guard let self, !self.tickInFlight else { return }
            let now = Date()
            guard now.timeIntervalSince(self.lastRefreshAt) >= self.minimumRefreshInterval else {
                return
            }
            self.tickInFlight = true
            self.lastRefreshAt = now
            defer { self.tickInFlight = false }

            do {
                let tracker = try self.tracker ?? self.makeTracker()
                try tracker.tick()
                let summary = tracker.summary()
                self.tracker = tracker
                DispatchQueue.main.async {
                    self.onAvailabilityChange?(true)
                    self.onSummary?(summary)
                }
            } catch {
                self.tracker = nil
                DebugTrace.log("AIUsageMonitor tick failed error=\(String(describing: error))")
                DispatchQueue.main.async {
                    self.onAvailabilityChange?(false)
                }
            }
        }
    }

    private func bootstrapTrackerIfNeeded(force: Bool) throws -> AIUsageSummary {
        if !force, let tracker {
            return tracker.summary()
        }

        let tracker = try makeTracker()
        try tracker.bootstrap()
        self.tracker = tracker
        return tracker.summary()
    }

    private func makeTracker() throws -> AIUsageTracker {
        try AIUsageTracker()
    }
}
