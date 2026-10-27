import Foundation
import XCTest
@testable import DaemonProbeHarness

final class DaemonProbeTests: XCTestCase {
    private var origin: String { ProcessInfo.processInfo.environment["NEXAWAL_PROBE_FIXTURE"]! }

    func testNormalResponseAndHeightFallback() async throws {
        let info = try await MoneroDaemonClient.getInfo(baseURL: origin + "/normal")
        XCTAssertEqual(info, MoneroDaemonInfo(height: 42, targetHeight: 45))
        let fallback = try await MoneroDaemonClient.getInfo(baseURL: origin + "/fallback")
        XCTAssertEqual(fallback, MoneroDaemonInfo(height: 40, targetHeight: 40))
    }

    func testOversizedKnownUnknownAndChunkedBodiesAreRejectedWithoutFallback() async throws {
        for mode in ["large", "unknown", "chunked", "gzip"] {
            do {
                _ = try await MoneroDaemonClient.getInfo(baseURL: origin + "/" + mode)
                XCTFail("Accepted oversized \(mode) body")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("65536"), error.localizedDescription)
            }
            let (data, _) = try await URLSession.shared.data(from: URL(string: origin + "/stats/" + mode)!)
            XCTAssertEqual(String(decoding: data, as: UTF8.self), "1", "Size errors must not trigger /get_height")
        }
    }

    func testExactByteLimitIsAccepted() async throws {
        let info = try await MoneroDaemonClient.getInfo(baseURL: origin + "/exact")
        XCTAssertEqual(info.height, 42)
    }

    func testOverflowDisconnectsBeforeTheBodyFinishes() async throws {
        do {
            _ = try await MoneroDaemonClient.getInfo(baseURL: origin + "/slow-stream")
            XCTFail("Accepted oversized stream")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("65536"))
        }
        // Give the fixture time to observe the cancelled socket; it would otherwise
        // take over five seconds to finish transmitting the full synthetic body.
        var disconnected = false
        for _ in 0..<40 {
            let (data, _) = try await URLSession.shared.data(from: URL(string: origin + "/disconnected/slow-stream")!)
            if String(decoding: data, as: UTF8.self) == "1" { disconnected = true; break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(disconnected, "Overflow must cancel the underlying transfer")
        let (data, _) = try await URLSession.shared.data(from: URL(string: origin + "/sent/slow-stream")!)
        XCTAssertLessThan(Int(String(decoding: data, as: UTF8.self))!, 1024 * 1024)
        let (count, _) = try await URLSession.shared.data(from: URL(string: origin + "/stats/slow-stream")!)
        XCTAssertEqual(String(decoding: count, as: UTF8.self), "1")
    }

    func testOversizedFallbackIsRejected() async {
        do {
            _ = try await MoneroDaemonClient.getInfo(baseURL: origin + "/fallback-large")
            XCTFail("Accepted oversized fallback")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("65536"), error.localizedDescription)
        }
    }

    func testDaemonErrorTextIsBounded() async {
        for mode in ["http-error", "decode-error"] {
            do {
                _ = try await MoneroDaemonClient.getInfo(baseURL: origin + "/" + mode)
                XCTFail("Expected error")
            } catch {
                XCTAssertLessThan(error.localizedDescription.utf8.count, 1500)
            }
        }
    }

    func testRedirectsRemainDisabled() async {
        do {
            _ = try await MoneroDaemonClient.getInfo(baseURL: origin + "/redirect")
            XCTFail("Followed daemon redirect")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("302"), error.localizedDescription)
        }
    }

    func testTimeoutRemainsBounded() async {
        let started = Date()
        do {
            _ = try await MoneroDaemonClient.getInfo(baseURL: origin + "/slow", timeout: 0.2)
            XCTFail("Expected timeout")
        } catch {
            XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        }
    }
}
