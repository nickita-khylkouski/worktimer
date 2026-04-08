import Foundation
import SQLite3

private let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct WisprFlowSummary: Equatable, Sendable {
    let wordsToday: Int64
    let clipsToday: Int
    let dictationDurationToday: TimeInterval

    static let zero = WisprFlowSummary(wordsToday: 0, clipsToday: 0, dictationDurationToday: 0)

    var wordsTodayText: String {
        AppModel.formatCompactInt64(wordsToday)
    }

    var clipsTodayText: String {
        "\(clipsToday)"
    }

    var dictationDurationTodayText: String {
        AppModel.formatElapsed(dictationDurationToday)
    }
}

final class WisprFlowMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "worktimer.wispr-flow", qos: .utility)
    private var lastRefreshAt = Date.distantPast
    private let minimumRefreshInterval: TimeInterval = 30
    private let databaseURL: URL?
    private let now: () -> Date

    var onSummary: ((WisprFlowSummary) -> Void)?
    var onAvailabilityChange: ((Bool) -> Void)?

    init(databaseURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.databaseURL = databaseURL ?? Self.defaultDatabaseURL()
        self.now = now
    }

    func start() {
        refresh(force: true)
    }

    func tick() {
        refresh(force: false)
    }

    private func refresh(force: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            let current = self.now()
            if !force, current.timeIntervalSince(self.lastRefreshAt) < self.minimumRefreshInterval {
                return
            }
            self.lastRefreshAt = current

            guard let databaseURL = self.databaseURL else {
                DispatchQueue.main.async {
                    self.onAvailabilityChange?(false)
                }
                return
            }

            do {
                let summary = try Self.loadSummary(databaseURL: databaseURL, referenceDate: current)
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

    static func defaultDatabaseURL() -> URL? {
        let fileManager = FileManager.default
        if let override = ProcessInfo.processInfo.environment["WORKTIMER_WISPR_FLOW_DB"], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }

        let baseDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Wispr Flow", isDirectory: true)
        let primary = baseDirectory.appendingPathComponent("flow.sqlite", isDirectory: false)
        if fileManager.fileExists(atPath: primary.path) {
            return primary
        }

        let backupsDirectory = baseDirectory.appendingPathComponent("backups", isDirectory: true)
        if let candidates = try? fileManager.contentsOfDirectory(
            at: backupsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            return candidates
                .filter { $0.pathExtension == "sqlite" }
                .sorted {
                    let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return left > right
                }
                .first
        }

        return nil
    }

    static func loadSummary(databaseURL: URL, referenceDate: Date) throws -> WisprFlowSummary {
        var database: OpaquePointer?
        let uri = "file:\(databaseURL.path)?mode=ro&immutable=1"
        guard sqlite3_open_v2(uri, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            defer { sqlite3_close(database) }
            throw databaseError(database, fallback: "Unable to open Wispr Flow database")
        }
        defer { sqlite3_close(database) }

        let query = """
        SELECT
            COUNT(*) AS clipsToday,
            COALESCE(SUM(COALESCE(numWords, 0)), 0) AS wordsToday,
            COALESCE(SUM(COALESCE(duration, speechDuration, 0)), 0) AS durationToday
        FROM History
        WHERE isArchived = 0
          AND strftime('%Y-%m-%d', timestamp, 'localtime') = ?1
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError(database, fallback: "Unable to prepare Wispr Flow query")
        }
        defer { sqlite3_finalize(statement) }

        let formatter = DateFormatter()
        formatter.calendar = Calendar.autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let localDay = formatter.string(from: referenceDate)
        _ = localDay.withCString { value in
            sqlite3_bind_text(statement, 1, value, -1, sqliteTransientDestructor)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw databaseError(database, fallback: "Wispr Flow query returned no row")
        }

        return WisprFlowSummary(
            wordsToday: sqlite3_column_int64(statement, 1),
            clipsToday: Int(sqlite3_column_int64(statement, 0)),
            dictationDurationToday: sqlite3_column_double(statement, 2)
        )
    }

    private static func databaseError(_ database: OpaquePointer?, fallback: String) -> NSError {
        let message = database.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? fallback
        return NSError(domain: "WorkTimerWisprFlow", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
