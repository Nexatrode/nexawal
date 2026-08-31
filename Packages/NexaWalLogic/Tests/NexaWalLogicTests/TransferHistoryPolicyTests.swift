import XCTest
@testable import NexaWalLogic

final class TransferHistoryPolicyTests: XCTestCase {
    func testNonemptyFetchAlwaysReplaces() {
        XCTAssertTrue(
            TransferHistoryPolicy.shouldReplaceTransfers(
                existingCount: 3,
                newCount: 1,
                refreshing: true,
                caughtUpToTip: false,
                scanInterrupted: true,
                lastScannedHeight: 10,
                trustedScannedHeight: 0
            )
        )
    }

    func testEmptyToEmptyReplaces() {
        XCTAssertTrue(
            TransferHistoryPolicy.shouldReplaceTransfers(
                existingCount: 0,
                newCount: 0,
                refreshing: true,
                caughtUpToTip: false,
                scanInterrupted: true,
                lastScannedHeight: 10,
                trustedScannedHeight: 0
            )
        )
    }

    func testPreservesNonemptyDuringMidSyncEmptyFetch() {
        XCTAssertFalse(
            TransferHistoryPolicy.shouldReplaceTransfers(
                existingCount: 2,
                newCount: 0,
                refreshing: true,
                caughtUpToTip: false,
                scanInterrupted: false,
                lastScannedHeight: 100,
                trustedScannedHeight: 100
            )
        )
    }

    func testPreservesNonemptyWhenIncompleteAndNotRefreshing() {
        XCTAssertFalse(
            TransferHistoryPolicy.shouldReplaceTransfers(
                existingCount: 2,
                newCount: 0,
                refreshing: false,
                caughtUpToTip: false,
                scanInterrupted: false,
                lastScannedHeight: 90,
                trustedScannedHeight: 90
            )
        )
    }

    func testPreservesNonemptyWhenCaughtUpButStillRefreshing() {
        XCTAssertFalse(
            TransferHistoryPolicy.shouldReplaceTransfers(
                existingCount: 2,
                newCount: 0,
                refreshing: true,
                caughtUpToTip: true,
                scanInterrupted: false,
                lastScannedHeight: 100,
                trustedScannedHeight: 100
            )
        )
    }

    func testPreservesNonemptyWhenIdleAtTipButScanInterrupted() {
        // Interrupted cache can be idle and appear at tip without a clean checkpoint.
        XCTAssertFalse(
            TransferHistoryPolicy.shouldReplaceTransfers(
                existingCount: 2,
                newCount: 0,
                refreshing: false,
                caughtUpToTip: true,
                scanInterrupted: true,
                lastScannedHeight: 100,
                trustedScannedHeight: 100
            )
        )
    }

    func testPreservesNonemptyWhenTrustedHeightLagsPastTolerance() {
        XCTAssertFalse(
            TransferHistoryPolicy.shouldReplaceTransfers(
                existingCount: 2,
                newCount: 0,
                refreshing: false,
                caughtUpToTip: true,
                scanInterrupted: false,
                lastScannedHeight: 100,
                trustedScannedHeight: 90,
                tipTolerance: 3
            )
        )
    }

    func testAllowsAuthoritativeEmptyAfterCleanCheckpoint() {
        XCTAssertTrue(
            TransferHistoryPolicy.shouldReplaceTransfers(
                existingCount: 2,
                newCount: 0,
                refreshing: false,
                caughtUpToTip: true,
                scanInterrupted: false,
                lastScannedHeight: 100,
                trustedScannedHeight: 98,
                tipTolerance: 3
            )
        )
    }
}
