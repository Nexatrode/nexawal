import XCTest
@testable import NexaWalLogic

final class MoneroPaymentURITests: XCTestCase {
    private let primary =
        "4B33mFPMq6mKi7Eiyd5XuyKRVMGVZz1Rqb9ZTyGApXW5d1aT7UBDZ89ewmnWFkzJ5wPd2SFbn313vCT8a4E2Qf4KQH4pNey"

    func testAddressExtracted() {
        let parsed = MoneroPaymentURI.parse("monero:\(primary)")
        XCTAssertEqual(parsed?.address, primary)
        XCTAssertNil(parsed?.amountXmr)
    }

    func testAmountExtracted() {
        let parsed = MoneroPaymentURI.parse("monero:\(primary)?tx_amount=1.5")
        XCTAssertEqual(parsed?.address, primary)
        XCTAssertEqual(parsed?.amountXmr, "1.5")
    }

    func testSpendAndViewKeysIgnoredAsSendTargets() {
        let uri =
            "monero:\(primary)?spend_key=deadbeefdeadbeef&view_key=cafebabecafebabe&tx_amount=1.0"
        let parsed = MoneroPaymentURI.parse(uri)
        XCTAssertEqual(parsed?.address, primary)
        XCTAssertEqual(parsed?.amountXmr, "1.0")
        XCTAssertNotEqual(parsed?.address, "deadbeefdeadbeef")
        XCTAssertNotEqual(parsed?.address, "cafebabecafebabe")
    }

    func testSlashSlashPrefix() {
        let parsed = MoneroPaymentURI.parse("monero://\(primary)?amount=0.25")
        XCTAssertEqual(parsed?.address, primary)
        XCTAssertEqual(parsed?.amountXmr, "0.25")
    }

    func testNonMoneroRejected() {
        XCTAssertNil(MoneroPaymentURI.parse(primary))
        XCTAssertNil(MoneroPaymentURI.parse("bitcoin:\(primary)"))
    }
}
