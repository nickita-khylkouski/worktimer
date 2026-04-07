import Foundation
import Testing
@testable import WorkTimer

struct DiskHealthMonitorTests {
    @Test
    func parsesDiskutilSmartCounters() {
        let info: [String: Any] = [
            "MediaName": "APPLE SSD AP0256Z",
            "SMARTStatus": "Verified",
            "SMARTDeviceSpecificKeysMayVaryNotGuaranteed": [
                "DATA_UNITS_READ_0": 236_191_616,
                "DATA_UNITS_READ_1": 0,
                "DATA_UNITS_WRITTEN_0": 112_582_079,
                "DATA_UNITS_WRITTEN_1": 0,
                "HOST_READ_COMMANDS_0": 3_307_592_693,
                "HOST_READ_COMMANDS_1": 1,
                "HOST_WRITE_COMMANDS_0": 3_207_927_793,
                "HOST_WRITE_COMMANDS_1": 0,
                "PERCENTAGE_USED": 5,
                "AVAILABLE_SPARE": 100,
                "POWER_ON_HOURS_0": 1_606,
                "POWER_ON_HOURS_1": 0,
                "POWER_CYCLES_0": 279,
                "POWER_CYCLES_1": 0,
                "UNSAFE_SHUTDOWNS_0": 66,
                "UNSAFE_SHUTDOWNS_1": 0,
            ],
        ]

        let summary = DiskHealthSummary.make(fromDiskInfo: info, selectionIdentifier: "disk0")

        #expect(summary?.diskIdentifier == "disk0")
        #expect(summary?.model == "APPLE SSD AP0256Z")
        #expect(summary?.readText == "121 TB")
        #expect(summary?.writtenText == "57.6 TB")
        #expect(summary?.hostWriteCommandsText == "3.21B")
        #expect(summary?.wearText == "5%")
        #expect(summary?.powerOnText == "1606h")
    }
}
