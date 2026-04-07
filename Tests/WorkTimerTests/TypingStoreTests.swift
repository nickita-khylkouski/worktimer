import Foundation
import Testing
@testable import WorkTimer

struct TypingStoreTests {
    @Test
    func insertsAndPurgesExpiredSnippets() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let databaseURL = root.appendingPathComponent("worktimer.sqlite")
        let store = try TypingStore(databaseURL: databaseURL)

        let expired = CapturedSnippet(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 110),
            context: CaptureContext(appName: "Terminal", bundleIdentifier: "com.apple.Terminal", sessionKey: "terminal"),
            text: "expired"
        )
        let fresh = CapturedSnippet(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 200),
            expiresAt: Date(timeIntervalSince1970: 600),
            context: CaptureContext(appName: "Cursor", bundleIdentifier: "com.todesktop.cursor", sessionKey: "cursor"),
            text: "fresh"
        )

        try store.insert(expired)
        try store.insert(fresh)

        _ = try store.purgeExpired(now: Date(timeIntervalSince1970: 300))
        let snippets = try store.recentSnippets(now: Date(timeIntervalSince1970: 300))

        #expect(snippets.count == 1)
        #expect(snippets.first?.text == "fresh")
    }

    @Test
    func summarizesTypingSessions() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let databaseURL = root.appendingPathComponent("worktimer.sqlite")
        let store = try TypingStore(databaseURL: databaseURL)
        let context = CaptureContext(appName: "Terminal", bundleIdentifier: "com.apple.Terminal", sessionKey: "terminal")

        try store.insert(
            TypingSessionRecord(
                id: UUID(),
                startedAt: Date(timeIntervalSince1970: 100),
                endedAt: Date(timeIntervalSince1970: 130),
                context: context,
                characterCount: 120
            )
        )
        try store.insert(
            TypingSessionRecord(
                id: UUID(),
                startedAt: Date(timeIntervalSince1970: 200),
                endedAt: Date(timeIntervalSince1970: 215),
                context: context,
                characterCount: 45
            )
        )

        let summary = try store.typingSummary(
            from: Date(timeIntervalSince1970: 0),
            to: Date(timeIntervalSince1970: 500)
        )

        #expect(summary.duration == 45)
        #expect(summary.characterCount == 165)
    }

    @Test
    func persistsSessionHistoryAndSettings() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let databaseURL = root.appendingPathComponent("worktimer.sqlite")
        let store = try TypingStore(databaseURL: databaseURL)
        let day = Date(timeIntervalSince1970: 1_000)

        let session = PersistedSession(
            isRunning: true,
            logEntries: [TimerLogEntry(kind: .paused, occurredAt: day, elapsedSnapshot: 42)],
            pauseCount: 1,
            resumeCount: 0,
            resetCount: 0,
            launchedAt: day,
            currentTime: day.addingTimeInterval(42),
            sessionRunDurations: [42],
            totalPausedDuration: 0,
            longestRunDuration: 42,
            lastResetElapsed: nil,
            accumulatedElapsed: 42,
            runningSince: day,
            pausedSince: nil,
            currentDayStart: day,
            mouseStoredDuration: 5,
            mouseStoredDistance: 120,
            activeMouseStartedAt: nil,
            activeMouseLastMovedAt: nil,
            activeMouseDistance: nil
        )
        let summaries = [
            DailyWorkSummary(
                dayStart: day,
                workedSeconds: 60,
                earningsAmount: 2.5,
                pauseCount: 1,
                resetCount: 0,
                mouseDistance: 120
            )
        ]

        try store.setString("typingTime", for: "menuBarDisplayMode")
        try store.setDouble(45.5, for: "hourlyRate")
        try store.saveSession(session)
        try store.saveDailySummaries(summaries)

        #expect(try store.stringSetting(for: "menuBarDisplayMode") == "typingTime")
        #expect(try store.doubleSetting(for: "hourlyRate") == 45.5)
        #expect(try store.loadSession() == session)
        #expect(try store.loadDailySummaries() == summaries)
    }
}
