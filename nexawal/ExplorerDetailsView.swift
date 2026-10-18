import Foundation
import SwiftUI
import UIKit
import NexaWalLogic

enum ExplorerPrivacy {
    static let setting = "explorer_details_enabled"
    static let help: String.LocalizationValue = "Optional. Each lookup shares your IP address and this transaction ID with explorer.nexawal.com over clearnet HTTPS, even in I2P mode. No background requests. Wallet data is unchanged."
}

private final class ExplorerRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Deliberately owns no timer, persistent cache, wallet client, or signing material.
struct ExplorerDetailsView: View {
    let txid: String
    let walletSession: UUID
    @ObservedObject var viewModel: WalletViewModel
    @AppStorage(ExplorerPrivacy.setting) private var enabled = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.classicPalette) private var palette
    @Environment(\.classicUI) private var classicUI
    @State private var refreshID = UUID()
    @State private var observation: ExplorerObservation?
    @State private var message: String?
    @State private var loading = false
    @State private var visible = false
    @State private var requested = false

    var body: some View {
        List {
            Group {
            Section {
                Text("Public explorer data only; your wallet verifies payments.")
                Text(L10n.t(ExplorerPrivacy.help)).font(.caption)
            }
            if !enabled {
                Text("Enable Explorer details in Settings to use this feature.")
            } else if !viewModel.explorerMainnet {
                Text("Public explorer supports mainnet only.")
            } else if let data = observation {
                Section {
                    LabeledContent("Status", value: data.status == "pending" ? L10n.t("Pending") : L10n.t("Confirmed"))
                    LabeledContent("Confirmations", value: String(data.confirmations))
                    LabeledContent("Fee", value: data.fee_piconero.flatMap(UInt64.init).map { viewModel.formatExactPiconero($0) } ?? L10n.t("Not available"))
                    if let height = data.block_height { LabeledContent("Height", value: String(height)) }
                    if let hash = data.block_hash { Text(hash).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                    if let time = data.block_timestamp { LabeledContent("Time", value: Date(timeIntervalSince1970: Double(time)).formatted()) }
                    LabeledContent("Observed at", value: Date(timeIntervalSince1970: Double(data.observed_at)).formatted())
                    if !data.node_ready { Text("Node data may be stale or incomplete.").foregroundStyle(palette?.accent ?? .orange) }
                }
            }
            if loading { ProgressView() }
            if let message { Text(message).foregroundStyle(palette?.secondaryText ?? .secondary) }
            if enabled && viewModel.explorerMainnet {
                Button("Refresh") { requested = true; refreshID = UUID() }.disabled(loading)
            }
            Section {
                Text(txid).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Button("Copy Explorer Link") { UIPasteboard.general.string = "https://explorer.nexawal.com/tx/\(txid)" }
            }
            }
            .listRowBackground(palette?.panel ?? Color(.secondarySystemGroupedBackground))
        }
        .listRowBackground(palette?.panel ?? Color(.secondarySystemGroupedBackground))
        .scrollContentBackground(palette == nil ? .visible : .hidden)
        .background(palette?.background ?? Color(.systemGroupedBackground))
        .foregroundStyle(palette?.primaryText ?? .primary)
        .font(classicUI ? .system(.body, design: .monospaced) : .body)
        .tint(palette?.accent ?? .accentColor)
        .navigationTitle(L10n.t("Explorer details"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(palette?.background ?? Color(.systemBackground), for: .navigationBar)
        .task(id: refreshID) { await load() }
        .onAppear { visible = true; requested = true; refreshID = UUID() }
        .onChange(of: enabled) { _, _ in requested = false; clear() }
        .onChange(of: viewModel.historySession) { _, _ in requested = false; clear() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { requested = false; clear() } }
        .onDisappear { visible = false; requested = false; clear() }
    }

    private func clear() {
        observation = nil; message = nil; refreshID = UUID()
    }

    private func load() async {
        observation = nil; message = nil
        guard enabled, visible, requested, scenePhase == .active, viewModel.isWalletOpen,
              walletSession == viewModel.historySession, viewModel.explorerMainnet,
              ExplorerObservation.validID(txid) else { return }
        loading = true
        defer { loading = false }
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 12
        config.waitsForConnectivity = false
        // A separate HTTPS request, not the wallet's configured I2P proxy.
        config.connectionProxyDictionary = [:]
        let session = URLSession(configuration: config, delegate: ExplorerRedirectBlocker(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            var request = URLRequest(url: URL(string: "https://explorer.nexawal.com/api/v1/transactions/\(txid)")!)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard [200, 404].contains(http.statusCode), response.mimeType == "application/json", response.expectedContentLength <= 16_384 else { throw URLError(.badServerResponse) }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 16_384 else { throw URLError(.dataLengthExceedsMaximum) }
                data.append(byte)
            }
            if http.statusCode == 404 {
                struct Missing: Decodable { struct Detail: Decodable { let code: String }; let api_version: Int; let error: Detail }
                let missing = try JSONDecoder().decode(Missing.self, from: data)
                guard missing.api_version == 1 && missing.error.code == "not_found" else { throw URLError(.cannotParseResponse) }
                try Task.checkCancellation()
                guard enabled, visible, requested, scenePhase == .active, walletSession == viewModel.historySession, viewModel.isWalletOpen else { return }
                message = L10n.t("Not found on this node. This does not prove a payment is missing.")
                return
            }
            let value = try ExplorerObservation.parse(data, txid: txid, now: UInt64(Date().timeIntervalSince1970))
            try Task.checkCancellation()
            guard enabled, visible, requested, scenePhase == .active, walletSession == viewModel.historySession, viewModel.isWalletOpen else { return }
            observation = value
        } catch {
            if !Task.isCancelled && enabled && visible && requested && scenePhase == .active && walletSession == viewModel.historySession {
                message = L10n.t("Explorer unavailable. Your wallet is unaffected. Try again.")
            }
        }
    }
}
