import XCTest
@testable import NexaWalLogic

final class HistoryConfirmationsTests: XCTestCase {
    func testTipChangesDoNotRequireReloadingTheRow() {
        XCTAssertEqual(HistoryConfirmations.count(height: 100, pending: false, chainHeight: 100, cached: 1), 1)
        XCTAssertEqual(HistoryConfirmations.count(height: 100, pending: false, chainHeight: 109, cached: 1), 10)
        XCTAssertEqual(HistoryConfirmations.count(height: 100, pending: false, chainHeight: 102, cached: 10), 3)
        XCTAssertEqual(HistoryConfirmations.count(height: 100, pending: false, chainHeight: 99, cached: 10), 1)
    }
    func testPendingUnknownHeightAndNumericBoundaries() {
        XCTAssertEqual(HistoryConfirmations.count(height: 100, pending: true, chainHeight: 109, cached: 9), 0)
        XCTAssertEqual(HistoryConfirmations.count(height: nil, pending: false, chainHeight: 109, cached: 9), 9)
        XCTAssertEqual(HistoryConfirmations.count(height: 100, pending: false, chainHeight: 0, cached: 9), 9)
        XCTAssertEqual(HistoryConfirmations.count(height: 0, pending: false, chainHeight: 109, cached: 9), 0)
        XCTAssertEqual(HistoryConfirmations.count(height: 1, pending: false, chainHeight: .max, cached: 0), .max)
    }
}
