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
    private var foregroundActive = false

    private init() {
        republishFromCache()
    }

    func onForeground() {
        foregroundActive = true
        republishFromCache()
        Task { await refreshIfNeeded(force: false) }
        startLoop()
    }

    func onBackground() {
        foregroundActive = false
        inFlight?.cancel()
        stopLoop()
    }

    func settingsDidChange() {
        republishFromCache()
        if !canFetch {
            inFlight?.cancel()
            publish(nil)
            stopLoop()
            return
        }
        _ = MoneroConfig.ensureFiatEstimatesEnabledAtMs()
        Task { await refreshIfNeeded(force: true) }
        startLoop()
    }

    var canFetch: Bool {
        MoneroConfig.fiatEstimatesEnabled && MoneroConfig.routingPolicy != .i2p
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
              cached.source == "nexatrode",
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
        guard canFetch && foregroundActive else { return }
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
        guard foregroundActive else { return }
        guard canFetch else {
            publish(nil)
            return
        }
        if shouldSkipFetch(force: force) { return }

        if let existing = inFlight {
            await existing.value
            guard canFetch && foregroundActive else {
                publish(nil)
                return
            }
            if shouldSkipFetch(force: force) { return }
        }

        if let existing = inFlight {
            await existing.value
            if shouldSkipFetch(force: force) { return }
        }

        guard canFetch && foregroundActive else {
            publish(nil)
            return
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
            if canFetch && foregroundActive && MoneroConfig.fiatCurrency == currency {
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
        guard FiatEstimate.isSupported(currency) else { throw URLError(.unsupportedURL) }
        let url = URL(string: "https://rates.nexatrode.com/v1/rates/XMR/\(currency)")!
        let (data, response) = try await session.data(from: url)
        try validate(response)
        guard data.count <= 16_384,
              let quote = try? JSONDecoder().decode(NexatrodeRateResponse.self, from: data),
              quote.base == "XMR", quote.quote == currency,
              let value = FiatEstimate.decimal(from: quote.fiatPerXmr), value > 0
        else {
            throw URLError(.cannotParseResponse)
        }
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        guard quote.checkedAtMs > 0, quote.checkedAtMs <= now,
              quote.expiresAtMs > now,
              quote.expiresAtMs - quote.checkedAtMs <= FiatEstimate.maxAgeMs,
              FiatEstimate.isFresh(fetchedAtMs: quote.checkedAtMs, nowMs: now)
        else {
            throw URLError(.cannotParseResponse)
        }
        return FiatRate(currency: currency, fiatPerXmr: value, fetchedAtMs: quote.checkedAtMs, source: "nexatrode")
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

private struct NexatrodeRateResponse: Decodable {
    let base: String
    let quote: String
    let fiatPerXmr: String
    let checkedAtMs: Int64
    let expiresAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case base, quote
        case fiatPerXmr = "fiat_per_xmr"
        case checkedAtMs = "checked_at_ms"
        case expiresAtMs = "expires_at_ms"
    }
}
