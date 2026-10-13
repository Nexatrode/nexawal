import XCTest
@testable import NexaWalLogic

final class SendPreviewIntentTests: XCTestCase {
    func testRecoveredPaymentDoesNotProceedIntoNewPayment() {
        var preparations = 0
        XCTAssertThrowsError(try {
            try SendSafety.requireNewPayment(recoveredTxid: "previous-txid")
            preparations += 1
        }()) { error in
            XCTAssertEqual((error as? SendSafety.PreviousPaymentRecovered)?.txid, "previous-txid")
        }
        XCTAssertEqual(preparations, 0)
        XCTAssertNoThrow(try SendSafety.requireNewPayment(recoveredTxid: nil))
    }
    func testEveryPaymentAuthorityInputInvalidatesAnEstimate() {
        func intent(_ address: String = "a", _ amount: UInt64? = 10, _ session: String = "wallet:1", _ node: String = "node", _ source: UInt32? = nil, _ maximum: Bool = false) -> SendPreviewIntent {
            SendPreviewIntent(destination: address, amount: amount, session: session, node: node, source: source, maximum: maximum)
        }
        let approved = intent()
        XCTAssertEqual(approved, intent())
        for changed in [intent("b"), intent("a", 11), intent("a", 10, "wallet:2"), intent("a", 10, "wallet:1", "other"), intent("a", 10, "wallet:1", "node", 1), intent("a", nil, "wallet:1", "node", nil, true)] {
            XCTAssertNotEqual(approved, changed)
        }
    }
    func testRatesRejectExtremeExponentPrecisionAndInvalidValues() {
        XCTAssertNotNil(FiatEstimate.serverRate("547.380000000000"))
        for value in ["1e1000000000", "1e-1000000000", "NaN", "0", "-1", "1." + String(repeating: "1", count: 1000), String(repeating: "9", count: 1000)] {
            XCTAssertNil(FiatEstimate.serverRate(value), value)
        }
    }
}
