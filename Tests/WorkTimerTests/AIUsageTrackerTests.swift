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

struct AIUsageTrackerTests {
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
