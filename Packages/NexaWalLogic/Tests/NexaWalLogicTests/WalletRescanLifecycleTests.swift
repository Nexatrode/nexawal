import XCTest
@testable import NexaWalLogic

@MainActor
private final class RescanFixture {
    enum Stage { case cancellation, scan, finish }
    enum Failure: Error { case nodeUnavailable }
    let authority = WalletSessionAuthority()
    var waiting: CheckedContinuation<Void, Never>?
    var events: [String] = []
    var seed = "synthetic seed"
    var history = [1, 2]
    var refreshing = false

    func pause() async { await withCheckedContinuation { waiting = $0 } }
    func resume() { waiting?.resume(); waiting = nil }
    func lockAndReplace() {
        authority.invalidate()
        seed = ""
        history = [99]
        refreshing = true // owned by the replacement session, not the old rescan
    }
    func run(pauseAt: Stage? = nil, failScan: Bool = false) async {
        let token = authority.token()
        await WalletRescanLifecycle.run(authority: authority, token: token, cancelRefresh: {
            self.events.append("cancel")
            if pauseAt == .cancellation { await self.pause() }
        }, begin: {
            self.events.append("begin")
            self.history = []
            self.refreshing = true
        }, scan: {
            self.events.append("scan")
            if pauseAt == .scan { await self.pause() }
            if failScan { throw Failure.nodeUnavailable }
            // Mirrors the manager's protected native reset boundary.
            return try self.authority.withCurrent(token) { 42 }
        }, finish: { _ in
            self.events.append("finish")
            if pauseAt == .finish { await self.pause() }
            // Mirrors finishSuccessfulRefresh's post-snapshot session check.
            try self.authority.check(token)
            self.events.append("publish")
            self.history = [42]
        }, cleanup: {
            self.events.append("cleanup")
            self.refreshing = false
        }, failure: { _ in self.events.append("failure") })
    }
}

@MainActor
final class WalletRescanLifecycleTests: XCTestCase {
    private func waitForPause(_ fixture: RescanFixture) async {
        for _ in 0..<10_000 {
            if fixture.waiting != nil { return }
            await Task.yield()
        }
        XCTFail("rescan did not reach the requested suspension point")
    }

    func testLockDuringCancellationDoesNotBeginOrRestoreSeed() async {
        let fixture = RescanFixture()
        let task = Task { await fixture.run(pauseAt: .cancellation) }
        await waitForPause(fixture)
        fixture.lockAndReplace()
        fixture.resume()
        await task.value
        XCTAssertEqual(fixture.events, ["cancel"])
        XCTAssertEqual(fixture.seed, "")
        XCTAssertEqual(fixture.history, [99])
        XCTAssertTrue(fixture.refreshing)
    }

    func testLockDuringScanDoesNotResetNativeOrPublishOrCleanNewSession() async {
        let fixture = RescanFixture()
        let task = Task { await fixture.run(pauseAt: .scan) }
        await waitForPause(fixture)
        fixture.lockAndReplace()
        fixture.resume()
        await task.value
        XCTAssertEqual(fixture.events, ["cancel", "begin", "scan"])
        XCTAssertEqual(fixture.history, [99])
        XCTAssertTrue(fixture.refreshing)
    }

    func testLockDuringFinalSnapshotDoesNotPublishOrCleanNewSession() async {
        let fixture = RescanFixture()
        let task = Task { await fixture.run(pauseAt: .finish) }
        await waitForPause(fixture)
        fixture.lockAndReplace()
        fixture.resume()
        await task.value
        XCTAssertEqual(fixture.events, ["cancel", "begin", "scan", "finish"])
        XCTAssertEqual(fixture.history, [99])
        XCTAssertTrue(fixture.refreshing)
    }

    func testLateNodeFailureCannotWriteAnErrorIntoReplacementSession() async {
        let fixture = RescanFixture()
        let task = Task { await fixture.run(pauseAt: .scan, failScan: true) }
        await waitForPause(fixture)
        fixture.lockAndReplace()
        fixture.resume()
        await task.value
        XCTAssertEqual(fixture.events, ["cancel", "begin", "scan"])
        XCTAssertEqual(fixture.history, [99])
        XCTAssertTrue(fixture.refreshing)
    }

    func testCancelledCurrentSessionStillCleansUpWithoutFailureDialog() async {
        let fixture = RescanFixture()
        let task = Task { await fixture.run(pauseAt: .scan) }
        await waitForPause(fixture)
        task.cancel()
        fixture.resume()
        await task.value
        XCTAssertEqual(fixture.events, ["cancel", "begin", "scan", "cleanup"])
        XCTAssertFalse(fixture.refreshing)
    }

    func testHealthyRescanPublishesAndCleansUp() async {
        let fixture = RescanFixture()
        await fixture.run()
        XCTAssertEqual(fixture.events, ["cancel", "begin", "scan", "finish", "publish", "cleanup"])
        XCTAssertEqual(fixture.history, [42])
        XCTAssertFalse(fixture.refreshing)
    }

    func testCurrentSessionErrorCleansUpAndReportsFailure() async {
        let fixture = RescanFixture()
        await fixture.run(failScan: true)
        XCTAssertEqual(fixture.events, ["cancel", "begin", "scan", "cleanup", "failure"])
        XCTAssertFalse(fixture.refreshing)
    }
}
