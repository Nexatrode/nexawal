import XCTest
@testable import NexaWalLogic

final class WalletSessionAuthorityTests: XCTestCase {
    func testBackgroundBeforeOpenRejectsNativeMutation() throws {
        let authority = WalletSessionAuthority()
        let old = authority.token()
        authority.invalidate()
        var opened = false
        XCTAssertThrowsError(try authority.withCurrent(old) { opened = true })
        XCTAssertFalse(opened)
        try authority.withCurrent(authority.token()) { opened = true }
        XCTAssertTrue(opened)
    }
    func testBackgroundBetweenAsyncStagesPreventsPublication() async throws {
        let authority = WalletSessionAuthority()
        let token = authority.token()
        try authority.check(token)
        await Task.yield()
        authority.invalidate()
        var published = false
        XCTAssertThrowsError(try authority.withCurrent(token) { published = true })
        XCTAssertFalse(published)
    }
    func testOldAttemptCannotBecomeValidAfterAnotherUnlock() {
        let authority = WalletSessionAuthority()
        let old = authority.token()
        authority.invalidate()
        let next = authority.token()
        XCTAssertFalse(authority.accepts(old))
        XCTAssertTrue(authority.accepts(next))
    }
}
