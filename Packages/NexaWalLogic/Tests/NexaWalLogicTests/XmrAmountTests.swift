import XCTest
@testable import NexaWalLogic

final class XmrAmountTests: XCTestCase {
    func testOneXmr() {
        XCTAssertEqual(XmrAmount.parsePiconero("1.0"), 1_000_000_000_000)
        XCTAssertEqual(XmrAmount.parsePiconero("1"), 1_000_000_000_000)
    }

    func testOnePiconero() {
        XCTAssertEqual(XmrAmount.parsePiconero("0.000000000001"), 1)
    }

    func testFormatForInput() {
        XCTAssertEqual(XmrAmount.formatForInput(1_000_000_000_000), "1")
        XCTAssertEqual(XmrAmount.formatForInput(500_000_000_000), "0.5")
        XCTAssertEqual(XmrAmount.formatForInput(1), "0.000000000001")
    }

    func testOverflowRejected() {
        XCTAssertNil(XmrAmount.parsePiconero("18446745"))
        XCTAssertNil(XmrAmount.parsePiconero("18446744073710.0"))
        XCTAssertNil(XmrAmount.parsePiconero("999999999999999"))
    }

    func testInvalidRejected() {
        XCTAssertNil(XmrAmount.parsePiconero(""))
        XCTAssertNil(XmrAmount.parsePiconero("abc"))
        XCTAssertNil(XmrAmount.parsePiconero("1.2.3"))
        XCTAssertNil(XmrAmount.parsePiconero("0.0000000000001"))
    }
}
