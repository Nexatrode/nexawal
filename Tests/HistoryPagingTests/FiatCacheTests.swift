import Foundation
import XCTest
import NexaWalLogic
@testable import HistoryModelHarness

// The harness is a separate process/preferences domain, never the installed wallet app.
@MainActor
final class FiatCacheTests: XCTestCase {
    func testCacheRetainsDeadlineAcrossReloadAndClearsIt() {
        defer { MoneroConfig.setCachedFiatRate(nil) }
        let rate = FiatRate(currency: "USD", fiatPerXmr: 100, fetchedAtMs: 1_000_000,
                            source: "nexatrode", expiresAtMs: 1_001_000)
        MoneroConfig.setCachedFiatRate(rate)
        let restored = MoneroConfig.cachedFiatRate()
        XCTAssertEqual(restored, rate)
        XCTAssertNil(FiatEstimate.liveRate(restored, nowMs: 1_001_000))
        MoneroConfig.setCachedFiatRate(nil)
        XCTAssertNil(MoneroConfig.cachedFiatRate())
    }

    func testLegacyQuoteIsNotReusedWithoutServerDeadline() {
        defer { MoneroConfig.setCachedFiatRate(nil) }
        MoneroConfig.setCachedFiatRate(FiatRate(currency: "USD", fiatPerXmr: 100,
            fetchedAtMs: 1_000_000, source: "nexatrode"))
        XCTAssertNil(MoneroConfig.cachedFiatRate())
    }

    func testExpiredQuoteCannotCreateAHistoricalSnapshot() {
        let id = "expiry-regression-" + UUID().uuidString
        let rate = FiatRate(currency: "USD", fiatPerXmr: 100, fetchedAtMs: 1_000_000,
                            source: "nexatrode", expiresAtMs: 1_001_000)
        defer {
            UserDefaults.standard.removeObject(forKey: FiatSnapshotStore.snapshotsKey)
            UserDefaults.standard.removeObject(forKey: FiatSnapshotStore.observedKey)
        }
        FiatSnapshotStore.record(txid: id, rate: rate, kind: "send", nowMs: 1_001_000)
        XCTAssertNil(FiatSnapshotStore.snapshot(for: id))
        FiatSnapshotStore.record(txid: id, rate: rate, kind: "send", nowMs: 1_000_999)
        XCTAssertNotNil(FiatSnapshotStore.snapshot(for: id))
        // Expiry doesn't erase a genuine earlier snapshot.
        FiatSnapshotStore.record(txid: id, rate: rate, kind: "send", nowMs: 1_001_000)
        XCTAssertNotNil(FiatSnapshotStore.snapshot(for: id))
    }
}
