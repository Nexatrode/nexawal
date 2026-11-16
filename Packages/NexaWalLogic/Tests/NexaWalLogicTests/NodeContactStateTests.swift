import XCTest
@testable import NexaWalLogic

final class NodeContactStateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testSuccessBetweenDisplayTicksIsFreshWhenEvaluatedAtCurrentTime() throws {
        var state = NodeContactState()
        let nextObservation = start.addingTimeInterval(5)
        XCTAssertTrue(state.succeed(probe: try XCTUnwrap(state.beginProbe()), at: nextObservation))
        // The view evaluates current time on each published update; it must not
        // reuse the timestamp from the previous 15-second display tick.
        XCTAssertEqual(state.status(at: nextObservation.addingTimeInterval(0.001)), .fresh)
        XCTAssertEqual(state.status(at: start), .stale)
    }

    func testUnknownThenSuccessfulContactExpiresIndependentlyOfScanCompletion() throws {
        var state = NodeContactState()
        XCTAssertEqual(state.status(at: start), .unknown)
        let probe = try XCTUnwrap(state.beginProbe())
        XCTAssertTrue(state.isChecking)
        XCTAssertTrue(state.succeed(probe: probe, at: start))
        XCTAssertEqual(state.status(at: start.addingTimeInterval(180)), .fresh)
        XCTAssertEqual(state.status(at: start.addingTimeInterval(181)), .stale)
        XCTAssertEqual(state.status(at: start.addingTimeInterval(-1)), .stale)
        XCTAssertFalse(state.isChecking)
    }

    func testFailedProbeRetainsLastSuccessfulObservationAndRecoveryClearsFailure() throws {
        var state = NodeContactState()
        XCTAssertTrue(state.succeed(probe: try XCTUnwrap(state.beginProbe()), at: start))
        XCTAssertTrue(state.fail(probe: try XCTUnwrap(state.beginProbe())))
        XCTAssertEqual(state.status(at: start), .unavailable)
        XCTAssertEqual(state.lastSuccess, start)
        XCTAssertTrue(state.succeed(probe: try XCTUnwrap(state.beginProbe()), at: start.addingTimeInterval(10)))
        XCTAssertEqual(state.status(at: start.addingTimeInterval(10)), .fresh)
    }

    func testResetRejectsOldNodeAndSessionResults() throws {
        var state = NodeContactState()
        let oldGeneration = state.generation
        let oldProbe = try XCTUnwrap(state.beginProbe())
        state.reset()
        let newProbe = try XCTUnwrap(state.beginProbe())
        XCTAssertFalse(state.succeed(probe: oldProbe, at: start))
        XCTAssertFalse(state.fail(probe: oldProbe))
        XCTAssertFalse(state.recordSuccessfulContact(generation: oldGeneration, at: start))
        state.cancel(probe: oldProbe)
        XCTAssertTrue(state.isChecking)
        XCTAssertTrue(state.succeed(probe: newProbe, at: start))
    }

    func testProbeIsSingleFlightAndCancellationDoesNotBecomeAnOutage() throws {
        var state = NodeContactState()
        let probe = try XCTUnwrap(state.beginProbe())
        XCTAssertNil(state.beginProbe())
        state.cancel(probe: probe)
        XCTAssertFalse(state.isChecking)
        XCTAssertEqual(state.status(at: start), .unknown)
        XCTAssertFalse(state.fail(probe: probe))
        XCTAssertNotNil(state.beginProbe())
    }

    func testCompletedRefreshSupersedesAnOlderProbeFailure() throws {
        var state = NodeContactState()
        let probe = try XCTUnwrap(state.beginProbe())
        XCTAssertTrue(state.recordSuccessfulContact(generation: state.generation, at: start))
        XCTAssertFalse(state.fail(probe: probe))
        XCTAssertEqual(state.status(at: start), .fresh)
        state.reset()
        XCTAssertNil(state.lastSuccess)
        XCTAssertEqual(state.status(at: start), .unknown)
    }

    func testForegroundCancellationPreservesHistoryOfContactButRejectsLateProbe() throws {
        var state = NodeContactState()
        XCTAssertTrue(state.recordSuccessfulContact(generation: state.generation, at: start))
        let probe = try XCTUnwrap(state.beginProbe())
        state.cancelProbe()
        XCTAssertFalse(state.succeed(probe: probe, at: start.addingTimeInterval(100)))
        XCTAssertEqual(state.status(at: start.addingTimeInterval(181)), .stale)
        XCTAssertEqual(state.lastSuccess, start)
    }
}
