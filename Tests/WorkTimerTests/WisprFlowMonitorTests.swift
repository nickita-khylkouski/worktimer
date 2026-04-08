import Foundation
import SQLite3
import Testing
@testable import WorkTimer

private let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct WisprFlowMonitorTests {
    @Test
    func loadsTodayWordsDurationAndClipCount() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let databaseURL = root.appendingPathComponent("flow.sqlite")
        try createHistoryDatabase(at: databaseURL)

        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let formatter = localTimestampFormatter()

        try insertHistoryRow(
            databaseURL: databaseURL,
            id: "today-1",
            numWords: 120,
            duration: 32.5,
            timestamp: formatter.string(from: startOfToday.addingTimeInterval(3_600)),
            isArchived: false
        )
        try insertHistoryRow(
            databaseURL: databaseURL,
            id: "today-2",
            numWords: 80,
            duration: 24.25,
            timestamp: formatter.string(from: startOfToday.addingTimeInterval(7_200)),
            isArchived: false
        )
        try insertHistoryRow(
            databaseURL: databaseURL,
            id: "old",
            numWords: 999,
            duration: 300,
            timestamp: formatter.string(from: startOfToday.addingTimeInterval(-86_400)),
            isArchived: false
        )
        try insertHistoryRow(
            databaseURL: databaseURL,
            id: "archived",
            numWords: 999,
            duration: 300,
            timestamp: formatter.string(from: startOfToday.addingTimeInterval(10_800)),
            isArchived: true
        )

        let summary = try WisprFlowMonitor.loadSummary(databaseURL: databaseURL, referenceDate: now)

        #expect(summary.wordsToday == 200)
        #expect(summary.clipsToday == 2)
        #expect(abs(summary.dictationDurationToday - 56.75) < 0.001)
        #expect(summary.wordsTodayText == "200")
        #expect(summary.clipsTodayText == "2")
    }

    @Test
    func defaultDatabaseURLUsesOverrideWhenPresent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let databaseURL = root.appendingPathComponent("custom-flow.sqlite")
        FileManager.default.createFile(atPath: databaseURL.path, contents: Data())

        let key = "WORKTIMER_WISPR_FLOW_DB"
        let previous = getenv(key).map { String(cString: $0) }
        setenv(key, databaseURL.path, 1)
        defer {
            if let previous {
                setenv(key, previous, 1)
            } else {
                unsetenv(key)
            }
        }

        #expect(WisprFlowMonitor.defaultDatabaseURL() == databaseURL)
    }

    private func createHistoryDatabase(at url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            defer { sqlite3_close(database) }
            throw testError("Failed to create temp Wispr Flow database")
        }
        defer { sqlite3_close(database) }

        let sql = """
        CREATE TABLE History (
            transcriptEntityId TEXT PRIMARY KEY NOT NULL,
            timestamp DATETIME,
            duration FLOAT,
            numWords INTEGER,
            isArchived TINYINT(1) NOT NULL DEFAULT 0
        );
        """

        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw testError(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func insertHistoryRow(
        databaseURL: URL,
        id: String,
        numWords: Int,
        duration: Double,
        timestamp: String,
        isArchived: Bool
    ) throws {
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
            defer { sqlite3_close(database) }
            throw testError("Failed to open temp Wispr Flow database")
        }
        defer { sqlite3_close(database) }

        let sql = """
        INSERT INTO History (transcriptEntityId, timestamp, duration, numWords, isArchived)
        VALUES (?1, ?2, ?3, ?4, ?5);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw testError(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        _ = id.withCString { value in
            sqlite3_bind_text(statement, 1, value, -1, sqliteTransientDestructor)
        }
        _ = timestamp.withCString { value in
            sqlite3_bind_text(statement, 2, value, -1, sqliteTransientDestructor)
        }
        sqlite3_bind_double(statement, 3, duration)
        sqlite3_bind_int64(statement, 4, Int64(numWords))
        sqlite3_bind_int(statement, 5, isArchived ? 1 : 0)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw testError(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func localTimestampFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS XXXXX"
        return formatter
    }

    private func testError(_ message: String) -> NSError {
        NSError(domain: "WisprFlowMonitorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
