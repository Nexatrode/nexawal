import Foundation
import Combine
import MoneroWalletCoreFFI
import NexaWalLogic

@MainActor
final class TransactionsModel: ObservableObject {
    @Published private(set) var cache = HistoryPageCache<WalletCoreFFIClient.Transfer>()
    @Published private(set) var count = 0
    @Published private(set) var total = 0
    @Published private(set) var revision: String?
    @Published var error: String?
    @Published var changed = false
    @Published private(set) var loading = false
    @Published private(set) var scrollTarget: Int?
    var visibleIndices = Set<Int>()
    private var generation = UUID()
    private var inFlight = Set<Int>()
    private var failed = Set<Int>()
    private var query = WalletCoreFFIClient.HistoryQuery()
    private var walletId = ""
    typealias Fetch = @Sendable (String, WalletCoreFFIClient.HistoryQuery) async throws -> WalletCoreFFIClient.HistoryPage
    private let fetch: Fetch
    private let onRows: ([WalletCoreFFIClient.Transfer]) -> Void

    init(fetch: @escaping Fetch = { id, request in
        try await Task.detached(priority: .userInitiated) {
            try WalletCoreFFIClient.queryTransfers(walletId: id, query: request)
        }.value
    }, onRows: @escaping ([WalletCoreFFIClient.Transfer]) -> Void = { _ in }) {
        self.fetch = fetch; self.onRows = onRows
    }

    func reset(walletId: String, query: WalletCoreFFIClient.HistoryQuery, anchor: String? = nil) async {
        generation = UUID(); inFlight.removeAll(); failed.removeAll()
        self.walletId = walletId; self.query = query; self.query.anchorTxid = anchor
        scrollTarget = nil; visibleIndices.removeAll()
        cache.clear(); count = 0; total = 0; revision = nil; changed = false; error = nil
        await load(index: 0)
    }
    func cancel() { generation = UUID(); inFlight.removeAll(); loading = false }
    func load(index: Int, onlyIfVisible: Bool = false) async {
        let offset = max(0, index / 50 * 50)
        if onlyIfVisible && !visibleIndices.contains(where: { $0 / 50 * 50 == offset }) { return }
        if cache.row(at: index) != nil { cache.touch(index: index); return }
        guard !inFlight.contains(offset), !failed.contains(offset), !changed else { return }
        if offset > 0 && revision == nil { return }
        let token = generation, id = walletId
        var request = query; request.offset = offset; request.revision = revision
        inFlight.insert(offset); loading = true
        defer { if token == generation { inFlight.remove(offset); loading = !inFlight.isEmpty } }
        do {
            let page = try await fetch(id, request)
            guard !Task.isCancelled, token == generation else { return }
            if onlyIfVisible && !visibleIndices.contains(where: { $0 / 50 * 50 == offset }) { return }
            guard revision == nil || revision == page.revision else { changed = true; return }
            revision = page.revision; count = page.matchingCount; total = page.totalCount
            if request.anchorTxid != nil { scrollTarget = page.anchorOffset ?? 0; query.anchorTxid = nil }
            cache.insert(page.transfers, offset: page.offset, protecting: visibleIndices)
            onRows(page.transfers)
        } catch {
            guard !Task.isCancelled, token == generation else { return }
            if onlyIfVisible && !visibleIndices.contains(where: { $0 / 50 * 50 == offset }) { return }
            failed.insert(offset)
            if error.localizedDescription.contains("stale_history_cursor") { changed = true }
            else { self.error = "Could not load this part of history. You can retry." }
        }
    }
    func reload() async {
        let anchor = visibleIndices.sorted().compactMap { cache.row(at: $0)?.txid }.first
        await reset(walletId: walletId, query: query, anchor: anchor)
    }
    func retry() async {
        let offsets = failed.sorted(); failed.removeAll(); error = nil
        for offset in offsets { await load(index: offset) }
    }

    func exportCSV(walletId: String, query: WalletCoreFFIClient.HistoryQuery) async throws -> URL {
        guard walletId == self.walletId else { throw CancellationError() }
        let token = generation
        var request = query
        request.limit = 200
        request.offset = 0
        request.revision = nil
        request.anchorTxid = nil

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexawal-history-\(UUID().uuidString).csv")
        guard FileManager.default.createFile(atPath: url.path, contents: Data(TransferHistoryCSV.header.utf8)) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            var expectedRevision: String?
            var writtenCount = 0
            while true {
                guard token == generation, walletId == self.walletId, !changed else { throw CancellationError() }
                let page = try await fetch(walletId, request)
                guard token == generation, walletId == self.walletId, !changed else { throw CancellationError() }
                if let expectedRevision, expectedRevision != page.revision {
                    throw NSError(domain: "NexaWalHistory", code: 1, userInfo: [NSLocalizedDescriptionKey: "History changed during export. Reload and try again."])
                }
                expectedRevision = page.revision
                try handle.write(contentsOf: Data(TransferHistoryCSV.rows(page.transfers).utf8))
                writtenCount += page.transfers.count
                guard let nextOffset = page.nextOffset else { break }
                request.offset = nextOffset
                request.revision = page.revision
            }
            guard writtenCount > 0 else {
                throw NSError(domain: "NexaWalHistory", code: 2, userInfo: [NSLocalizedDescriptionKey: "No matching transactions to export."])
            }
            try handle.synchronize()
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }
}

enum TransferHistoryCSV {
    static let header = "direction,amount_xmr,amount_piconero,fee_xmr,fee_piconero,block,timestamp_utc,confirmations,status,txid\n"

    nonisolated static func rows(_ rows: [WalletCoreFFIClient.Transfer]) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return rows.map { row in
            let feeXmr = row.fee.map { formatXMR($0) } ?? ""
            let feePiconero = row.fee.map(String.init) ?? ""
            let height = row.height.map(String.init) ?? ""
            let timestamp = row.timestamp.map { formatter.string(from: Date(timeIntervalSince1970: TimeInterval($0))) } ?? ""
            let status = row.isPending || row.confirmations == 0 ? "pending" : "confirmed"
            return [row.direction, formatXMR(row.amount), String(row.amount), feeXmr, feePiconero,
                    height, timestamp, String(row.confirmations), status, row.txid]
                .map(escape)
                .joined(separator: ",") + "\n"
        }.joined()
    }

    private nonisolated static func formatXMR(_ piconero: UInt64) -> String {
        "\(piconero / 1_000_000_000_000).\(String(format: "%012llu", piconero % 1_000_000_000_000))"
    }

    private nonisolated static func escape(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
