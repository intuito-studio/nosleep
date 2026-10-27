// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NoSleep",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NoSleep", targets: ["NoSleep"]),
    ],
    targets: [
        // Everything that touches the system: the sleep switch, the battery,
        // and the rules that decide when a session ends. No UI.
        .target(
            name: "NoSleepCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The menu bar app.
        .executableTarget(
            name: "NoSleep",
            dependencies: ["NoSleepCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "NoSleepCoreTests",
            dependencies: ["NoSleepCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
