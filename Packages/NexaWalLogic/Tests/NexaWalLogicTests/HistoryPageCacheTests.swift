import XCTest
@testable import NexaWalLogic
final class HistoryPageCacheTests: XCTestCase {
    func testLatePagesCannotEvictTheVisiblePage() {
        var cache = HistoryPageCache<Int>()
        // Current page completes first; four older requests complete after it.
        for offset in [250, 50, 100, 150, 200] {
            cache.insert(Array(offset..<offset + 50), offset: offset, protecting: [250])
        }
        XCTAssertEqual(cache.row(at: 250), 250)
        XCTAssertLessThanOrEqual(cache.storedRowCount, 200)
        XCTAssertNil(cache.row(at: 50))
    }

    func testProtectionMovesWithTheViewportAndStaysBounded() {
        var cache = HistoryPageCache<Int>()
        for offset in stride(from: 0, to: 500, by: 50) {
            cache.insert(Array(offset..<offset + 50), offset: offset, protecting: [offset])
        }
        XCTAssertNil(cache.row(at: 0))
        cache.insert(Array(0..<50), offset: 0, protecting: [0])
        XCTAssertEqual(cache.row(at: 0), 0)
        XCTAssertLessThanOrEqual(cache.storedRowCount, 200)
    }
    func testTenThousandRowsStayBoundedAndOlderPagesReload() {
        var cache = HistoryPageCache<Int>()
        for offset in stride(from: 0, to: 10000, by: 50) {
            cache.insert(Array(offset..<(offset + 50)), offset: offset)
            XCTAssertLessThanOrEqual(cache.storedRowCount, 200)
            XCTAssertEqual(cache.row(at: offset + 49), offset + 49)
        }
        XCTAssertNil(cache.row(at: 0))
        cache.insert(Array(0..<50), offset: 0)
        XCTAssertEqual(cache.row(at: 0), 0)
        XCTAssertLessThanOrEqual(cache.storedRowCount, 200)
        cache.clear()
        XCTAssertNil(cache.row(at: 0))
    }
}
