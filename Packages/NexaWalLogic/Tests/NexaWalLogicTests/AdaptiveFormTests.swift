import XCTest
import CoreGraphics
@testable import NexaWalLogic

final class AdaptiveFormTests: XCTestCase {
    func testDraftsKeepIndependentInputsAndUnits() {
        var send = SendFormDraft()
        send.toAddress = "layout-test-not-a-payment-address"
        send.amount = "12.34"
        send.amountMode = .fiat
        send.paymentDescription = "Test invoice"
        send.recipientName = "Test recipient"
        send.fromSubaddressMinor = 7
        send.sendFromSubaddressEnabled = true
        var receive = ReceiveFormDraft()
        receive.amount = "0.5"
        receive.description = "Test request"
        receive.newSubaddressLabel = "Draft label"
        let restoredSend = send
        let restoredReceive = receive
        XCTAssertEqual(restoredSend, send)
        XCTAssertEqual(restoredReceive, receive)
        XCTAssertEqual(restoredSend.amountMode, .fiat)
        XCTAssertEqual(restoredReceive.amountMode, .xmr)
        // A new unlocked session starts with empty inputs, not last session's draft.
        XCTAssertNotEqual(SendFormDraft(), restoredSend)
        XCTAssertEqual(SendFormDraft().toAddress, "")
        XCTAssertEqual(ReceiveFormDraft().description, "")
    }

    func testScannerFitsPhoneAndTabletSafeAreas() {
        for size in [CGSize(width: 320, height: 480), CGSize(width: 375, height: 647),
                     CGSize(width: 350, height: 560), CGSize(width: 667, height: 300),
                     CGSize(width: 744, height: 1050), CGSize(width: 1100, height: 760)] {
            let safe = CGRect(origin: CGPoint(x: 20, y: 44), size: size)
            assertUsable(QRScannerLayout.resolve(safeBounds: safe), inside: safe)
        }
    }

    func testScannerAvoidsBookAndTabletopHingesIncludingMargins() {
        let safe = CGRect(x: 20, y: 40, width: 1000, height: 720)
        for fold in [CGRect(x: 480, y: 0, width: 40, height: 800),
                     CGRect(x: 0, y: 380, width: 1100, height: 40)] {
            let layout = QRScannerLayout.resolve(safeBounds: safe, divisions: [fold])
            assertUsable(layout, inside: safe)
            for frame in [layout.scanArea, layout.close, layout.cancel, layout.instruction] {
                XCTAssertFalse(frame.intersects(fold), "Frame \(frame) crosses hinge \(fold)")
            }
        }
    }

    func testScannerRecomputesAllFramesOnResize() {
        let portrait = QRScannerLayout.resolve(safeBounds: CGRect(x: 0, y: 50, width: 350, height: 700))
        let landscape = QRScannerLayout.resolve(safeBounds: CGRect(x: 44, y: 0, width: 700, height: 300))
        XCTAssertNotEqual(portrait.scanArea, landscape.scanArea)
        XCTAssertNotEqual(portrait.close, landscape.close)
        XCTAssertNotEqual(portrait.cancel, landscape.cancel)
        XCTAssertNotEqual(portrait.instruction, landscape.instruction)
    }

    func testFormsUseCurrentViewportAndAvoidActiveDivisions() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 720)
        XCTAssertEqual(ContiguousLayoutRegion.resolve(bounds: bounds, divisions: []), bounds)
        let folds = [CGRect(x: 475, y: 0, width: 50, height: 720),
                     CGRect(x: 0, y: 330, width: 1000, height: 40)]
        for fold in folds {
            let panel = ContiguousLayoutRegion.resolve(bounds: bounds, divisions: [fold])
            XCTAssertTrue(bounds.contains(panel))
            XCTAssertFalse(panel.intersects(fold))
            XCTAssertGreaterThan(panel.width * panel.height, 0)
        }
        XCTAssertEqual(ContiguousLayoutRegion.resolve(bounds: .zero, divisions: []), .zero)
        XCTAssertEqual(QRScannerLayout.resolve(safeBounds: .zero).cancel, .zero)
    }

    private func assertUsable(_ layout: QRScannerLayout, inside safe: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        for frame in [layout.scanArea, layout.close, layout.cancel, layout.instruction] {
            XCTAssertTrue(safe.contains(frame), "Frame \(frame) outside \(safe)", file: file, line: line)
        }
        XCTAssertEqual(layout.scanArea.width, layout.scanArea.height, file: file, line: line)
        XCTAssertGreaterThan(layout.scanArea.width, 80, file: file, line: line)
        XCTAssertGreaterThanOrEqual(layout.cancel.height, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(layout.close.height, 44, file: file, line: line)
        XCTAssertFalse(layout.scanArea.intersects(layout.cancel), file: file, line: line)
        XCTAssertFalse(layout.instruction.intersects(layout.cancel), file: file, line: line)
        XCTAssertFalse(layout.scanArea.intersects(layout.close), file: file, line: line)
    }
}
