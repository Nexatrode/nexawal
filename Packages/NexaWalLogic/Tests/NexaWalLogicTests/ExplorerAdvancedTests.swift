import XCTest
@testable import NexaWalLogic

@MainActor
private final class AdvancedGate {
    var requests = [UInt64?]()
    var continuation: CheckedContinuation<ExplorerObservation, Error>?
    func fetch(_ page: UInt64?, summary: ExplorerObservation) async throws -> ExplorerObservation {
        requests.append(page)
        if page == nil { return summary }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func complete(_ value: ExplorerObservation) { continuation?.resume(returning:value); continuation = nil }
}

@MainActor
final class ExplorerAdvancedTests: XCTestCase {
    private let id = String(repeating: "a", count: 64)
    private func body() throws -> [String: Any] {
        let url = Bundle.module.url(forResource: "explorer_advanced_page0", withExtension: "json", subdirectory: "Fixtures")!
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }
    private func parse(_ body: [String: Any], page: UInt64 = 0) throws -> ExplorerObservation {
        try ExplorerObservation.parse(JSONSerialization.data(withJSONObject: body), txid: id, now: 1000, page: page)
    }
    func testSharedFixturePreservesExactFeeConflictAndBoundedRows() throws {
        let data = try parse(body())
        XCTAssertEqual(data.fee_piconero,"18446744073709551615")
        XCTAssertEqual(data.double_spend_seen,true)
        XCTAssertEqual(data.details?.inputs.count,10); XCTAssertEqual(data.details?.outputs.count,10)
        XCTAssertEqual(data.details?.inputs[0].absolute_indices.count,16)
        XCTAssertNil(data.details?.outputs[0].public_amount_piconero)
        XCTAssertNil(data.details?.weight)
        XCTAssertThrowsError(try parse(body(),page:1))
        XCTAssertThrowsError(try ExplorerObservation.parse(JSONSerialization.data(withJSONObject: body()),txid:id,now:1000))
    }
    func testLastPageLegacyAmountsCoinbaseAndTruncation() throws {
        var b = try body(), d = b["details"] as! [String: Any]
        var inputs = d["inputs"] as! [[String: Any]], outputs = d["outputs"] as! [[String: Any]]
        inputs = [inputs[0]]; inputs[0]["index"] = 10
        outputs = Array(outputs.prefix(2)); outputs[0]["index"] = 10; outputs[1]["index"] = 11
        d["page"] = 1; d["inputs"] = inputs; d["outputs"] = outputs; b["details"] = d
        XCTAssertEqual(try parse(b,page:1).details?.inputs.count,1)
        b = try body(); d = b["details"] as! [String: Any]
        outputs = d["outputs"] as! [[String: Any]]
        for i in outputs.indices { outputs[i]["public_amount_piconero"] = "18446744073709551615" }
        d["version"] = 1; d["outputs"] = outputs; b["details"] = d
        XCTAssertEqual(try parse(b).details?.outputs[0].public_amount_piconero,"18446744073709551615")
        d["coinbase"] = true; d["input_count"] = 1; d["inputs"] = [[String: Any]](); b["fee_piconero"] = "0"; b["details"] = d
        XCTAssertTrue(try parse(b).details!.inputs.isEmpty)
        b = try body(); d = b["details"] as! [String: Any]; inputs = d["inputs"] as! [[String: Any]]
        inputs[0]["ring_size"] = 200; inputs[0]["absolute_indices"] = (0..<128).map(String.init); inputs[0]["indices_truncated"] = true
        d["inputs"] = inputs; d["extra_hex"] = String(repeating:"aa",count:2048); d["extra_truncated"] = true; b["details"] = d
        XCTAssertTrue(try parse(b).details!.inputs[0].indices_truncated)
    }
    func testMalformedPagesNeverBecomeEmptyOrFabricatedDetails() throws {
        for (key, value) in ["page_count": 1, "page_size": 25, "input_count": 4097, "inputs": [], "unlock_kind": "other", "extra_hex": "GG", "weight": -1] as [String: Any] {
            var b = try body(), d = b["details"] as! [String: Any]
            d[key] = value; b["details"] = d
            XCTAssertThrowsError(try parse(b),key)
        }
        var b = try body(), d = b["details"] as! [String: Any]
        var rows = d["inputs"] as! [[String: Any]]; rows[0]["absolute_indices"] = Array(repeating:"1",count:16)
        d["inputs"] = rows; b["details"] = d
        XCTAssertThrowsError(try parse(b))
        b = try body(); b["double_spend_seen"] = "false"
        XCTAssertThrowsError(try parse(b))
        XCTAssertThrowsError(try ExplorerObservation.parse(Data(repeating:32,count:65_537),txid:id,now:1000,page:0))
    }

    func testExpandCollapseAndBackgroundCannotPublishOldPageOrAutoFetch() async throws {
        let fixture = try parse(body())
        var baseBody = try body(); baseBody.removeValue(forKey:"details")
        let summary = try ExplorerObservation.parse(JSONSerialization.data(withJSONObject:baseBody),txid:id,now:1000)
        let gate = AdvancedGate()
        let lookup = ExplorerLookup(fetchPage: { _, page in
            try await gate.fetch(page,summary:summary)
        })
        var context = ExplorerLookup.Context(enabled:true,active:true,walletOpen:true,mainnet:true,walletSession:UUID())
        lookup.open(txid:id,context:context)
        for _ in 0..<1000 { if lookup.observation != nil { break }; try await Task.sleep(nanoseconds:1_000_000) }
        XCTAssertEqual(gate.requests.count,1)
        lookup.loadPage(0)
        for _ in 0..<1000 { if gate.continuation != nil { break }; try await Task.sleep(nanoseconds:1_000_000) }
        XCTAssertEqual(gate.requests.count,2)
        lookup.collapseAdvanced()
        gate.complete(fixture)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(lookup.advancedExpanded); XCTAssertNil(lookup.observation?.details)
        lookup.loadPage(0)
        for _ in 0..<1000 { if gate.continuation != nil { break }; try await Task.sleep(nanoseconds:1_000_000) }
        context.active = false; lookup.update(context)
        context.active = true; lookup.update(context)
        gate.complete(fixture)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(lookup.advancedExpanded); XCTAssertNil(lookup.observation)
        XCTAssertEqual(gate.requests.count,3)
        lookup.close()
    }
}
