import Foundation
import Testing
@testable import WorkTimer

@Suite(.serialized)
@MainActor
struct AppModelTests {
    @Test
    func pauseResumeAndResetCreateTimestampedLogEntries() {
        withCleanDefaults {
            let start = Date(timeIntervalSince1970: 1_000)
            let model = AppModel(now: start, installsStatusItem: false)

            model.toggleRunning(at: start.addingTimeInterval(5))
            model.toggleRunning(at: start.addingTimeInterval(8))
            model.resetTimer(at: start.addingTimeInterval(12))

            #expect(model.pauseCount == 1)
            #expect(model.resumeCount == 1)
            #expect(model.resetCount == 1)
            #expect(model.logEntries.count == 3)
            #expect(model.logEntries[0].kind == .reset)
            #expect(model.logEntries[0].elapsedSnapshot == 9)
            #expect(model.logEntries[1].kind == .resumed)
            #expect(model.logEntries[1].occurredAt == start.addingTimeInterval(8))
            #expect(model.logEntries[2].kind == .paused)
            #expect(model.logEntries[2].elapsedSnapshot == 5)
            #expect(model.elapsedText == "0:00:00")
            #expect(model.cumulativeRunText == "0:00:09")
            #expect(model.totalPausedText == "0:00:03")
            #expect(model.longestRunText == "0:00:05")
            #expect(model.completedRunCount == 2)
            #expect(model.lastResetText == "0:00:09")
        }
    }

    @Test
    func resetWhilePausedKeepsTimerPausedAtZero() {
        withCleanDefaults {
            let start = Date(timeIntervalSince1970: 2_000)
            let model = AppModel(now: start, installsStatusItem: false)

            model.toggleRunning(at: start.addingTimeInterval(7))
            model.resetTimer(at: start.addingTimeInterval(9))

            #expect(model.isRunning == false)
            #expect(model.elapsedText == "0:00:00")
            #expect(model.logEntries.first?.kind == .reset)
            #expect(model.logEntries.first?.elapsedSnapshot == 7)
            #expect(model.currentPhaseLabel == "Current Pause")
            #expect(model.cumulativeRunText == "0:00:07")
            #expect(model.longestRunText == "0:00:07")
        }
    }

    @Test
    func resetAndStartResumesAfterPauseAndPreservesSessionStats() {
        withCleanDefaults {
            let start = Date(timeIntervalSince1970: 3_000)
            let model = AppModel(now: start, installsStatusItem: false)

            model.toggleRunning(at: start.addingTimeInterval(10))
            model.resetAndStart(at: start.addingTimeInterval(16))

            #expect(model.isRunning == true)
            #expect(model.elapsedText == "0:00:00")
            #expect(model.resetCount == 1)
            #expect(model.resumeCount == 1)
            #expect(model.pauseCount == 1)
            #expect(model.totalPausedText == "0:00:06")
            #expect(model.cumulativeRunText == "0:00:10")
            #expect(model.actionCount == 3)
            #expect(model.logEntries[0].kind == .resumed)
            #expect(model.logEntries[1].kind == .reset)
            #expect(model.logEntries[2].kind == .paused)
        }
    }

    @Test
    func dayRolloverArchivesPreviousDayAndResetsCurrentTimer() {
        withCleanDefaults {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .autoupdatingCurrent
            let start = calendar.date(from: DateComponents(
                year: 2026,
                month: 4,
                day: 7,
                hour: 23,
                minute: 59,
                second: 50
            ))!
            let model = AppModel(now: start, installsStatusItem: false)

            model.advance(to: start.addingTimeInterval(15))

            #expect(model.elapsedText == "0:00:05")
            #expect(model.cumulativeRunText == "0:00:05")
            #expect(model.dailySummaries.count == 2)
            #expect(calendar.isDate(model.dailySummaries[0].dayStart, inSameDayAs: start.addingTimeInterval(15)))
            #expect(model.dailySummaries[1].workedText == "0:00:10")
        }
    }

    @Test
    func earningsIncreaseWithWorkedTimeAndHourlyRate() {
        withCleanDefaults {
            let start = Date(timeIntervalSince1970: 4_000)
            let model = AppModel(now: start, installsStatusItem: false)

            model.hourlyRate = 60
            model.advance(to: start.addingTimeInterval(30))
            model.menuBarDisplayMode = .earnings

            #expect(model.currentEarnings == 0.5)
            #expect(model.currentEarningsText == "$0.50")
            #expect(model.topBarText == "$0.50")
            #expect(model.hourlyRateText == "$60.00/hr")
        }
    }

    @Test
    func relaunchRestoresCurrentDaySessionFromDisk() {
        withCleanDefaults {
            let start = Date(timeIntervalSince1970: 5_000)
            let firstLaunch = AppModel(now: start, installsStatusItem: false)

            firstLaunch.hourlyRate = 120
            firstLaunch.advance(to: start.addingTimeInterval(45))

            let relaunched = AppModel(now: start.addingTimeInterval(75), installsStatusItem: false)

            #expect(relaunched.elapsedText == "0:01:15")
            #expect(relaunched.cumulativeRunText == "0:01:15")
            #expect(relaunched.currentEarningsText == "$2.50")
            #expect(relaunched.dailySummaries.count == 1)
        }
    }

    @Test
    func typingStatsKeepShortPausesInsideOneSessionAndStopAfterIdle() {
        withCleanDefaults {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            let databaseURL = root.appendingPathComponent("typing.sqlite")
            let start = Date(timeIntervalSince1970: 6_000)
            let context = CaptureContext(appName: "Terminal", bundleIdentifier: "com.apple.Terminal", sessionKey: "terminal")
            let model = AppModel(now: start, installsStatusItem: false, typingDatabaseURL: databaseURL)

            model.recordTypingInput(TypingInput(context: context, mutation: .text("hello")), at: start)
            model.recordTypingInput(TypingInput(context: context, mutation: .text("world")), at: start.addingTimeInterval(4))

            #expect(model.isTyping == true)
            #expect(model.typingCharacterCountText == "10")
            #expect(model.typingTimeText == "0:00:04")

            model.advance(to: start.addingTimeInterval(10))

            #expect(model.isTyping == false)
            #expect(model.typingCharacterCountText == "10")
            #expect(model.typingTimeText == "0:00:04")
            #expect(model.typingCharactersPerMinuteText == "150")
            #expect(model.typingWordsPerMinuteText == "30")

            model.menuBarDisplayMode = .charactersPerMinute
            #expect(model.topBarText == "150 CPM")
        }
    }

    @Test
    func typingGraceWindowRevertsIfUserDoesNotResume() {
        withCleanDefaults {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            let databaseURL = root.appendingPathComponent("typing.sqlite")
            let start = Date(timeIntervalSince1970: 6_500)
            let context = CaptureContext(appName: "Superset", bundleIdentifier: "app.superset", sessionKey: "superset")
            let model = AppModel(now: start, installsStatusItem: false, typingDatabaseURL: databaseURL)

            model.recordTypingInput(TypingInput(context: context, mutation: .text("a")), at: start)
            model.advance(to: start.addingTimeInterval(3))

            #expect(model.isTyping == true)
            #expect(model.typingTimeText == "0:00:03")

            model.advance(to: start.addingTimeInterval(6))

            #expect(model.isTyping == false)
            #expect(model.typingTimeText == "0:00:01")
        }
    }

    @Test
    func mouseStatsKeepShortPausesInsideOneSessionAndStopAfterIdle() {
        withCleanDefaults {
            let start = Date(timeIntervalSince1970: 7_000)
            let model = AppModel(now: start, installsStatusItem: false)

            model.recordMouseMovement(
                MouseMovementSample(pointDistance: 12, estimatedMillimeters: 25.4),
                at: start
            )
            model.recordMouseMovement(
                MouseMovementSample(pointDistance: 8, estimatedMillimeters: 12.7),
                at: start.addingTimeInterval(1)
            )

            #expect(model.isMouseMoving == true)
            #expect(model.mouseDistanceText == "0.12 ft")
            #expect(model.mouseMoveTimeText == "0:00:01")

            model.advance(to: start.addingTimeInterval(4))

            #expect(model.isMouseMoving == false)
            #expect(model.mouseDistanceText == "0.12 ft")
            #expect(model.mouseMoveTimeText == "0:00:03")
            #expect(model.mouseDistancePerMinuteText == "2.50 ft")

            model.menuBarDisplayMode = .mouseDistance
            #expect(model.topBarText == "0.12 ft")
            #expect(abs((model.todaySummary.mouseDistance ?? 0) - 38.1) < 0.001)
        }
    }

    private func withCleanDefaults(_ body: () -> Void) {
        clearDefaults()
        body()
        clearDefaults()
    }

    private func clearDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "menuBarDisplayMode")
        defaults.removeObject(forKey: "hourlyRate")
        defaults.removeObject(forKey: "dayHistory")
        if let sessionFileURL = try? sessionFileURL() {
            try? FileManager.default.removeItem(at: sessionFileURL)
        }
    }

    private func sessionFileURL() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("WorkTimer", isDirectory: true)

        return directory.appendingPathComponent("session.json", isDirectory: false)
    }
}
