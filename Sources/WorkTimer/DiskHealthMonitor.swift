import Foundation

struct DiskHealthSummary: Equatable, Sendable {
    let diskIdentifier: String
    let model: String
    let readBytes: Int64
    let writtenBytes: Int64
    let hostReadCommands: Int64
    let hostWriteCommands: Int64
    let percentageUsed: Int
    let availableSparePercent: Int
    let powerOnHours: Int64
    let powerCycles: Int64
    let unsafeShutdowns: Int64
    let smartStatus: String

    static let zero = DiskHealthSummary(
        diskIdentifier: "--",
        model: "--",
        readBytes: 0,
        writtenBytes: 0,
        hostReadCommands: 0,
        hostWriteCommands: 0,
        percentageUsed: 0,
        availableSparePercent: 0,
        powerOnHours: 0,
        powerCycles: 0,
        unsafeShutdowns: 0,
        smartStatus: "Unknown"
    )

    var readText: String { Self.formatDecimalBytes(readBytes) }
    var writtenText: String { Self.formatDecimalBytes(writtenBytes) }
    var hostReadCommandsText: String { Self.formatCommandCount(hostReadCommands) }
    var hostWriteCommandsText: String { Self.formatCommandCount(hostWriteCommands) }
    var wearText: String { "\(percentageUsed)%" }
    var spareText: String { "\(availableSparePercent)%" }
    var powerOnText: String { "\(powerOnHours)h" }

    static func formatDecimalBytes(_ byteCount: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = Double(byteCount)
        var unit = units[0]
        for candidate in units {
            unit = candidate
            if abs(value) < 1000 || candidate == units.last {
                break
            }
            value /= 1000
        }

        if unit == "B" {
            return "\(Int(value)) \(unit)"
        }
        if value >= 100 {
            return String(format: "%.0f %@", value, unit)
        }
        if value >= 10 {
            return String(format: "%.1f %@", value, unit)
        }
        return String(format: "%.2f %@", value, unit)
    }

    static func formatCommandCount(_ value: Int64) -> String {
        AppModel.formatCompactInt64(value)
    }

    static func make(fromDiskInfo info: [String: Any], selectionIdentifier: String) -> DiskHealthSummary? {
        let smart = info["SMARTDeviceSpecificKeysMayVaryNotGuaranteed"] as? [String: Any] ?? [:]
        guard !smart.isEmpty else {
            return nil
        }

        let readUnits = int64FromLoHi(smart, base: "DATA_UNITS_READ")
        let writtenUnits = int64FromLoHi(smart, base: "DATA_UNITS_WRITTEN")

        return DiskHealthSummary(
            diskIdentifier: selectionIdentifier,
            model: String(info["MediaName"] as? String ?? info["IORegistryEntryName"] as? String ?? selectionIdentifier),
            readBytes: readUnits * 512_000,
            writtenBytes: writtenUnits * 512_000,
            hostReadCommands: int64FromLoHi(smart, base: "HOST_READ_COMMANDS"),
            hostWriteCommands: int64FromLoHi(smart, base: "HOST_WRITE_COMMANDS"),
            percentageUsed: Int(smart["PERCENTAGE_USED"] as? Int ?? 0),
            availableSparePercent: Int(smart["AVAILABLE_SPARE"] as? Int ?? 0),
            powerOnHours: int64FromLoHi(smart, base: "POWER_ON_HOURS"),
            powerCycles: int64FromLoHi(smart, base: "POWER_CYCLES"),
            unsafeShutdowns: int64FromLoHi(smart, base: "UNSAFE_SHUTDOWNS"),
            smartStatus: String(info["SMARTStatus"] as? String ?? "Unknown")
        )
    }

    private static func int64FromLoHi(_ payload: [String: Any], base: String) -> Int64 {
        let low = int64(payload["\(base)_0"])
        let high = int64(payload["\(base)_1"])
        return low + (high << 32)
    }

    private static func int64(_ value: Any?) -> Int64 {
        switch value {
        case let int as Int:
            return Int64(int)
        case let int64 as Int64:
            return int64
        case let double as Double:
            return Int64(double)
        case let string as String:
            return Int64(string) ?? 0
        case let number as NSNumber:
            return number.int64Value
        default:
            return 0
        }
    }
}

final class DiskHealthMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "worktimer.disk-health", qos: .utility)
    private var lastRefreshAt = Date.distantPast
    private let minimumRefreshInterval: TimeInterval = 60

    var onSummary: ((DiskHealthSummary) -> Void)?
    var onAvailabilityChange: ((Bool) -> Void)?

    func start() {
        refresh(force: true)
    }

    func tick() {
        refresh(force: false)
    }

    private func refresh(force: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            let now = Date()
            if !force, now.timeIntervalSince(self.lastRefreshAt) < self.minimumRefreshInterval {
                return
            }
            self.lastRefreshAt = now

            do {
                let summary = try Self.loadSummary()
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

    private static func loadSummary() throws -> DiskHealthSummary {
        let listingData = try run(["/usr/sbin/diskutil", "list", "-plist", "physical"])
        let listing = try PropertyListSerialization.propertyList(from: listingData, format: nil) as? [String: Any]
        let wholeDisks = listing?["WholeDisks"] as? [String] ?? []

        for identifier in wholeDisks {
            let infoData = try run(["/usr/sbin/diskutil", "info", "-plist", identifier])
            guard let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any] else {
                continue
            }
            guard (info["WholeDisk"] as? Bool) == true, (info["Internal"] as? Bool) == true else {
                continue
            }
            if let summary = DiskHealthSummary.make(fromDiskInfo: info, selectionIdentifier: identifier) {
                return summary
            }
        }

        throw NSError(domain: "WorkTimerDiskHealth", code: 1, userInfo: [NSLocalizedDescriptionKey: "No internal disk counters found"])
    }

    private static func run(_ command: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst())
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let errorText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "command failed"
            throw NSError(domain: "WorkTimerDiskHealth", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorText])
        }
        return stdout.fileHandleForReading.readDataToEndOfFile()
    }
}
