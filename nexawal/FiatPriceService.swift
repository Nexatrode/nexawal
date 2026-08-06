import Combine
import Foundation
import NexaWalLogic

@MainActor
final class FiatPriceService: ObservableObject {
    static let shared = FiatPriceService()

    @Published private(set) var displayRate: FiatRate?

    private var loopTask: Task<Void, Never>?
    private var inFlight: Task<Void, Never>?
    private var staleTask: Task<Void, Never>?

    private init() {
        republishFromCache()
    }

    func onForeground() {
        republishFromCache()
        Task { await refreshIfNeeded(force: false) }
        startLoop()
    }

    func settingsDidChange() {
        republishFromCache()
        if !canFetch {
            publish(nil)
            stopLoop()
            return
        }
        _ = MoneroConfig.ensureFiatEstimatesEnabledAtMs()
        Task { await refreshIfNeeded(force: true) }
        startLoop()
    }

    var canFetch: Bool {
        MoneroConfig.fiatEstimatesEnabled
    }

    func recordSend(txid: String) {
        FiatSnapshotStore.record(txid: txid, rate: displayRate, kind: "send")
    }

    func recordSeenTransfers(_ transfers: [(txid: String, timestampSeconds: Int64?)]) {
        FiatSnapshotStore.recordNewTransfers(
            transfers: transfers,
            rate: displayRate,
            optedInAtMs: MoneroConfig.ensureFiatEstimatesEnabledAtMs()
        )
    }

    private func republishFromCache() {
        guard canFetch else {
            publish(nil)
            return
        }
        let now = nowMs()
        let currency = MoneroConfig.fiatCurrency
        guard let cached = MoneroConfig.cachedFiatRate(),
              cached.currency == currency,
              FiatEstimate.isFresh(fetchedAtMs: cached.fetchedAtMs, nowMs: now)
        else {
            publish(nil)
            return
        }
        publish(cached)
    }

    private func startLoop() {
        stopLoop()
        guard canFetch else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                let nanos = UInt64(FiatEstimate.refreshIntervalMs) * 1_000_000
                try? await Task.sleep(nanoseconds: nanos)
                guard !Task.isCancelled else { return }
                await self?.refreshIfNeeded(force: false)
            }
        }
    }

    private func stopLoop() {
        loopTask?.cancel()
        loopTask = nil
        staleTask?.cancel()
        staleTask = nil
    }

    func refreshIfNeeded(force: Bool) async {
        guard canFetch else {
            publish(nil)
            return
        }
        if shouldSkipFetch(force: force) { return }

        if let existing = inFlight {
            await existing.value
            guard canFetch else {
                publish(nil)
                return
            }
            if shouldSkipFetch(force: force) { return }
        }

        if let existing = inFlight {
            await existing.value
            if shouldSkipFetch(force: force) { return }
        }

        let currency = MoneroConfig.fiatCurrency
        let task = Task { await self.fetchAndPublish(currency: currency) }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func shouldSkipFetch(force: Bool) -> Bool {
        let currency = MoneroConfig.fiatCurrency
        let now = nowMs()
        guard !force,
              let current = displayRate,
              current.currency == currency,
              FiatEstimate.isFresh(fetchedAtMs: current.fetchedAtMs, nowMs: now)
        else {
            return false
        }
        return now - current.fetchedAtMs < FiatEstimate.refreshIntervalMs
    }

    private func fetchAndPublish(currency: String) async {
        do {
            let rate = try await Self.fetchRate(currency: currency)
            MoneroConfig.setCachedFiatRate(rate)
            if canFetch && MoneroConfig.fiatCurrency == currency {
                publish(FiatEstimate.liveRate(rate, nowMs: nowMs()))
            }
        } catch {
            republishFromCache()
        }
    }

    private func publish(_ rate: FiatRate?) {
        displayRate = FiatEstimate.liveRate(rate, nowMs: nowMs())
        scheduleStaleHide()
    }

    private func scheduleStaleHide() {
        staleTask?.cancel()
        guard let rate = displayRate else { return }
        let remaining = FiatEstimate.msUntilStale(fetchedAtMs: rate.fetchedAtMs, nowMs: nowMs())
        if remaining <= 0 {
            displayRate = nil
            return
        }
        staleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(remaining) * 1_000_000)
            guard !Task.isCancelled else { return }
            self?.displayRate = FiatEstimate.liveRate(self?.displayRate, nowMs: self?.nowMs() ?? 0)
        }
    }

    private static func fetchRate(currency: String) async throws -> FiatRate {
        let session = makeSession()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if currency == "EUR" {
            let last = try await fetchKrakenLastTrade(session: session, pair: "XMREUR")
            return FiatRate(currency: "EUR", fiatPerXmr: last, fetchedAtMs: now, source: "kraken")
        }
        let usd = try await fetchKrakenLastTrade(session: session, pair: "XMRUSD")
        if currency == "USD" {
            return FiatRate(currency: "USD", fiatPerXmr: usd, fetchedAtMs: now, source: "kraken")
        }
        let fx = try await fetchFrankfurter(session: session, symbol: currency)
        return FiatRate(
            currency: currency,
            fiatPerXmr: FiatEstimate.combine(usdPerXmr: usd, usdToFiat: fx),
            fetchedAtMs: now,
            source: "kraken+frankfurter"
        )
    }

    private static func fetchKrakenLastTrade(session: URLSession, pair: String) async throws -> Decimal {
        let url = URL(string: "https://api.kraken.com/0/public/Ticker?pair=\(pair)")!
        let (data, response) = try await session.data(from: url)
        try validate(response)
        let json = String(decoding: data, as: UTF8.self)
        guard let last = FiatEstimate.parseKrakenLastTrade(json: json) else {
            throw URLError(.cannotParseResponse)
        }
        return last
    }

    private static func fetchFrankfurter(session: URLSession, symbol: String) async throws -> Decimal {
        let url = URL(string: "https://api.frankfurter.dev/v1/latest?base=USD&symbols=\(symbol)")!
        let (data, response) = try await session.data(from: url)
        try validate(response)
        let json = String(decoding: data, as: UTF8.self)
        guard let fx = FiatEstimate.parseFrankfurterRate(json: json, symbol: symbol) else {
            throw URLError(.cannotParseResponse)
        }
        return fx
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 8
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    private func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
