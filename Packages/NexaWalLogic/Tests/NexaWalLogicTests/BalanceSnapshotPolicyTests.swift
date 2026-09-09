import XCTest
@testable import NexaWalLogic

final class BalanceSnapshotPolicyTests: XCTestCase {
    private let partial: UInt64 = 835_000_000 // 0.000835 XMR; test-only amount.

    func testPartialNonzeroIsVisibleButProvisional() {
        let decision = BalanceSnapshotPolicy.decide(knownTotal: 0, knownUnlocked: 0,
            proposedTotal: partial, proposedUnlocked: partial, authoritative: false)
        XCTAssertTrue(decision.apply)
        XCTAssertTrue(decision.provisional)
    }

    func testInterruptedZeroPreservesKnownBalanceWithoutClaimingItIsCurrent() {
        let decision = BalanceSnapshotPolicy.decide(knownTotal: partial, knownUnlocked: partial,
            proposedTotal: 0, proposedUnlocked: 0, authoritative: false)
        XCTAssertFalse(decision.apply)
        XCTAssertTrue(decision.provisional)
    }

    func testFinalZeroReplacesPartialBalanceWithUnchangedHistory() {
        // UI is still publishing (spinner up / interruption marker not cleared yet).
        // Neither UI flag participates in the completed-native-snapshot decision.
        let historyBefore = ["receive", "spend"]
        let historyAfter = historyBefore
        let authoritative = BalanceSnapshotPolicy.completedRefreshIsAuthoritative(
            nativeIdle: true, chainHeight: 3_756_000, lastScannedHeight: 3_756_000,
            restoreHeight: 3_519_450, transferCount: historyAfter.count)
        let decision = BalanceSnapshotPolicy.decide(knownTotal: partial, knownUnlocked: partial,
            proposedTotal: 0, proposedUnlocked: 0, authoritative: authoritative)
        XCTAssertTrue(decision.apply)
        XCTAssertFalse(decision.provisional)
        XCTAssertEqual(historyBefore, historyAfter)
    }

    func testNativeRunningOrShortScanCannotAuthorizeZero() {
        XCTAssertFalse(BalanceSnapshotPolicy.completedRefreshIsAuthoritative(
            nativeIdle: false, chainHeight: 100, lastScannedHeight: 100,
            restoreHeight: 0, transferCount: 2))
        XCTAssertFalse(BalanceSnapshotPolicy.completedRefreshIsAuthoritative(
            nativeIdle: true, chainHeight: 100, lastScannedHeight: 99,
            restoreHeight: 0, transferCount: 2))
    }

    func testUnknownTipCannotAuthorizeZeroButCompletedEmptyHistoryCan() {
        XCTAssertFalse(BalanceSnapshotPolicy.completedRefreshIsAuthoritative(
            nativeIdle: true, chainHeight: 0, lastScannedHeight: 0,
            restoreHeight: 0, transferCount: 2))
        XCTAssertTrue(BalanceSnapshotPolicy.completedRefreshIsAuthoritative(
            nativeIdle: true, chainHeight: 100_000, lastScannedHeight: 100_000,
            restoreHeight: 0, transferCount: 0))
    }

    func testReorgFinalSnapshotPublishesEmptyHistoryAndZeroBeforeSpinnerStops() {
        // Exercise the final publisher's actual policy sequence with old nonempty UI data.
        // Both short restores and long restores can legitimately lose their last receive.
        for restore: UInt64 in [0, 99_000] {
            var displayedHistory = ["orphaned-receive"]
            var displayedBalance = partial
            let authoritative = BalanceSnapshotPolicy.completedRefreshIsAuthoritative(
                nativeIdle: true, chainHeight: 100_000, lastScannedHeight: 100_000,
                restoreHeight: restore, transferCount: 0)
            if TransferHistoryPolicy.shouldReplaceTransfers(
                existingCount: displayedHistory.count, newCount: 0, refreshing: true,
                caughtUpToTip: true, scanInterrupted: true, lastScannedHeight: 100_000,
                trustedScannedHeight: 99_990, completedRefreshAuthoritative: authoritative) {
                displayedHistory = []
            }
            if BalanceSnapshotPolicy.decide(knownTotal: displayedBalance,
                knownUnlocked: displayedBalance, proposedTotal: 0, proposedUnlocked: 0,
                authoritative: authoritative).apply {
                displayedBalance = 0
            }
            XCTAssertTrue(displayedHistory.isEmpty)
            XCTAssertEqual(displayedBalance, 0)
        }
    }

    func testNewEmptyWalletAndMaximumHeightsDoNotOverflow() {
        XCTAssertTrue(BalanceSnapshotPolicy.completedRefreshIsAuthoritative(
            nativeIdle: true, chainHeight: .max, lastScannedHeight: .max,
            restoreHeight: .max - 10, transferCount: 0))
    }

    func testWiFiFailureBackgroundRelaunchAndLTECompletion() {
        var epoch = WalletSnapshotEpoch()
        var displayed: UInt64 = 0
        func publish(_ amount: UInt64, authoritative: Bool) {
            if BalanceSnapshotPolicy.decide(knownTotal: displayed, knownUnlocked: displayed,
                proposedTotal: amount, proposedUnlocked: amount, authoritative: authoritative).apply {
                displayed = amount
            }
        }
        publish(partial, authoritative: false)
        let wifiPoll = epoch.token
        epoch.invalidate() // cancelled Wi-Fi refresh / background transition
        XCTAssertFalse(epoch.accepts(wifiPoll))
        publish(0, authoritative: false) // incomplete restored cache
        XCTAssertEqual(displayed, partial)
        let previousProcess = epoch.token
        epoch = WalletSnapshotEpoch() // force quit + launch: metadata remains only provisional
        XCTAssertFalse(epoch.accepts(previousProcess))
        let ltePoll = epoch.token
        epoch.invalidate() // final snapshot supersedes all intermediate polls
        publish(0, authoritative: true)
        if epoch.accepts(ltePoll) { publish(partial, authoritative: false) }
        XCTAssertEqual(displayed, 0, "late polls must not resurrect the intermediate balance")
    }

    func testSteadyStateSnapshotAppliesDecreasesAndZero() {
        for amount: UInt64 in [partial / 2, 0] {
            let decision = BalanceSnapshotPolicy.decide(knownTotal: partial, knownUnlocked: partial,
                proposedTotal: amount, proposedUnlocked: amount, authoritative: true)
            XCTAssertTrue(decision.apply)
            XCTAssertFalse(decision.provisional)
        }
    }
}
