import Foundation
import Testing
@testable import WorkTimer

struct TypingBufferCoordinatorTests {
    @Test
    func flushesAfterIdleThreshold() {
        let coordinator = TypingBufferCoordinator(idleThreshold: 5)
        let context = CaptureContext(appName: "Terminal", bundleIdentifier: "com.apple.Terminal", sessionKey: "terminal")
        let start = Date(timeIntervalSince1970: 100)

        _ = coordinator.record(TypingInput(context: context, mutation: .text("hello")), at: start)
        let snippet = coordinator.flushIfIdle(at: start.addingTimeInterval(6))

        #expect(snippet?.text == "hello")
        #expect(snippet?.context == context)
    }

    @Test
    func flushesWhenContextChanges() {
        let coordinator = TypingBufferCoordinator(idleThreshold: 5)
        let terminal = CaptureContext(appName: "Terminal", bundleIdentifier: "com.apple.Terminal", sessionKey: "terminal")
        let cursor = CaptureContext(appName: "Cursor", bundleIdentifier: "com.todesktop.230313mzl4w4u92", sessionKey: "cursor")
        let start = Date(timeIntervalSince1970: 100)

        _ = coordinator.record(TypingInput(context: terminal, mutation: .text("hello")), at: start)
        let flushed = coordinator.record(TypingInput(context: cursor, mutation: .text("world")), at: start.addingTimeInterval(1))

        #expect(flushed?.text == "hello")
        #expect(flushed?.context == terminal)
    }

    @Test
    func appliesBackspace() {
        let coordinator = TypingBufferCoordinator(idleThreshold: 5)
        let context = CaptureContext(appName: "Terminal", bundleIdentifier: "com.apple.Terminal", sessionKey: "terminal")
        let start = Date(timeIntervalSince1970: 100)

        _ = coordinator.record(TypingInput(context: context, mutation: .text("hello")), at: start)
        _ = coordinator.record(TypingInput(context: context, mutation: .backspace), at: start.addingTimeInterval(0.5))
        let flushed = coordinator.forceFlush(at: start.addingTimeInterval(1))

        #expect(flushed?.text == "hell")
    }
}
