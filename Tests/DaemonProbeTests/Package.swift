// swift-tools-version: 5.9
import PackageDescription
import Foundation

let root = ProcessInfo.processInfo.environment["NEXAWAL_TEST_ROOT"]!
let package = Package(
    name: "DaemonProbeHarness", platforms: [.macOS(.v13)],
    dependencies: [.package(path: root + "/Packages/NexaWalLogic")],
    targets: [
        .target(name: "DaemonProbeHarness", dependencies: ["NexaWalLogic"]),
        .testTarget(name: "DaemonProbeTests", dependencies: ["DaemonProbeHarness"]),
    ]
)
