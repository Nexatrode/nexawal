import XCTest
@testable import NexaWalLogic

/// Intentionally ignores cancellation until released, like a response already
/// queued by the network. No real URL, wallet, Keychain or phone is accessed.
private final class DelayedExplorer: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [(UUID, String, CheckedContinuation<ExplorerObservation, Error>?)] = []
    private var cancelled = Set<UUID>()
    var count: Int { lock.withLock { requests.count } }
    var cancelCount: Int { lock.withLock { cancelled.count } }

    func fetch(_ txid: String) async throws -> ExplorerObservation {
        let id = UUID()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock { requests.append((id, txid, continuation)) }
            }
        }, onCancel: { self.lock.withLock { _ = self.cancelled.insert(id) } })
    }

    func complete(_ index: Int, error: ExplorerLookupFailure? = nil) throws {
        let (txid, continuation) = lock.withLock { () -> (String, CheckedContinuation<ExplorerObservation, Error>?) in
            let request = requests[index]; requests[index].2 = nil
            return (request.1, request.2)
        }
        if let error { continuation?.resume(throwing: error); return }
        let data = try JSONSerialization.data(withJSONObject: [
            "api_version": 1, "network": "mainnet", "txid": txid, "status": "pending",
            "fee_piconero": "44540000", "block_height": NSNull(), "block_hash": NSNull(),
            "block_timestamp": NSNull(), "confirmations": 0, "chain_height": 10,
            "tip_hash": String(repeating: "c", count: 64), "node_ready": true, "observed_at": 1000,
        ])
        continuation?.resume(returning: try ExplorerObservation.parse(data, txid: txid, now: 1000))
    }
}

@MainActor
final class ExplorerLookupTests: XCTestCase {
    private let id = String(repeating: "a", count: 64)
    private func context() -> ExplorerLookup.Context {
        .init(enabled: true, active: true, walletOpen: true, mainnet: true, walletSession: UUID())
    }
    private func waitFor(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<2000 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Timed out waiting for synthetic explorer", file: file, line: line)
        throw URLError(.timedOut)
    }
    private func drain() async {
        // Let a released continuation and the lookup's main-actor publication run.
        for _ in 0..<20 { await Task.yield() }
    }

    func testConsentAndNetworkGatesNeverFetchAutomatically() async throws {
        for field in 0..<4 {
            let network = DelayedExplorer()
            let lookup = ExplorerLookup(fetch: { try await network.fetch($0) })
            var ctx = context()
            switch field {
            case 0: ctx.enabled = false
            case 1: ctx.active = false
            case 2: ctx.walletOpen = false
            default: ctx.mainnet = false
            }
            lookup.open(txid: id, context: ctx)
            lookup.refresh()
            ctx.enabled = true; ctx.active = true; ctx.walletOpen = true; ctx.mainnet = true
            lookup.update(ctx)
            await drain()
            XCTAssertEqual(network.count, 0)
            lookup.refresh()
            try await waitFor { network.count == 1 }
            try network.complete(0)
            try await waitFor { lookup.observation != nil }
            lookup.close()
        }
        let network = DelayedExplorer()
        let lookup = ExplorerLookup(fetch: { try await network.fetch($0) })
        lookup.open(txid: "../bad", context: context()); lookup.refresh()
        await drain()
        XCTAssertEqual(network.count, 0)
    }

    func testBackgroundCancelsAndForegroundNeedsManualRefresh() async throws {
        let network = DelayedExplorer()
        // Use the exact production controller, with only its transport replaced.
        let subject = ExplorerLookup(fetch: { try await network.fetch($0) })
        var ctx = context()
        subject.open(txid: id, context: ctx)
        try await waitFor { network.count == 1 }
        ctx.active = false; subject.update(ctx)
        try await waitFor { network.cancelCount == 1 }
        XCTAssertFalse(subject.loading)
        ctx.active = true; subject.update(ctx)
        try network.complete(0)
        await drain()
        XCTAssertNil(subject.observation); XCTAssertNil(subject.failure)
        XCTAssertEqual(network.count, 1)
        subject.refresh()
        try await waitFor { network.count == 2 }
        try network.complete(1)
        try await waitFor { subject.observation != nil }
        ctx.active = false; subject.update(ctx)
        XCTAssertNil(subject.observation)
        subject.close()
    }

    func testCloseReopenRejectsOldSuccessAndDoesNotClearNewLoading() async throws {
        let network = DelayedExplorer(), ctx = context()
        let lookup = ExplorerLookup(fetch: { try await network.fetch($0) })
        lookup.open(txid: id, context: ctx)
        try await waitFor { network.count == 1 }
        lookup.close()
        try await waitFor { network.cancelCount == 1 }
        let other = String(repeating: "b", count: 64)
        lookup.open(txid: other, context: ctx)
        try await waitFor { network.count == 2 }
        try network.complete(0)
        await drain()
        XCTAssertNil(lookup.observation); XCTAssertTrue(lookup.loading)
        try network.complete(1)
        try await waitFor { lookup.observation?.txid == other }
        lookup.close()
    }

    func testDisableReenableDropsLateErrorsAndDoesNotAuthorizeLookup() async throws {
        let network = DelayedExplorer()
        let lookup = ExplorerLookup(fetch: { try await network.fetch($0) })
        var ctx = context()
        lookup.open(txid: id, context: ctx)
        try await waitFor { network.count == 1 }
        ctx.enabled = false; lookup.update(ctx)
        try await waitFor { network.cancelCount == 1 }
        ctx.enabled = true; lookup.update(ctx)
        try network.complete(0, error: .missing)
        await drain()
        XCTAssertEqual(network.count, 1); XCTAssertNil(lookup.failure)
        lookup.refresh()
        try await waitFor { network.count == 2 }
        try network.complete(1)
        try await waitFor { lookup.observation != nil }
        ctx.enabled = false; lookup.update(ctx)
        XCTAssertNil(lookup.observation)
        lookup.close()
    }

    func testLockAndWalletReplacementCannotReuseOldViewAuthority() async throws {
        for replace in [false, true] {
            let network = DelayedExplorer()
            let lookup = ExplorerLookup(fetch: { try await network.fetch($0) })
            var ctx = context()
            lookup.open(txid: id, context: ctx)
            try await waitFor { network.count == 1 }
            if replace { ctx.walletSession = UUID() } else { ctx.walletOpen = false }
            lookup.update(ctx)
            try await waitFor { network.cancelCount == 1 }
            try network.complete(0, error: .unavailable)
            lookup.refresh()
            await drain()
            XCTAssertEqual(network.count, 1); XCTAssertNil(lookup.failure); XCTAssertNil(lookup.observation)
            lookup.close()
            ctx.walletOpen = true
            lookup.open(txid: id, context: ctx)
            try await waitFor { network.count == 2 }
            try network.complete(1)
            try await waitFor { lookup.observation != nil }
            lookup.close()
        }
    }

    func testRepeatedAppearAndRefreshAreSingleFlight() async throws {
        let network = DelayedExplorer(), ctx = context()
        let lookup = ExplorerLookup(fetch: { try await network.fetch($0) })
        lookup.open(txid: id, context: ctx)
        lookup.open(txid: id, context: ctx)
        lookup.refresh(); lookup.refresh()
        try await waitFor { network.count == 1 }
        try network.complete(0)
        try await waitFor { lookup.observation != nil }
        XCTAssertEqual(network.count, 1)
        lookup.refresh()
        try await waitFor { network.count == 2 }
        try network.complete(1, error: .missing)
        try await waitFor { lookup.failure == .missing }
        XCTAssertNil(lookup.observation)
        lookup.close()
    }

    func testOldErrorCannotEraseACompletedNewRefresh() async throws {
        let network = DelayedExplorer()
        let lookup = ExplorerLookup(fetch: { try await network.fetch($0) })
        var ctx = context()
        lookup.open(txid: id, context: ctx)
        try await waitFor { network.count == 1 }
        ctx.active = false; lookup.update(ctx)
        ctx.active = true; lookup.update(ctx)
        lookup.refresh()
        try await waitFor { network.count == 2 }
        try network.complete(1)
        try await waitFor { lookup.observation != nil }
        try network.complete(0, error: .missing)
        await drain()
        XCTAssertEqual(lookup.observation?.txid, id)
        XCTAssertNil(lookup.failure); XCTAssertFalse(lookup.loading)
        lookup.close()
    }
}
