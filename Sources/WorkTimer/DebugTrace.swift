import Foundation

enum DebugTrace {
    static let enabled = true
    private static let queue = DispatchQueue(label: "worktimer.debug-trace")
    private static let fileURL = URL(fileURLWithPath: "/tmp/worktimer-debug.log")

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else {
            return
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let line = "[WorkTimer \(formatter.string(from: .now))] \(message())\n"
        queue.async {
            guard let data = line.data(using: .utf8) else {
                return
            }
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }
}
