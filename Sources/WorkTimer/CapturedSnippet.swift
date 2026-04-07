import Foundation

struct CaptureContext: Codable, Equatable, Sendable {
    let appName: String
    let bundleIdentifier: String
    let sessionKey: String
}

struct CapturedSnippet: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let expiresAt: Date
    let context: CaptureContext
    let text: String

    var charCount: Int {
        text.count
    }
}

enum TypingMutation: Equatable, Sendable {
    case text(String)
    case backspace
    case newline
    case tab
}

struct TypingInput: Equatable, Sendable {
    let context: CaptureContext
    let mutation: TypingMutation
}

struct BufferedSnippet: Equatable, Sendable {
    let createdAt: Date
    let context: CaptureContext
    let text: String
}

struct TypingSessionRecord: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let context: CaptureContext
    let characterCount: Int

    var duration: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
    }
}

struct TypingSummary: Equatable, Sendable {
    let duration: TimeInterval
    let characterCount: Int

    static let zero = TypingSummary(duration: 0, characterCount: 0)
}
