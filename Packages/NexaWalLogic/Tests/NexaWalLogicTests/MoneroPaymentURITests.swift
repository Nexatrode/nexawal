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

    func testMixedCaseSchemeAndMetadataAreSupported() {
        let parsed = MoneroPaymentURI.parse(
            "MonErO://\(primary)?TX_AMOUNT=1.5&recipient_name=Coffee+Shop&message=two%20drinks%20%26%20tip"
        )
        XCTAssertEqual(parsed?.address, primary)
        XCTAssertEqual(parsed?.amountXmr, "1.5")
        XCTAssertEqual(parsed?.recipientName, "Coffee Shop")
        XCTAssertEqual(parsed?.txDescription, "two drinks & tip")
    }

    func testPlusAmountIsRejected() {
        XCTAssertNil(MoneroPaymentURI.parse("monero:\(primary)?tx_amount=%2B1.5"))
        XCTAssertNil(MoneroPaymentURI.parse("monero:\(primary)?tx_amount=+1.5"))
    }

    func testConflictingAmountsAreRejected() {
        XCTAssertNil(MoneroPaymentURI.parse("monero:\(primary)?amount=1.5&tx_amount=2.0"))
    }

    func testIdenticalAmountDuplicatesAreAccepted() {
        let parsed = MoneroPaymentURI.parse("monero:\(primary)?amount=1.5&tx_amount=1.5")
        XCTAssertEqual(parsed?.amountXmr, "1.5")
    }

    func testEquivalentAmountAliasesNormalize() {
        let parsed = MoneroPaymentURI.parse("monero:\(primary)?amount=1.5&tx_amount=1.500")
        XCTAssertEqual(parsed?.amountXmr, "1.5")
        XCTAssertEqual(
            MoneroPaymentURI.parseAmountPiconero("1.5"),
            MoneroPaymentURI.parseAmountPiconero("1.500")
        )
    }

    func testMoreThanTwelveFractionalDigitsRejected() {
        XCTAssertNil(MoneroPaymentURI.parseAmountPiconero("1.1234567890123"))
        XCTAssertNil(MoneroPaymentURI.parse("monero:\(primary)?tx_amount=1.1234567890123"))
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

    func testBuildUsesStrictQueryEncoding() {
        let uri = MoneroPaymentURI.build(
            address: primary,
            amountXmr: "1.25",
            description: "coffee & cake = good"
        )
        XCTAssertEqual(
            uri,
            "monero:\(primary)?tx_amount=1.25&tx_description=coffee%20%26%20cake%20%3D%20good"
        )
    }

    func testCompleteAddressShape() {
        XCTAssertTrue(MoneroPaymentURI.hasCompleteAddressShape(primary))
        XCTAssertFalse(MoneroPaymentURI.hasCompleteAddressShape("4abc"))
    }
}
