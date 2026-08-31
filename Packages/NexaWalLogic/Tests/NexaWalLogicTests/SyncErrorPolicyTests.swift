import XCTest
@testable import NexaWalLogic

final class SyncErrorPolicyTests: XCTestCase {
    func testOnlyTransportFailuresAreCalledNodeUnreachable() {
        XCTAssertEqual(
            SyncErrorPolicy.classify(message: "refresh already running for wallet"),
            .failed
        )
        XCTAssertEqual(SyncErrorPolicy.classify(message: "cache JSON was malformed"), .failed)
        XCTAssertEqual(
            SyncErrorPolicy.classify(message: "connection refused by peer"),
            .nodeUnreachable
        )
    }

    func testTypedStallWinsOverMessageGuessing() {
        XCTAssertEqual(SyncErrorPolicy.classify(message: "anything", stalled: true), .stalled)
        XCTAssertEqual(SyncErrorPolicy.classify(message: "Sync stalled: no scan progress"), .stalled)
    }
}
