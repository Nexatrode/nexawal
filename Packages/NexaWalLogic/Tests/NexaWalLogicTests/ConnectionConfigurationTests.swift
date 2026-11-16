import XCTest
@testable import NexaWalLogic

final class ConnectionConfigurationTests: XCTestCase {
    func testNormalizationDoesNotCorruptPreviouslySavedExplicitURLs() {
        for raw in ["https://rpc.example/path?token=x", "http://rpc.example#fragment", "https://"] {
            XCTAssertEqual(NetworkRouting.normalizeURL(raw), raw)
        }
    }
    func testMalformedClearnetURLsAreRejected() {
        for raw in ["http://", "https:///", "https://:18081", "http://host:0", "http://host:99999", "https://host?q=secret", "https://host#fragment", "node:18081"] {
            XCTAssertNil(NetworkRouting.explicitNodeURL(raw), "Accepted \(raw)")
        }
        XCTAssertEqual(NetworkRouting.explicitNodeURL(" https://rpc.example/path "), "https://rpc.example/path")
        XCTAssertEqual(NetworkRouting.explicitNodeURL("http://[::1]:18081"), "http://[::1]:18081")
    }
}
