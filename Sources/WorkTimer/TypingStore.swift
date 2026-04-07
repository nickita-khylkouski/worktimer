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
