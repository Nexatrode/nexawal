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
}
