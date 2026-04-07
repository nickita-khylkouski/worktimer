import Foundation

final class TypingBufferCoordinator {
    private let idleThreshold: TimeInterval
    private var activeContext: CaptureContext?
    private var createdAt: Date?
    private var lastInputAt: Date?
    private var buffer = ""

    init(idleThreshold: TimeInterval) {
        self.idleThreshold = idleThreshold
    }

    func updateIdleThreshold(_ value: TimeInterval) {
        _ = value
    }

    func record(_ input: TypingInput, at date: Date) -> BufferedSnippet? {
        var committed: BufferedSnippet?
        if let activeContext, activeContext != input.context {
            committed = flush(at: date)
        }

        if createdAt == nil {
            createdAt = date
        }
        activeContext = input.context
        lastInputAt = date
        apply(input.mutation)
        return committed
    }

    func flushIfIdle(at date: Date) -> BufferedSnippet? {
        guard let lastInputAt else {
            return nil
        }
        guard date.timeIntervalSince(lastInputAt) >= idleThreshold else {
            return nil
        }
        return flush(at: date)
    }

    func forceFlush(at date: Date) -> BufferedSnippet? {
        flush(at: date)
    }

    private func apply(_ mutation: TypingMutation) {
        switch mutation {
        case let .text(text):
            buffer.append(text)
        case .backspace:
            guard !buffer.isEmpty else {
                return
            }
            buffer.removeLast()
        case .newline:
            buffer.append("\n")
        case .tab:
            buffer.append("\t")
        }
    }

    private func flush(at date: Date) -> BufferedSnippet? {
        guard
            let activeContext,
            let createdAt,
            !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            reset()
            return nil
        }

        let snippet = BufferedSnippet(
            createdAt: createdAt,
            context: activeContext,
            text: buffer
        )
        reset(keepingDate: date)
        return snippet
    }

    private func reset(keepingDate date: Date? = nil) {
        activeContext = nil
        createdAt = nil
        lastInputAt = date
        buffer = ""
    }
}
