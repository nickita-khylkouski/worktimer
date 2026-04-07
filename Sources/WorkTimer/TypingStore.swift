import Foundation
import SQLite3

enum TypingStoreError: Error {
    case openFailed(String)
    case executeFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
}

final class TypingStore: @unchecked Sendable {
    private let databaseURL: URL
    private var database: OpaquePointer?
    private let queue = DispatchQueue(label: "worktimer.sqlite")

    init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        try Self.ensureParentDirectory(for: databaseURL)
        try open()
        try configure()
        try createTables()
    }

    deinit {
        sqlite3_close(database)
    }

    func insert(_ snippet: CapturedSnippet) throws {
        try queue.sync {
            let sql = """
            INSERT INTO snippets (
                id,
                created_at,
                expires_at,
                app_name,
                bundle_id,
                session_key,
                text,
                char_count
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            bind(text: snippet.id.uuidString, to: 1, in: statement)
            sqlite3_bind_double(statement, 2, snippet.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(statement, 3, snippet.expiresAt.timeIntervalSince1970)
            bind(text: snippet.context.appName, to: 4, in: statement)
            bind(text: snippet.context.bundleIdentifier, to: 5, in: statement)
            bind(text: snippet.context.sessionKey, to: 6, in: statement)
            bind(text: snippet.text, to: 7, in: statement)
            sqlite3_bind_int64(statement, 8, sqlite3_int64(snippet.charCount))

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw TypingStoreError.stepFailed(lastErrorMessage())
            }
        }
    }

    func insert(_ session: TypingSessionRecord) throws {
        try queue.sync {
            let sql = """
            INSERT INTO typing_sessions (
                id,
                started_at,
                ended_at,
                app_name,
                bundle_id,
                session_key,
                character_count
            ) VALUES (?, ?, ?, ?, ?, ?, ?);
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            bind(text: session.id.uuidString, to: 1, in: statement)
            sqlite3_bind_double(statement, 2, session.startedAt.timeIntervalSince1970)
            sqlite3_bind_double(statement, 3, session.endedAt.timeIntervalSince1970)
            bind(text: session.context.appName, to: 4, in: statement)
            bind(text: session.context.bundleIdentifier, to: 5, in: statement)
            bind(text: session.context.sessionKey, to: 6, in: statement)
            sqlite3_bind_int64(statement, 7, sqlite3_int64(session.characterCount))

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw TypingStoreError.stepFailed(lastErrorMessage())
            }
        }
    }

    func recentSnippets(now: Date = .now, limit: Int = 200) throws -> [CapturedSnippet] {
        try queue.sync {
            let sql = """
            SELECT
                id,
                created_at,
                expires_at,
                app_name,
                bundle_id,
                session_key,
                text
            FROM snippets
            WHERE expires_at > ?
            ORDER BY created_at DESC
            LIMIT ?;
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_double(statement, 1, now.timeIntervalSince1970)
            sqlite3_bind_int(statement, 2, Int32(limit))

            var snippets: [CapturedSnippet] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard
                    let idCString = sqlite3_column_text(statement, 0),
                    let appNameCString = sqlite3_column_text(statement, 3),
                    let bundleCString = sqlite3_column_text(statement, 4),
                    let sessionCString = sqlite3_column_text(statement, 5),
                    let textCString = sqlite3_column_text(statement, 6),
                    let id = UUID(uuidString: String(cString: idCString))
                else {
                    continue
                }

                snippets.append(
                    CapturedSnippet(
                        id: id,
                        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                        expiresAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                        context: CaptureContext(
                            appName: String(cString: appNameCString),
                            bundleIdentifier: String(cString: bundleCString),
                            sessionKey: String(cString: sessionCString)
                        ),
                        text: String(cString: textCString)
                    )
                )
            }

            return snippets
        }
    }

    func typingSummary(from start: Date, to end: Date) throws -> TypingSummary {
        try queue.sync {
            let sql = """
            SELECT
                COALESCE(SUM(ended_at - started_at), 0),
                COALESCE(SUM(character_count), 0)
            FROM typing_sessions
            WHERE ended_at > ? AND started_at < ?;
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)
            sqlite3_bind_double(statement, 2, end.timeIntervalSince1970)

            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw TypingStoreError.stepFailed(lastErrorMessage())
            }

            return TypingSummary(
                duration: sqlite3_column_double(statement, 0),
                characterCount: Int(sqlite3_column_int64(statement, 1))
            )
        }
    }

    func setString(_ value: String, for key: String) throws {
        try queue.sync {
            let sql = """
            INSERT INTO app_settings (key, value_text)
            VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value_text = excluded.value_text;
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            bind(text: key, to: 1, in: statement)
            bind(text: value, to: 2, in: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw TypingStoreError.stepFailed(lastErrorMessage())
            }
        }
    }

    func stringSetting(for key: String) throws -> String? {
        try queue.sync {
            let statement = try prepare("SELECT value_text FROM app_settings WHERE key = ? LIMIT 1;")
            defer { sqlite3_finalize(statement) }
            bind(text: key, to: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            guard let value = sqlite3_column_text(statement, 0) else {
                return nil
            }
            return String(cString: value)
        }
    }

    func setDouble(_ value: Double, for key: String) throws {
        try setString(String(value), for: key)
    }

    func doubleSetting(for key: String) throws -> Double? {
        guard let value = try stringSetting(for: key) else {
            return nil
        }
        return Double(value)
    }

    func saveSession(_ session: PersistedSession) throws {
        let payload = try JSONEncoder().encode(session)
        try queue.sync {
            let sql = """
            INSERT INTO session_state (slot, payload_json)
            VALUES (1, ?)
            ON CONFLICT(slot) DO UPDATE SET payload_json = excluded.payload_json;
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_blob(statement, 1, (payload as NSData).bytes, Int32(payload.count), Self.transientDestructor)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw TypingStoreError.stepFailed(lastErrorMessage())
            }
        }
    }

    func loadSession() throws -> PersistedSession? {
        try queue.sync {
            let statement = try prepare("SELECT payload_json FROM session_state WHERE slot = 1 LIMIT 1;")
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            guard let bytes = sqlite3_column_blob(statement, 0) else {
                return nil
            }
            let count = Int(sqlite3_column_bytes(statement, 0))
            let data = Data(bytes: bytes, count: count)
            return try JSONDecoder().decode(PersistedSession.self, from: data)
        }
    }

    func saveDailySummaries(_ summaries: [DailyWorkSummary]) throws {
        let payload = try JSONEncoder().encode(summaries)
        try queue.sync {
            let sql = """
            INSERT INTO day_history (slot, payload_json)
            VALUES (1, ?)
            ON CONFLICT(slot) DO UPDATE SET payload_json = excluded.payload_json;
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_blob(statement, 1, (payload as NSData).bytes, Int32(payload.count), Self.transientDestructor)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw TypingStoreError.stepFailed(lastErrorMessage())
            }
        }
    }

    func loadDailySummaries() throws -> [DailyWorkSummary] {
        try queue.sync {
            let statement = try prepare("SELECT payload_json FROM day_history WHERE slot = 1 LIMIT 1;")
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return []
            }
            guard let bytes = sqlite3_column_blob(statement, 0) else {
                return []
            }
            let count = Int(sqlite3_column_bytes(statement, 0))
            let data = Data(bytes: bytes, count: count)
            return try JSONDecoder().decode([DailyWorkSummary].self, from: data)
        }
    }

    func delete(id: UUID) throws {
        try queue.sync {
            let statement = try prepare("DELETE FROM snippets WHERE id = ?;")
            defer { sqlite3_finalize(statement) }
            bind(text: id.uuidString, to: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw TypingStoreError.stepFailed(lastErrorMessage())
            }
        }
    }

    @discardableResult
    func purgeExpired(now: Date = .now) throws -> Int {
        try queue.sync {
            let statement = try prepare("DELETE FROM snippets WHERE expires_at <= ?;")
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_double(statement, 1, now.timeIntervalSince1970)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw TypingStoreError.stepFailed(lastErrorMessage())
            }
            return Int(sqlite3_changes(database))
        }
    }

    private func open() throws {
        var database: OpaquePointer?
        if sqlite3_open(databaseURL.path, &database) != SQLITE_OK {
            throw TypingStoreError.openFailed(lastErrorMessage(database))
        }
        self.database = database
    }

    private func configure() throws {
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA synchronous=NORMAL;")
        try exec("PRAGMA secure_delete=FAST;")
    }

    private func createTables() throws {
        try exec(
            """
            CREATE TABLE IF NOT EXISTS snippets (
                id TEXT PRIMARY KEY,
                created_at REAL NOT NULL,
                expires_at REAL NOT NULL,
                app_name TEXT NOT NULL,
                bundle_id TEXT NOT NULL,
                session_key TEXT NOT NULL,
                text TEXT NOT NULL,
                char_count INTEGER NOT NULL
            );
            """
        )
        try exec("CREATE INDEX IF NOT EXISTS snippets_expires_at_idx ON snippets (expires_at);")
        try exec("CREATE INDEX IF NOT EXISTS snippets_created_at_idx ON snippets (created_at DESC);")
        try exec(
            """
            CREATE TABLE IF NOT EXISTS typing_sessions (
                id TEXT PRIMARY KEY,
                started_at REAL NOT NULL,
                ended_at REAL NOT NULL,
                app_name TEXT NOT NULL,
                bundle_id TEXT NOT NULL,
                session_key TEXT NOT NULL,
                character_count INTEGER NOT NULL
            );
            """
        )
        try exec("CREATE INDEX IF NOT EXISTS typing_sessions_started_at_idx ON typing_sessions (started_at DESC);")
        try exec("CREATE INDEX IF NOT EXISTS typing_sessions_ended_at_idx ON typing_sessions (ended_at DESC);")
        try exec(
            """
            CREATE TABLE IF NOT EXISTS app_settings (
                key TEXT PRIMARY KEY,
                value_text TEXT NOT NULL
            );
            """
        )
        try exec(
            """
            CREATE TABLE IF NOT EXISTS session_state (
                slot INTEGER PRIMARY KEY CHECK (slot = 1),
                payload_json BLOB NOT NULL
            );
            """
        )
        try exec(
            """
            CREATE TABLE IF NOT EXISTS day_history (
                slot INTEGER PRIMARY KEY CHECK (slot = 1),
                payload_json BLOB NOT NULL
            );
            """
        )
    }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw TypingStoreError.executeFailed(lastErrorMessage())
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw TypingStoreError.prepareFailed(lastErrorMessage())
        }
        return statement
    }

    private func bind(text: String, to index: Int32, in statement: OpaquePointer?) {
        sqlite3_bind_text(statement, index, text, -1, Self.transientDestructor)
    }

    private static let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func lastErrorMessage(_ databaseOverride: OpaquePointer? = nil) -> String {
        let database = databaseOverride ?? database
        guard let database, let message = sqlite3_errmsg(database) else {
            return "unknown sqlite error"
        }
        return String(cString: message)
    }

    private static func ensureParentDirectory(for url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }
}
