import XCTest
@testable import NexaWalLogic

final class FeeApprovalTests: XCTestCase {
    func testIncreasedFeeCannotPersistOrRelay() {
        var events: [String] = []
        XCTAssertThrowsError(try SendSafety.withApprovedFee(preparedFee: 101, approvedMaxFee: 100) {
            events.append("persist")
            events.append("relay")
        }) { XCTAssertEqual($0 as? SendSafety.FeeApprovalError, .feeIncreased) }
        XCTAssertTrue(events.isEmpty)
    }

    func testEqualOrLowerFeeCanProceedOnce() throws {
        for fee: UInt64 in [0, 99, 100] {
            var calls = 0
            let result = try SendSafety.withApprovedFee(preparedFee: fee, approvedMaxFee: 100) {
                calls += 1
                return "signed transaction"
            }
            XCTAssertEqual(result, "signed transaction")
            XCTAssertEqual(calls, 1)
        }
    }

    func testMaximumIntegerIsComparedWithoutOverflow() {
        XCTAssertThrowsError(try SendSafety.withApprovedFee(preparedFee: .max, approvedMaxFee: .max - 1) { XCTFail() })
    }
}
