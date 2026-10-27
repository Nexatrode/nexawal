// swift-tools-version: 5.9
import PackageDescription
import Foundation
let root = ProcessInfo.processInfo.environment["NEXAWAL_TEST_ROOT"]!
let package = Package(
    name: "ConnectionSettingsHarness", platforms: [.macOS(.v13)],
    dependencies: [.package(path: root + "/Packages/NexaWalLogic")],
    targets: [
        .target(name: "ConnectionSettingsHarness", dependencies: ["NexaWalLogic"]),
        .testTarget(name: "ConnectionSettingsTests", dependencies: ["ConnectionSettingsHarness"]),
    ]
)
