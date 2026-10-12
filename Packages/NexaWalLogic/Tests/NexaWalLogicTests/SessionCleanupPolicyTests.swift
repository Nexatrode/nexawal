import XCTest
@testable import NexaWalLogic

final class SessionCleanupPolicyTests: XCTestCase {
    enum Failure: Error { case busy, invalid }

    func testCloseCannotBeDowngradedAndPauseCancelsViewOnlyContinuation() {
        var intent = SessionCleanupIntent()
        intent.request(close: false, continueRefresh: true)
        XCTAssertTrue(intent.continueRefresh)
        intent.request(close: false, continueRefresh: false)
        XCTAssertFalse(intent.continueRefresh)
        intent.request(close: true, continueRefresh: false)
        intent.request(close: false, continueRefresh: true)
        XCTAssertTrue(intent.close)
        XCTAssertFalse(intent.continueRefresh)
    }

    func testRepeatedTimeoutsMustFinishBeforeReturning() async throws {
        var attempts = 0
        var sealed = false
        try await SessionCleanupPolicy.complete(retryDelayNanoseconds: 1,
            isRetryable: { ($0 as? Failure) == .busy }) {
                attempts += 1
                if attempts < 4 { throw Failure.busy }
                sealed = true
            }
        XCTAssertEqual(attempts, 4)
        XCTAssertTrue(sealed)
    }

    func testOtherFailuresAreNotRetriedOrReportedComplete() async {
        var attempts = 0
        do {
            try await SessionCleanupPolicy.complete(retryDelayNanoseconds: 1,
                isRetryable: { ($0 as? Failure) == .busy }) {
                    attempts += 1
                    throw Failure.invalid
                }
            XCTFail("Cleanup falsely reported success")
        } catch { XCTAssertEqual(attempts, 1) }
    }
}
