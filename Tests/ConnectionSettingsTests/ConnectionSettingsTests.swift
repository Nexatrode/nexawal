import Foundation
import XCTest
@testable import ConnectionSettingsHarness

@MainActor
final class ConnectionSettingsTests: XCTestCase {
    private let keys = [MoneroConfig.userDefaultsKey, MoneroConfig.userDefaultsNetworkPolicyKey,
                        MoneroConfig.userDefaultsI2PRPCKey, MoneroConfig.userDefaultsI2PProxyKey,
                        MoneroConfig.userDefaultsI2PModeKey]
    private let i2p = "http://fixture.b32.i2p:18081"
    private let proxy = "127.0.0.1:4444"
    private func snapshot() -> NSDictionary {
        NSDictionary(dictionary: Dictionary(uniqueKeysWithValues: keys.compactMap { key in
            UserDefaults.standard.object(forKey: key).map { (key, $0) }
        }))
    }

    func testRejectedTransitionsLeaveEveryPreferenceUntouched() async throws {
        let original = snapshot()
        defer { restore(original) }
        for starting in [MoneroConfig.NetworkPolicy.clearnet, .i2p, .hybrid] {
            _ = try MoneroConfig.applyNetworkSettings(policy: starting, nodeAddress: "http://127.0.0.1:18081",
                i2pRPCAddress: i2p, proxyAddress: proxy)
            let before = snapshot()
            for target in [MoneroConfig.NetworkPolicy.clearnet, .i2p, .hybrid] {
                XCTAssertThrowsError(try MoneroConfig.applyNetworkSettings(policy: target,
                    nodeAddress: "scheme-less.example:18081", i2pRPCAddress: "invalid-node", proxyAddress: "socks5://127.0.0.1:4447"))
                XCTAssertEqual(snapshot(), before)
            }
            // Specifically reproduce the original partial-write failure: valid I2P fields,
            // but the clearnet URL is rejected after switching to hybrid.
            XCTAssertThrowsError(try MoneroConfig.applyNetworkSettings(policy: .hybrid,
                nodeAddress: "scheme-less.example:18081", i2pRPCAddress: i2p, proxyAddress: proxy))
            XCTAssertEqual(snapshot(), before)
            XCTAssertThrowsError(try MoneroConfig.applyNetworkSettings(policy: .hybrid,
                nodeAddress: "https://rpc.example", i2pRPCAddress: i2p, proxyAddress: ""))
            XCTAssertEqual(snapshot(), before)
        }
    }

    func testValidTransitionsPublishConsistentScanAndBroadcastRoutes() async throws {
        let original = snapshot()
        defer { restore(original) }
        for policy in [MoneroConfig.NetworkPolicy.clearnet, .i2p, .hybrid, .clearnet] {
            let node = try MoneroConfig.applyNetworkSettings(policy: policy,
                nodeAddress: " http://127.0.0.1:18081 ", i2pRPCAddress: " \(i2p) ", proxyAddress: " \(proxy) ")
            XCTAssertEqual(MoneroConfig.networkPolicy.rawValue, policy.rawValue)
            XCTAssertEqual(MoneroConfig.useI2P, policy != .clearnet)
            XCTAssertEqual(MoneroConfig.i2pHTTPProxyAddress, proxy)
            XCTAssertEqual(node, "http://127.0.0.1:18081")
            XCTAssertEqual(MoneroConfig.scanNodeAddress(), policy == .i2p ? i2p : node)
            XCTAssertEqual(MoneroConfig.broadcastNodeAddress(), policy == .clearnet ? node : i2p)
        }
    }

    func testBlankClearnetUsesDefaultAndInactiveFieldsDoNotBlockSaving() async throws {
        let original = snapshot()
        defer { restore(original) }
        _ = try MoneroConfig.applyNetworkSettings(policy: .clearnet, nodeAddress: " ", i2pRPCAddress: "", proxyAddress: "")
        XCTAssertEqual(MoneroConfig.daemonAddress, MoneroConfig.defaultAddress)
        XCTAssertNil(MoneroConfig.i2pHTTPProxyAddress)
        _ = try MoneroConfig.applyNetworkSettings(policy: .i2p, nodeAddress: "invalid-inactive-field", i2pRPCAddress: i2p, proxyAddress: proxy)
        XCTAssertEqual(MoneroConfig.daemonAddress, MoneroConfig.defaultAddress)
    }

    private func restore(_ values: NSDictionary) {
        for key in keys { UserDefaults.standard.set(values[key], forKey: key) }
    }
}
