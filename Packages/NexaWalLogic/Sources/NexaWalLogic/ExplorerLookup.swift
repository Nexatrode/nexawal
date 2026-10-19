import Foundation
import Combine

public enum ExplorerLookupFailure: Error, Equatable, Sendable {
    case missing, unavailable
}

/// View-scoped consent and lifetime owner. A context change invalidates work but
/// never authorizes another request; only opening the view or Refresh does that.
@MainActor
public final class ExplorerLookup: ObservableObject {
    public struct Context: Equatable, Sendable {
        public var enabled: Bool
        public var active: Bool
        public var walletOpen: Bool
        public var mainnet: Bool
        public var walletSession: UUID

        public init(enabled: Bool, active: Bool, walletOpen: Bool, mainnet: Bool, walletSession: UUID) {
            self.enabled = enabled; self.active = active; self.walletOpen = walletOpen
            self.mainnet = mainnet; self.walletSession = walletSession
        }
    }

    @Published public private(set) var observation: ExplorerObservation?
    @Published public private(set) var failure: ExplorerLookupFailure?
    @Published public private(set) var loading = false
    @Published public private(set) var advancedExpanded = false
    private var context: Context?
    private var boundSession: UUID?
    private var txid = ""
    private var visible = false
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private let fetch: @Sendable (String, UInt64?) async throws -> ExplorerObservation

    public init(fetchPage: @escaping @Sendable (String, UInt64?) async throws -> ExplorerObservation = { try await ExplorerClient.fetch($0, page: $1) }) {
        self.fetch = fetchPage
    }

    public convenience init(fetch: @escaping @Sendable (String) async throws -> ExplorerObservation) {
        self.init(fetchPage: { id, _ in try await fetch(id) })
    }

    deinit { task?.cancel() }

    public func open(txid: String, context: Context) {
        // SwiftUI may deliver appear more than once for the same mounted view.
        guard !visible else { update(context); return }
        self.txid = txid; self.context = context; boundSession = context.walletSession
        visible = true
        refresh()
    }

    public func update(_ context: Context) {
        guard self.context != context else { return }
        invalidate()
        self.context = context
    }

    public func close() {
        visible = false
        invalidate()
    }

    private var permitted: Bool {
        guard let context else { return false }
        return visible && context.enabled && context.active && context.walletOpen
            && context.mainnet && context.walletSession == boundSession
            && ExplorerObservation.validID(txid)
    }

    private func invalidate(clearData: Bool = true) {
        generation = UUID()
        task?.cancel(); task = nil
        if clearData { observation = nil; advancedExpanded = false }
        failure = nil; loading = false
    }

    public func refresh() {
        request(page: advancedExpanded ? 0 : nil, keepObservation: false)
    }

    public func loadPage(_ page: UInt64) {
        guard page < 410, permitted, !loading else { return }
        advancedExpanded = true
        request(page: page)
    }

    public func collapseAdvanced() {
        advancedExpanded = false
        invalidate(clearData: false)
    }

    private func request(page: UInt64?, keepObservation: Bool = true) {
        guard permitted, !loading else { return }
        invalidate(clearData: !keepObservation)
        advancedExpanded = page != nil
        loading = true
        let ticket = generation
        let id = txid
        task = Task { [weak self, fetch] in
            let result: Result<ExplorerObservation, ExplorerLookupFailure>
            do {
                try Task.checkCancellation()
                result = .success(try await fetch(id, page))
            } catch {
                result = .failure(error as? ExplorerLookupFailure ?? .unavailable)
            }
            // Even a transport that ignores cancellation cannot publish into a
            // reopened view, a new wallet session, or a newer Refresh request.
            guard !Task.isCancelled, let self, self.generation == ticket, self.permitted else { return }
            self.loading = false
            self.task = nil
            switch result {
            case .success(let value): self.observation = value
            case .failure(let error): self.failure = error
            }
        }
    }
}

private final class ExplorerRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public enum ExplorerClient {
    public static func fetch(_ txid: String, page: UInt64? = nil) async throws -> ExplorerObservation {
        guard ExplorerObservation.validID(txid), page == nil || page! < 410 else { throw ExplorerLookupFailure.unavailable }
        let limit = page == nil ? 16_384 : 65_536
        try Task.checkCancellation()
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 12
        config.waitsForConnectivity = false
        config.connectionProxyDictionary = [:]
        let session = URLSession(configuration: config, delegate: ExplorerRedirectBlocker(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let suffix = page.map { "/details/\($0)" } ?? ""
        var request = URLRequest(url: URL(string: "https://explorer.nexawal.com/api/v1/transactions/\(txid)\(suffix)")!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse,
              [200, 404].contains(http.statusCode), response.mimeType == "application/json",
              response.expectedContentLength <= Int64(limit) else { throw ExplorerLookupFailure.unavailable }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else { throw ExplorerLookupFailure.unavailable }
            data.append(byte)
        }
        try Task.checkCancellation()
        if http.statusCode == 404 {
            struct Missing: Decodable { struct Detail: Decodable { let code: String }; let api_version: Int; let error: Detail }
            let missing = try JSONDecoder().decode(Missing.self, from: data)
            guard missing.api_version == 1 && missing.error.code == "not_found" else { throw ExplorerLookupFailure.unavailable }
            throw page == nil ? ExplorerLookupFailure.missing : ExplorerLookupFailure.unavailable
        }
        return try ExplorerObservation.parse(data, txid: txid, now: UInt64(Date().timeIntervalSince1970), page: page)
    }
}
