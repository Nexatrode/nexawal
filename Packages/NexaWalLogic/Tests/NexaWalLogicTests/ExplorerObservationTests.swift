import XCTest
@testable import NexaWalLogic

final class ExplorerObservationTests: XCTestCase {
    let id = String(repeating: "a", count: 64)
    func body(_ edits: [String: Any] = [:]) throws -> Data {
        var json: [String: Any] = ["api_version": 1, "network": "mainnet", "txid": id, "status": "confirmed", "fee_piconero": "18446744073709551615", "block_height": 8, "block_hash": id, "block_timestamp": 900, "confirmations": 2, "chain_height": 10, "tip_hash": id, "node_ready": true, "observed_at": 1000]
        for (key, value) in edits { json[key] = value }
        return try JSONSerialization.data(withJSONObject: json)
    }
    func testExactFeeAndNodeWarning() throws {
        let value = try ExplorerObservation.parse(body(["node_ready": false]), txid: id, now: 1000)
        XCTAssertEqual(value.fee_piconero, "18446744073709551615")
        XCTAssertFalse(value.node_ready)
        XCTAssertEqual(value.confirmations, 2)
    }
    func testPendingAndUnknownFeeAreNotFabricated() throws {
        let value = try ExplorerObservation.parse(body(["status": "pending", "fee_piconero": NSNull(), "block_height": NSNull(), "block_hash": NSNull(), "block_timestamp": NSNull(), "confirmations": 0]), txid: id, now: 1000)
        XCTAssertNil(value.fee_piconero)
        XCTAssertNil(value.block_height)
    }
    func testWrongIdentityNetworkStatusFreshnessAndNumbersFail() throws {
        for edit: [String: Any] in [
            ["txid": String(repeating: "b", count: 64)], ["network": "stagenet"], ["api_version": 2],
            ["status": "success"], ["confirmations": 1], ["block_height": 10],
            ["fee_piconero": "18446744073709551616"], ["fee_piconero": "1e3"], ["fee_piconero": 1.5],
            ["observed_at": 699], ["observed_at": 1121], ["block_hash": "bad"], ["node_ready": "true"]
        ] {
            XCTAssertThrowsError(try ExplorerObservation.parse(body(edit), txid: id, now: 1000), "\(edit)")
        }
        XCTAssertThrowsError(try ExplorerObservation.parse(Data(repeating: 32, count: 16_385), txid: id, now: 1000))
        XCTAssertFalse(ExplorerObservation.validID("../" + id))
    }
}
