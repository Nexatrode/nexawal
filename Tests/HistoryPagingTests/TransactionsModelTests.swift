import XCTest
import MoneroWalletCoreFFI
import NexaWalLogic
@testable import HistoryModelHarness

private actor PageSource {
    var waiting: [Int: CheckedContinuation<WalletCoreFFIClient.HistoryPage, Error>] = [:]
    var calls = 0
    func fetch(id: String, query: WalletCoreFFIClient.HistoryQuery) async throws -> WalletCoreFFIClient.HistoryPage {
        calls += 1
        if query.offset == 0 { return try Self.page(id: id, offset: 0) }
        return try await withCheckedThrowingContinuation { waiting[query.offset] = $0 }
    }
    func isWaiting(_ offset: Int) -> Bool { waiting[offset] != nil }
    func finish(_ offset: Int, id: String = "fixture") throws {
        waiting.removeValue(forKey: offset)?.resume(returning: try Self.page(id: id, offset: offset))
    }
    func fail(_ offset: Int) { waiting.removeValue(forKey: offset)?.resume(throwing: Failure()) }
    struct Failure: LocalizedError { var errorDescription: String? { "stale_history_cursor" } }
    static func page(id: String, offset: Int) throws -> WalletCoreFFIClient.HistoryPage {
        let rows = (offset..<offset + 50).map {
            """
            {"txid":"\(String(format: "%064x", $0))","direction":"in","amount":1,"height":100,"confirmations":1,"is_pending":false}
            """
        }.joined(separator: ",")
        return try WalletCoreFFIClient.decodeHistoryPageJSON("""
        {"schema_version":1,"wallet_id":"\(id)","revision":"\(id)","total_count":1000,"matching_count":1000,"pending_count":0,"offset":\(offset),"next_offset":\(offset + 50),"last_scanned_height":100,"chain_height":100,"chain_time":1,"transfers":[\(rows)]}
        """, expectedWalletId: id)
    }
}

@MainActor
final class TransactionsModelTests: XCTestCase {
    func testLateViewportResponsesDoNotEvictVisibleRows() async throws {
        let source = PageSource()
        let model = TransactionsModel(fetch: { try await source.fetch(id: $0, query: $1) })
        await model.reset(walletId: "fixture", query: .init())
        var tasks: [Int: Task<Void, Never>] = [:]
        for offset in [50, 100, 150, 200, 250] {
            model.visibleIndices = [offset]
            tasks[offset] = Task { await model.load(index: offset, onlyIfVisible: true) }
            while !(await source.isWaiting(offset)) { await Task.yield() }
        }
        // Newest visible page wins; old responses arrive in reverse viewport order.
        for offset in [250, 50, 100, 150, 200] {
            try await source.finish(offset)
            await tasks[offset]!.value
        }
        XCTAssertNotNil(model.cache.row(at: 250))
        XCTAssertNil(model.cache.row(at: 50))
        XCTAssertLessThanOrEqual(model.cache.storedRowCount, 200)
        XCTAssertFalse(model.loading)
        XCTAssertFalse(model.changed)
        XCTAssertNil(model.error)
    }

    func testObsoleteFailureCannotFreezeCurrentViewport() async throws {
        let source = PageSource()
        let model = TransactionsModel(fetch: { try await source.fetch(id: $0, query: $1) })
        await model.reset(walletId: "fixture", query: .init())
        model.visibleIndices = [50]
        let task = Task { await model.load(index: 50, onlyIfVisible: true) }
        while !(await source.isWaiting(50)) { await Task.yield() }
        model.visibleIndices = [0]
        await source.fail(50); await task.value
        XCTAssertFalse(model.changed)
        XCTAssertNil(model.error)
        XCTAssertFalse(model.loading)
        XCTAssertNotNil(model.cache.row(at: 0))
    }

    func testReplacementRejectsOldResultAndTipChangeNeedsNoPageFetch() async throws {
        let source = PageSource()
        let model = TransactionsModel(fetch: { try await source.fetch(id: $0, query: $1) })
        await model.reset(walletId: "fixture", query: .init())
        model.visibleIndices = [50]
        let old = Task { await model.load(index: 50, onlyIfVisible: true) }
        while !(await source.isWaiting(50)) { await Task.yield() }
        await model.reset(walletId: "replacement", query: .init())
        try await source.finish(50); await old.value
        XCTAssertEqual(model.revision, "replacement")
        XCTAssertNil(model.cache.row(at: 50))
        let row = try XCTUnwrap(model.cache.row(at: 0))
        let callsBefore = await source.calls
        XCTAssertEqual(HistoryConfirmations.count(height: row.height, pending: row.isPending, chainHeight: 109, cached: row.confirmations), 10)
        XCTAssertEqual(HistoryConfirmations.count(height: row.height, pending: row.isPending, chainHeight: 102, cached: row.confirmations), 3)
        let callsAfter = await source.calls
        XCTAssertEqual(callsBefore, callsAfter)
        XCTAssertEqual(model.revision, "replacement")
    }
}
