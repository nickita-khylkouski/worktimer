import Foundation
import Testing
@testable import WorkTimer

private func writeAIUsageFixture(_ url: URL, _ text: String) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.data(using: .utf8)!.write(to: url)
}

private func isoDate(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)!
}

@Suite(.serialized)
struct AIUsageTrackerTests {
    @Test
    func snapshotRootCandidatesIncludeAncestorRepos() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repoRoot = root.appendingPathComponent("workspace/nested/repo", isDirectory: true)
        let previousDirectory = FileManager.default.currentDirectoryPath
        try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)
        let snapshotURL = root.appendingPathComponent("workspace/usage-data/codex-usage.json")
        try writeAIUsageFixture(snapshotURL, #"{"totals":{"totalTokens":10,"costUSD":0}}"#)

        FileManager.default.changeCurrentDirectoryPath(repoRoot.path)
        defer { FileManager.default.changeCurrentDirectoryPath(previousDirectory) }

        let candidates = AIUsageTracker.snapshotRootCandidates(explicitSiteRoot: nil)

        #expect(candidates.contains(root.appendingPathComponent("workspace", isDirectory: true).standardizedFileURL))
    }

    @Test
    func defaultSiteRootPrefersFreshestSnapshotRoot() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let staleRoot = root.appendingPathComponent("stale-root", isDirectory: true)
        let freshRoot = root.appendingPathComponent("fresh-root", isDirectory: true)

        let staleCodex = staleRoot.appendingPathComponent("web/src/data/codex-usage.json")
        let staleClaude = staleRoot.appendingPathComponent("web/src/data/claude-usage.json")
        let freshCodex = freshRoot.appendingPathComponent("usage-data/codex-usage.json")
        let freshClaude = freshRoot.appendingPathComponent("usage-data/claude-usage.json")

        try writeAIUsageFixture(staleCodex, #"{"totals":{"totalTokens":10,"costUSD":0}}"#)
        try writeAIUsageFixture(staleClaude, #"{"totals":{"totalTokens":20,"totalCost":0}}"#)
        try writeAIUsageFixture(freshCodex, #"{"totals":{"totalTokens":30,"costUSD":0}}"#)
        try writeAIUsageFixture(freshClaude, #"{"totals":{"totalTokens":40,"totalCost":0}}"#)

        let staleTime = isoDate("2026-04-05T20:18:15Z")
        let freshTime = isoDate("2026-04-08T13:15:38Z")
        try FileManager.default.setAttributes([.modificationDate: staleTime], ofItemAtPath: staleCodex.path)
        try FileManager.default.setAttributes([.modificationDate: staleTime], ofItemAtPath: staleClaude.path)
        try FileManager.default.setAttributes([.modificationDate: freshTime], ofItemAtPath: freshCodex.path)
        try FileManager.default.setAttributes([.modificationDate: freshTime], ofItemAtPath: freshClaude.path)

        let resolved = AIUsageTracker.preferredSiteRoot(from: [staleRoot, freshRoot])

        #expect(resolved == freshRoot)
    }

    @Test
    func preferredSnapshotURLResolvesEachProviderIndependently() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let codexRoot = root.appendingPathComponent("codex-root", isDirectory: true)
        let claudeRoot = root.appendingPathComponent("claude-root", isDirectory: true)

        let codexURL = codexRoot.appendingPathComponent("usage-data/codex-usage.json")
        let claudeURL = claudeRoot.appendingPathComponent("usage-data/claude-usage.json")
        try writeAIUsageFixture(codexURL, #"{"totals":{"totalTokens":30,"costUSD":0}}"#)
        try writeAIUsageFixture(claudeURL, #"{"totals":{"totalTokens":40,"totalCost":0}}"#)

        let codexTime = isoDate("2026-04-08T13:15:37Z")
        let claudeTime = isoDate("2026-04-08T13:15:38Z")
        try FileManager.default.setAttributes([.modificationDate: codexTime], ofItemAtPath: codexURL.path)
        try FileManager.default.setAttributes([.modificationDate: claudeTime], ofItemAtPath: claudeURL.path)

        let candidates = [codexRoot, claudeRoot]
        #expect(AIUsageTracker.preferredSnapshotURL(fileName: "codex-usage.json", candidates: candidates) == codexURL)
        #expect(AIUsageTracker.preferredSnapshotURL(fileName: "claude-usage.json", candidates: candidates) == claudeURL)
    }

    @Test
    func tickReloadsSnapshotTotalsAfterJsonChanges() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let siteRoot = root.appendingPathComponent("site", isDirectory: true)
        let codexRoot = root.appendingPathComponent("codex", isDirectory: true)
        let claudeRoot = root.appendingPathComponent("claude", isDirectory: true)

        let codexUsage = siteRoot.appendingPathComponent("usage-data/codex-usage.json")
        let claudeUsage = siteRoot.appendingPathComponent("usage-data/claude-usage.json")
        try writeAIUsageFixture(codexUsage, #"{"daily":[{"date":"Apr 08, 2026","totalTokens":100}],"totals":{"totalTokens":100,"costUSD":1.0}}"#)
        try writeAIUsageFixture(claudeUsage, #"{"daily":[{"date":"2026-04-08","totalTokens":50}],"totals":{"totalTokens":50,"totalCost":2.0}}"#)

        var currentTime = isoDate("2026-04-08T18:00:00Z")
        try FileManager.default.setAttributes([.modificationDate: currentTime], ofItemAtPath: codexUsage.path)
        try FileManager.default.setAttributes([.modificationDate: currentTime], ofItemAtPath: claudeUsage.path)

        let tracker = try AIUsageTracker(
            siteRoot: siteRoot,
            codexRoot: codexRoot,
            claudeRoot: claudeRoot,
            now: { currentTime }
        )
        try tracker.bootstrap()
        #expect(tracker.summary().combined.tokens == 150)

        currentTime = isoDate("2026-04-08T18:05:00Z")
        try writeAIUsageFixture(codexUsage, #"{"daily":[{"date":"Apr 08, 2026","totalTokens":120}],"totals":{"totalTokens":120,"costUSD":1.0}}"#)
        try writeAIUsageFixture(claudeUsage, #"{"daily":[{"date":"2026-04-08","totalTokens":80}],"totals":{"totalTokens":80,"totalCost":2.0}}"#)
        try FileManager.default.setAttributes([.modificationDate: currentTime], ofItemAtPath: codexUsage.path)
        try FileManager.default.setAttributes([.modificationDate: currentTime], ofItemAtPath: claudeUsage.path)

        try tracker.tick()
        #expect(tracker.summary().combined.tokens == 200)
        #expect(tracker.summary().combined.todayTokens == 200)
    }

    @Test
    func bootstrapLoadsCodexAndClaudeTotals() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let siteRoot = root.appendingPathComponent("site", isDirectory: true)
        let codexRoot = root.appendingPathComponent("codex", isDirectory: true)
        let claudeRoot = root.appendingPathComponent("claude", isDirectory: true)

        let codexUsage = siteRoot.appendingPathComponent("usage-data/codex-usage.json")
        let claudeUsage = siteRoot.appendingPathComponent("usage-data/claude-usage.json")
        try writeAIUsageFixture(codexUsage, #"{"daily":[{"date":"Apr 07, 2026","totalTokens":1200}],"totals":{"totalTokens":1200,"costUSD":1.0}}"#)
        try writeAIUsageFixture(claudeUsage, #"{"daily":[{"date":"2026-04-07","totalTokens":300}],"totals":{"totalTokens":300,"totalCost":2.0}}"#)

        let cutoff = isoDate("2026-04-07T10:00:00Z")
        try FileManager.default.setAttributes([.modificationDate: cutoff], ofItemAtPath: codexUsage.path)
        try FileManager.default.setAttributes([.modificationDate: cutoff], ofItemAtPath: claudeUsage.path)

        let codexSession = codexRoot.appendingPathComponent("2026/04/07/session.jsonl")
        let claudeSession = claudeRoot.appendingPathComponent("project/claude.jsonl")
        try writeAIUsageFixture(codexSession, """
        {"timestamp":"2026-04-07T17:00:05Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":50,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":50}}}}
        """)
        try writeAIUsageFixture(claudeSession, """
        {"timestamp":"2026-04-07T17:00:10Z","message":{"model":"claude-opus-4-6","usage":{"input_tokens":5,"output_tokens":4,"cache_creation_input_tokens":0,"cache_read_input_tokens":1}}}
        """)
        try FileManager.default.setAttributes([.modificationDate: cutoff.addingTimeInterval(5)], ofItemAtPath: codexSession.path)
        try FileManager.default.setAttributes([.modificationDate: cutoff.addingTimeInterval(5)], ofItemAtPath: claudeSession.path)

        let now = isoDate("2026-04-07T17:01:00Z")
        let tracker = try AIUsageTracker(
            siteRoot: siteRoot,
            codexRoot: codexRoot,
            claudeRoot: claudeRoot,
            now: { now }
        )
        try tracker.bootstrap()
        let summary = tracker.summary()

        #expect(summary.codex.tokens == 1_250)
        #expect(summary.claude.tokens == 310)
        #expect(summary.combined.tokens == 1_560)
        #expect(summary.combined.todayTokens == 1_560)
    }

    @Test
    func rateUsesRollingWindow() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let siteRoot = root.appendingPathComponent("site", isDirectory: true)
        let codexRoot = root.appendingPathComponent("codex", isDirectory: true)
        let claudeRoot = root.appendingPathComponent("claude", isDirectory: true)

        let codexUsage = siteRoot.appendingPathComponent("usage-data/codex-usage.json")
        let claudeUsage = siteRoot.appendingPathComponent("usage-data/claude-usage.json")
        try writeAIUsageFixture(codexUsage, #"{"daily":[],"totals":{"totalTokens":0,"costUSD":0}}"#)
        try writeAIUsageFixture(claudeUsage, #"{"daily":[],"totals":{"totalTokens":0,"totalCost":0}}"#)

        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: cutoff], ofItemAtPath: codexUsage.path)
        try FileManager.default.setAttributes([.modificationDate: cutoff], ofItemAtPath: claudeUsage.path)

        let session = codexRoot.appendingPathComponent("2026/04/07/session.jsonl")
        try writeAIUsageFixture(session, """
        {"timestamp":"2023-11-14T22:13:25Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":40,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":40}}}}
        """)
        try FileManager.default.setAttributes([.modificationDate: cutoff.addingTimeInterval(5)], ofItemAtPath: session.path)

        var currentTime = cutoff.addingTimeInterval(60)
        let tracker = try AIUsageTracker(
            siteRoot: siteRoot,
            codexRoot: codexRoot,
            claudeRoot: claudeRoot,
            now: { currentTime }
        )
        try tracker.bootstrap()
        #expect(abs(tracker.summary().lastMinuteAverageTokensPerSecond - (40.0 / 55.0)) < 0.0001)
        #expect(abs(tracker.summary().lastFiveMinutesAverageTokensPerSecond - (40.0 / 55.0)) < 0.0001)
        #expect(abs(tracker.summary().lastFifteenMinutesAverageTokensPerSecond - (40.0 / 55.0)) < 0.0001)
        #expect(abs(tracker.summary().lastHourAverageTokensPerSecond - (40.0 / 55.0)) < 0.0001)

        let handle = try FileHandle(forWritingTo: session)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("""
        {"timestamp":"2023-11-14T22:13:35Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":20,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":20}}}}

        """.utf8))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: cutoff.addingTimeInterval(15)], ofItemAtPath: session.path)

        currentTime = cutoff.addingTimeInterval(80)
        try tracker.tick()

        #expect(tracker.summary().combined.tokens == 60)
        #expect(tracker.summary().lastMinuteAverageTokensPerSecond == 0)
        #expect(abs(tracker.summary().lastFiveMinutesAverageTokensPerSecond - (60.0 / 75.0)) < 0.0001)
        #expect(abs(tracker.summary().lastFifteenMinutesAverageTokensPerSecond - (60.0 / 75.0)) < 0.0001)
        #expect(abs(tracker.summary().lastHourAverageTokensPerSecond - (60.0 / 75.0)) < 0.0001)
    }

    @Test
    func codexDuplicateTotalTokenRowsDoNotDoubleCount() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let siteRoot = root.appendingPathComponent("site", isDirectory: true)
        let codexRoot = root.appendingPathComponent("codex", isDirectory: true)
        let claudeRoot = root.appendingPathComponent("claude", isDirectory: true)

        let codexUsage = siteRoot.appendingPathComponent("usage-data/codex-usage.json")
        let claudeUsage = siteRoot.appendingPathComponent("usage-data/claude-usage.json")
        try writeAIUsageFixture(codexUsage, #"{"daily":[],"totals":{"totalTokens":0,"costUSD":0}}"#)
        try writeAIUsageFixture(claudeUsage, #"{"daily":[],"totals":{"totalTokens":0,"totalCost":0}}"#)

        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: cutoff], ofItemAtPath: codexUsage.path)
        try FileManager.default.setAttributes([.modificationDate: cutoff], ofItemAtPath: claudeUsage.path)

        let session = codexRoot.appendingPathComponent("2026/04/07/session.jsonl")
        try writeAIUsageFixture(session, """
        {"timestamp":"2023-11-14T22:13:24Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":20,"cached_input_tokens":0,"output_tokens":5,"reasoning_output_tokens":0,"total_tokens":25},"total_token_usage":{"input_tokens":20,"cached_input_tokens":0,"output_tokens":5,"reasoning_output_tokens":0,"total_tokens":25}}}}
        {"timestamp":"2023-11-14T22:13:30Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":20,"cached_input_tokens":0,"output_tokens":5,"reasoning_output_tokens":0,"total_tokens":25},"total_token_usage":{"input_tokens":20,"cached_input_tokens":0,"output_tokens":5,"reasoning_output_tokens":0,"total_tokens":25}}}}
        """)
        try FileManager.default.setAttributes([.modificationDate: cutoff.addingTimeInterval(10)], ofItemAtPath: session.path)

        let tracker = try AIUsageTracker(
            siteRoot: siteRoot,
            codexRoot: codexRoot,
            claudeRoot: claudeRoot,
            now: { cutoff.addingTimeInterval(40) }
        )
        try tracker.bootstrap()

        #expect(tracker.summary().codex.tokens == 25)
    }

    @Test
    func snapshotlessTrackerStillBuildsRatesFromLiveLogs() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let emptySiteRoot = root.appendingPathComponent("empty-site", isDirectory: true)
        let codexRoot = root.appendingPathComponent("codex", isDirectory: true)
        let claudeRoot = root.appendingPathComponent("claude", isDirectory: true)

        let session = codexRoot.appendingPathComponent("2026/04/07/session.jsonl")
        try writeAIUsageFixture(session, """
        {"timestamp":"2026-04-07T17:00:05Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":40,"cached_input_tokens":10,"output_tokens":5,"reasoning_output_tokens":5,"total_tokens":60}}}}
        """)
        let now = isoDate("2026-04-07T17:00:30Z")
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: session.path)

        let tracker = try AIUsageTracker(
            siteRoot: emptySiteRoot,
            codexRoot: codexRoot,
            claudeRoot: claudeRoot,
            supersetSessionLogRoot: root.appendingPathComponent("superset", isDirectory: true),
            now: { now }
        )
        try tracker.bootstrap()
        let summary = tracker.summary()

        #expect(summary.codex.tokens == 60)
        #expect(summary.combined.tokens == 60)
        #expect(summary.lastMinuteAverageTokensPerSecond > 0)
    }

    @Test
    func snapshotlessBootstrapScansFullHistoryForTotals() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let emptySiteRoot = root.appendingPathComponent("empty-site", isDirectory: true)
        let codexRoot = root.appendingPathComponent("codex", isDirectory: true)
        let claudeRoot = root.appendingPathComponent("claude", isDirectory: true)

        let oldCodexSession = codexRoot.appendingPathComponent("2026/01/07/session.jsonl")
        let oldClaudeSession = claudeRoot.appendingPathComponent("project/claude.jsonl")
        try writeAIUsageFixture(oldCodexSession, """
        {"timestamp":"2026-01-07T17:00:05Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":90,"cached_input_tokens":5,"output_tokens":3,"reasoning_output_tokens":2,"total_tokens":100}}}}
        """)
        try writeAIUsageFixture(oldClaudeSession, """
        {"timestamp":"2026-01-07T17:00:10Z","message":{"model":"claude-opus-4-6","usage":{"input_tokens":7,"output_tokens":8,"cache_creation_input_tokens":9,"cache_read_input_tokens":6}}}
        """)

        let now = isoDate("2026-04-08T17:00:00Z")
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: oldCodexSession.path)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: oldClaudeSession.path)

        let tracker = try AIUsageTracker(
            siteRoot: emptySiteRoot,
            codexRoot: codexRoot,
            claudeRoot: claudeRoot,
            supersetSessionLogRoot: root.appendingPathComponent("superset", isDirectory: true),
            now: { now }
        )
        try tracker.bootstrap()
        let summary = tracker.summary()

        #expect(summary.codex.tokens == 100)
        #expect(summary.claude.tokens == 30)
        #expect(summary.combined.tokens == 130)
    }

    @Test
    func directSnapshotFileOverridesTakePrecedence() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let siteRoot = root.appendingPathComponent("site", isDirectory: true)
        let codexRoot = root.appendingPathComponent("codex", isDirectory: true)
        let claudeRoot = root.appendingPathComponent("claude", isDirectory: true)
        let overrideCodex = root.appendingPathComponent("override/codex-usage.json")
        let overrideClaude = root.appendingPathComponent("override/claude-usage.json")

        try writeAIUsageFixture(siteRoot.appendingPathComponent("usage-data/codex-usage.json"), #"{"daily":[],"totals":{"totalTokens":10,"costUSD":0}}"#)
        try writeAIUsageFixture(siteRoot.appendingPathComponent("usage-data/claude-usage.json"), #"{"daily":[],"totals":{"totalTokens":20,"totalCost":0}}"#)
        try writeAIUsageFixture(overrideCodex, #"{"daily":[],"totals":{"totalTokens":111,"costUSD":0}}"#)
        try writeAIUsageFixture(overrideClaude, #"{"daily":[],"totals":{"totalTokens":222,"totalCost":0}}"#)

        setenv("WORKTIMER_CODEX_USAGE_JSON", overrideCodex.path, 1)
        setenv("WORKTIMER_CLAUDE_USAGE_JSON", overrideClaude.path, 1)
        defer {
            unsetenv("WORKTIMER_CODEX_USAGE_JSON")
            unsetenv("WORKTIMER_CLAUDE_USAGE_JSON")
        }

        let tracker = try AIUsageTracker(
            siteRoot: siteRoot,
            codexRoot: codexRoot,
            claudeRoot: claudeRoot,
            now: { isoDate("2026-04-08T17:00:00Z") }
        )
        try tracker.bootstrap()
        let summary = tracker.summary()

        #expect(summary.codex.tokens == 111)
        #expect(summary.claude.tokens == 222)
        #expect(summary.combined.tokens == 333)
    }

    @Test
    func malformedJsonLinesDoNotKillTracker() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let emptySiteRoot = root.appendingPathComponent("empty-site", isDirectory: true)
        let codexRoot = root.appendingPathComponent("codex", isDirectory: true)
        let claudeRoot = root.appendingPathComponent("claude", isDirectory: true)

        let session = codexRoot.appendingPathComponent("2026/04/07/session.jsonl")
        try writeAIUsageFixture(session, """
        this is not json
        {"timestamp":"2026-04-07T17:00:05Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":40,"cached_input_tokens":10,"output_tokens":5,"reasoning_output_tokens":5,"total_tokens":60}}}}
        """)
        let now = isoDate("2026-04-07T17:00:30Z")
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: session.path)

        let tracker = try AIUsageTracker(
            siteRoot: emptySiteRoot,
            codexRoot: codexRoot,
            claudeRoot: claudeRoot,
            supersetSessionLogRoot: root.appendingPathComponent("superset", isDirectory: true),
            now: { now }
        )
        try tracker.bootstrap()
        let summary = tracker.summary()

        #expect(summary.codex.tokens == 60)
        #expect(summary.lastMinuteAverageTokensPerSecond > 0)
    }

    @Test
    func rateSamplesIgnoreSnapshotCutoffEvenWhenTotalsDoNot() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let siteRoot = root.appendingPathComponent("site", isDirectory: true)
        let codexRoot = root.appendingPathComponent("codex", isDirectory: true)
        let claudeRoot = root.appendingPathComponent("claude", isDirectory: true)

        let codexUsage = siteRoot.appendingPathComponent("usage-data/codex-usage.json")
        let claudeUsage = siteRoot.appendingPathComponent("usage-data/claude-usage.json")
        try writeAIUsageFixture(codexUsage, #"{"daily":[],"totals":{"totalTokens":1000,"costUSD":0}}"#)
        try writeAIUsageFixture(claudeUsage, #"{"daily":[],"totals":{"totalTokens":0,"totalCost":0}}"#)

        let snapshotTime = isoDate("2026-04-07T18:00:00Z")
        try FileManager.default.setAttributes([.modificationDate: snapshotTime], ofItemAtPath: codexUsage.path)
        try FileManager.default.setAttributes([.modificationDate: snapshotTime], ofItemAtPath: claudeUsage.path)

        let session = codexRoot.appendingPathComponent("2026/04/07/session.jsonl")
        try writeAIUsageFixture(session, """
        {"timestamp":"2026-04-07T17:59:50Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":50,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":50}}}}
        """)
        try FileManager.default.setAttributes([.modificationDate: snapshotTime.addingTimeInterval(5)], ofItemAtPath: session.path)

        let now = isoDate("2026-04-07T18:00:20Z")
        let tracker = try AIUsageTracker(
            siteRoot: siteRoot,
            codexRoot: codexRoot,
            claudeRoot: claudeRoot,
            supersetSessionLogRoot: root.appendingPathComponent("superset", isDirectory: true),
            now: { now }
        )
        try tracker.bootstrap()
        let summary = tracker.summary()

        #expect(summary.codex.tokens == 1_000)
        #expect(summary.lastMinuteAverageTokensPerSecond > 0)
    }

    @Test
    func thirtyMinuteSeriesRetainsOlderRecentSamples() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let siteRoot = root.appendingPathComponent("site", isDirectory: true)
        let codexRoot = root.appendingPathComponent("codex", isDirectory: true)
        let claudeRoot = root.appendingPathComponent("claude", isDirectory: true)

        let codexUsage = siteRoot.appendingPathComponent("usage-data/codex-usage.json")
        let claudeUsage = siteRoot.appendingPathComponent("usage-data/claude-usage.json")
        try writeAIUsageFixture(codexUsage, #"{"daily":[],"totals":{"totalTokens":0,"costUSD":0}}"#)
        try writeAIUsageFixture(claudeUsage, #"{"daily":[],"totals":{"totalTokens":0,"totalCost":0}}"#)

        let now = isoDate("2026-04-07T17:30:00Z")
        let cutoff = isoDate("2026-04-07T16:00:00Z")
        try FileManager.default.setAttributes([.modificationDate: cutoff], ofItemAtPath: codexUsage.path)
        try FileManager.default.setAttributes([.modificationDate: cutoff], ofItemAtPath: claudeUsage.path)

        let session = codexRoot.appendingPathComponent("2026/04/07/session.jsonl")
        try writeAIUsageFixture(session, """
        {"timestamp":"2026-04-07T17:05:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":60,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":60}}}}
        """)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: session.path)

        let tracker = try AIUsageTracker(
            siteRoot: siteRoot,
            codexRoot: codexRoot,
            claudeRoot: claudeRoot,
            supersetSessionLogRoot: root.appendingPathComponent("superset", isDirectory: true),
            now: { now }
        )
        try tracker.bootstrap()
        let summary = tracker.summary()

        #expect(summary.lastThirtyMinutesRateSeries.count == 30)
        #expect(summary.lastThirtyMinutesRateSeries.contains(where: { $0 > 0 }))
    }
}
