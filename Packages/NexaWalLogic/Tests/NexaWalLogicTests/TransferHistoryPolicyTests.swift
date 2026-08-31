import XCTest
@testable import NexaWalLogic

final class TransferHistoryPolicyTests: XCTestCase {
    func testNonemptyFetchAlwaysReplaces() {
        XCTAssertTrue(
            TransferHistoryPolicy.shouldReplaceTransfers(
                existingCount: 3,
                newCount: 1,
                refreshing: true,
                caughtUpToTip: false
            )
        )
    }

    func testEmptyToEmptyReplaces() {
        XCTAssertTrue(
            TransferHistoryPolicy.shouldReplaceTransfers(
                existingCount: 0,
                newCount: 0,
                refreshing: true,
                caughtUpToTip: false
            )
        )
    }

    func testPreservesNonemptyDuringMidSyncEmptyFetch() {
        XCTAssertFalse(
            TransferHistoryPolicy.shouldReplaceTransfers(
                existingCount: 2,
                newCount: 0,
                refreshing: true,
                caughtUpToTip: false
            )
        )
    }

    func testPreservesNonemptyWhenIncompleteAndNotRefreshing() {
        XCTAssertFalse(
            TransferHistoryPolicy.shouldReplaceTransfers(
                existingCount: 2,
                newCount: 0,
                refreshing: false,
                caughtUpToTip: false
            )
        )
    }

    func testAllowsAuthoritativeEmptyWhenCaughtUpWhileRefreshing() {
        // End-of-refresh still has isRefreshing=true until defer runs.
        XCTAssertTrue(
            TransferHistoryPolicy.shouldReplaceTransfers(
                existingCount: 2,
                newCount: 0,
                refreshing: true,
                caughtUpToTip: true
            )
        )
    }

    func testAllowsAuthoritativeEmptyWhenCaughtUpAndIdle() {
        XCTAssertTrue(
            TransferHistoryPolicy.shouldReplaceTransfers(
                existingCount: 2,
                newCount: 0,
                refreshing: false,
                caughtUpToTip: true
            )
        )
    }
}
