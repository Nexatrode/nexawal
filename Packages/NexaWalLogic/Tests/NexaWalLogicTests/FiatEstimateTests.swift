import XCTest
@testable import NexaWalLogic

final class FiatEstimateTests: XCTestCase {
    private let krakenUsd = """
    {"error":[],"result":{"XXMRZUSD":{"a":["356.73000000","9","9.000"],"b":["356.61000000","1","1.000"],"c":["356.85000000","0.02761000"],"v":["4487.01313992","6468.48583715"]}}}
    """
    private let krakenEur = """
    {"error":[],"result":{"XXMRZEUR":{"c":["308.84000000","0.06719369"]}}}
    """
    private let frankfurter = """
    {"amount":1.0,"base":"USD","date":"2026-08-05","rates":{"BRL":5.1153,"CAD":1.4047,"EUR":0.8655,"GBP":0.74191,"JPY":157.59}}
    """

    func testParseKrakenLastTrade() {
        XCTAssertEqual(FiatEstimate.parseKrakenLastTrade(json: krakenUsd), Decimal(string: "356.85000000"))
        XCTAssertEqual(FiatEstimate.parseKrakenLastTrade(json: krakenEur), Decimal(string: "308.84000000"))
        XCTAssertNil(FiatEstimate.parseKrakenLastTrade(json: "{}"))
    }

    func testParseFrankfurterAndCombine() {
        XCTAssertEqual(FiatEstimate.parseFrankfurterRate(json: frankfurter, symbol: "GBP"), Decimal(string: "0.74191"))
        XCTAssertEqual(FiatEstimate.parseFrankfurterRate(json: frankfurter, symbol: "JPY"), Decimal(string: "157.59"))
        XCTAssertEqual(FiatEstimate.parseFrankfurterRate(json: frankfurter, symbol: "USD"), 1)
        XCTAssertNil(FiatEstimate.parseFrankfurterRate(json: frankfurter, symbol: "UAH"))

        let usd = FiatEstimate.parseKrakenLastTrade(json: krakenUsd)!
        let gbpFx = FiatEstimate.parseFrankfurterRate(json: frankfurter, symbol: "GBP")!
        let gbpPerXmr = FiatEstimate.combine(usdPerXmr: usd, usdToFiat: gbpFx)
        XCTAssertEqual(gbpPerXmr, usd * gbpFx)
    }

    func testFreshnessBoundary() {
        let fetched: Int64 = 1_000_000
        XCTAssertTrue(FiatEstimate.isFresh(fetchedAtMs: fetched, nowMs: fetched + FiatEstimate.maxAgeMs - 1))
        XCTAssertFalse(FiatEstimate.isFresh(fetchedAtMs: fetched, nowMs: fetched + FiatEstimate.maxAgeMs))
        XCTAssertFalse(FiatEstimate.isFresh(fetchedAtMs: fetched, nowMs: fetched - 1))
    }

    func testConversionAndFormatting() {
        let usdRate = FiatRate(
            currency: "USD",
            fiatPerXmr: Decimal(string: "356.85")!,
            fetchedAtMs: 10,
            source: "kraken"
        )
        XCTAssertEqual(FiatEstimate.fiatAmount(piconero: 1_000_000_000_000, fiatPerXmr: usdRate.fiatPerXmr), Decimal(string: "356.85"))
        XCTAssertEqual(FiatEstimate.formatApprox(piconero: 1_000_000_000_000, rate: usdRate), "≈ $356.85")
        XCTAssertEqual(
            FiatEstimate.liveApproxText(piconero: 1_000_000_000_000, rate: usdRate, nowMs: 10 + 60_000),
            "≈ $356.85"
        )
        XCTAssertNil(FiatEstimate.liveApproxText(piconero: 1_000_000_000_000, rate: usdRate, nowMs: 10 + FiatEstimate.maxAgeMs))

        let dust = FiatEstimate.fiatAmount(piconero: 1, fiatPerXmr: usdRate.fiatPerXmr)
        XCTAssertEqual(FiatEstimate.formatApprox(dust, currency: "USD"), "≈ $0.00")

        let jpyRate = FiatRate(currency: "JPY", fiatPerXmr: Decimal(string: "56234.4")!, fetchedAtMs: 10, source: "kraken+frankfurter")
        XCTAssertEqual(FiatEstimate.formatApprox(piconero: 1_000_000_000_000, rate: jpyRate), "≈ ¥56,234")
        XCTAssertEqual(
            FiatEstimate.recordedApproxText(piconero: 1_000_000_000_000, fiatPerXmr: usdRate.fiatPerXmr, currency: "USD"),
            "≈ $356.85"
        )
    }

    func testLocaleHint() {
        XCTAssertEqual(FiatEstimate.hintedCurrency(localeCurrencyCode: "eur"), "EUR")
        XCTAssertEqual(FiatEstimate.hintedCurrency(localeCurrencyCode: "UAH"), "USD")
        XCTAssertEqual(FiatEstimate.hintedCurrency(localeCurrencyCode: nil), "USD")
    }

    func testSeenSnapshotSkipsHistoryBeforeOptIn() {
        let optedIn: Int64 = 1_700_000_000_000
        XCTAssertFalse(FiatEstimate.shouldRecordSeenSnapshot(txTimestampSeconds: nil, optedInAtMs: optedIn))
        XCTAssertFalse(FiatEstimate.shouldRecordSeenSnapshot(txTimestampSeconds: 0, optedInAtMs: optedIn))
        XCTAssertFalse(FiatEstimate.shouldRecordSeenSnapshot(txTimestampSeconds: 1_699_999_999, optedInAtMs: optedIn))
        XCTAssertTrue(FiatEstimate.shouldRecordSeenSnapshot(txTimestampSeconds: 1_700_000_000, optedInAtMs: optedIn))
        XCTAssertTrue(FiatEstimate.shouldRecordSeenSnapshot(txTimestampSeconds: 1_700_000_001, optedInAtMs: optedIn))
        XCTAssertFalse(FiatEstimate.shouldRecordSeenSnapshot(txTimestampSeconds: 1_800_000_000, optedInAtMs: 0))
        XCTAssertEqual(FiatEstimate.msUntilStale(fetchedAtMs: 10, nowMs: 10 + FiatEstimate.maxAgeMs - 5), 5)
        XCTAssertEqual(FiatEstimate.msUntilStale(fetchedAtMs: 10, nowMs: 10 + FiatEstimate.maxAgeMs), 0)
    }
}
