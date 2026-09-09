// swift-tools-version: 5.9
import PackageDescription
import Foundation

// The runner links the actual app model into a temporary package. No app, Keychain, or wallet is opened.
let root = ProcessInfo.processInfo.environment["NEXAWAL_TEST_ROOT"]!
let core = ProcessInfo.processInfo.environment["NEXAWAL_TEST_WALLETCORE_PACKAGE"]!
let package = Package(
    name: "HistoryModelHarness", platforms: [.macOS(.v13)],
    dependencies: [
        .package(name: "MoneroWalletCoreFFI", path: core),
        .package(path: root + "/Packages/NexaWalLogic"),
    ],
    targets: [
        .target(name: "HistoryModelHarness", dependencies: [
            .product(name: "MoneroWalletCoreFFI", package: "MoneroWalletCoreFFI"), "NexaWalLogic"
        ]),
        .testTarget(name: "HistoryModelTests", dependencies: ["HistoryModelHarness", "NexaWalLogic"]),
    ]
)
