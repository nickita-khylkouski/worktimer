// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WorkTimer",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "WorkTimer", targets: ["WorkTimer"]),
    ],
    targets: [
        .executableTarget(
            name: "WorkTimer",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("Carbon"),
            ]
        ),
        .testTarget(
            name: "WorkTimerTests",
            dependencies: ["WorkTimer"]
        ),
    ]
)
