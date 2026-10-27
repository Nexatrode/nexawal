import XCTest
@testable import NexaWalLogic

final class NetworkRoutingPrivacyTests: XCTestCase {
    func testValidHTTPProxyAndI2PRPC() throws {
        try NetworkRouting.validateI2PConfiguration(nodeAddress: NetworkRouting.defaultI2PRPCAddress, proxyAddress: "127.0.0.1:4444")
        try NetworkRouting.validateI2PConfiguration(nodeAddress: "http://custom.i2p:18081", proxyAddress: "http://[::1]:4444")
    }

    func testRejectsMissingProxyAndWrongProxyProtocol() {
        for proxy: String? in [nil, "", "localhost", "127.0.0.1:0", "127.0.0.1:65536", "socks5://127.0.0.1:4447", "https://127.0.0.1:4444", "http://127.0.0.1:4444/path"] {
            XCTAssertThrowsError(try NetworkRouting.validateI2PConfiguration(nodeAddress: "http://test.i2p", proxyAddress: proxy))
        }
    }

    func testRejectsClearnetNodeAndP2PPortInI2PModes() {
        for node in ["", "https://rpc.nexawal.com", "http://127.0.0.1:18092", "http://test.i2p.evil.example", "test.i2p:0", "http://test.i2p/#fragment"] {
            XCTAssertThrowsError(try NetworkRouting.validateI2PConfiguration(nodeAddress: node, proxyAddress: "127.0.0.1:4444"))
        }
    }

    func testHybridAndI2PBroadcastNeverSelectClearnetNode() {
        for policy: NetworkRouting.Policy in [.i2p, .hybrid] {
            let node = NetworkRouting.broadcastNodeURL(policy: policy, clearnetNodeURL: "https://rpc.nexawal.com", i2pRPCAddress: NetworkRouting.defaultI2PRPCAddress)
            XCTAssertTrue(node.hasSuffix(".b32.i2p"))
        }
    }
}
