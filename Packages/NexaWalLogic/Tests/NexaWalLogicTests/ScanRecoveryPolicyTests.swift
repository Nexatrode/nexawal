import XCTest
@testable import NexaWalLogic

final class ScanRecoveryPolicyTests: XCTestCase {
    func testInterruptedNearTipRewindsToTrustedCheckpointWithoutSkippingOldHistory() {
        let original: UInt64 = 3_519_450
        let trusted: UInt64 = 3_775_752
        let result = ScanRecoveryPolicy.rewindHeight(
            caughtUpToTip: true,
            scanInterrupted: true,
            cursorAheadOfTrusted: false,
            emptyHistoryAtTip: false,
            originalRestoreHeight: original,
            trustedScannedHeight: trusted,
            lastScannedHeight: 3_776_865
        )
        XCTAssertEqual(result, trusted)
        XCTAssertGreaterThan(result!, original)
    }

    func testEmptyInterruptedHistoryRewindsAllTheWayToOriginalRestoreHeight() {
        XCTAssertEqual(ScanRecoveryPolicy.rewindHeight(
            caughtUpToTip: true, scanInterrupted: true, cursorAheadOfTrusted: false,
            emptyHistoryAtTip: true, originalRestoreHeight: 3_519_450,
            trustedScannedHeight: 3_775_752, lastScannedHeight: 3_776_865
        ), 3_519_450)
    }

    func testTrustedHeightCannotAdvanceCursorOrPrecedeRestoreHeight() {
        XCTAssertEqual(ScanRecoveryPolicy.rewindHeight(
            caughtUpToTip: true, scanInterrupted: true, cursorAheadOfTrusted: false,
            emptyHistoryAtTip: false, originalRestoreHeight: 100,
            trustedScannedHeight: 300, lastScannedHeight: 200
        ), 200)
        XCTAssertEqual(ScanRecoveryPolicy.rewindHeight(
            caughtUpToTip: true, scanInterrupted: true, cursorAheadOfTrusted: false,
            emptyHistoryAtTip: false, originalRestoreHeight: 100,
            trustedScannedHeight: 0, lastScannedHeight: 200
        ), 100)
    }

    func testInProgressOrCleanScanDoesNotRewind() {
        XCTAssertNil(ScanRecoveryPolicy.rewindHeight(
            caughtUpToTip: false,
            scanInterrupted: true,
            cursorAheadOfTrusted: true,
            emptyHistoryAtTip: false,
            originalRestoreHeight: 3_519_450,
            trustedScannedHeight: 3_775_752,
            lastScannedHeight: 3_776_865
        ))
        XCTAssertNil(ScanRecoveryPolicy.rewindHeight(
            caughtUpToTip: true,
            scanInterrupted: false,
            cursorAheadOfTrusted: false,
            emptyHistoryAtTip: false,
            originalRestoreHeight: 3_519_450,
            trustedScannedHeight: 3_775_752,
            lastScannedHeight: 3_776_865
        ))
    }
}
