import Foundation
import SwiftUI
import UIKit
import NexaWalLogic

enum ExplorerPrivacy {
    static let setting = "explorer_details_enabled"
    static let help: String.LocalizationValue = "Optional. Each lookup shares your IP address and this transaction ID with explorer.nexawal.com over clearnet HTTPS, even in I2P mode. No background requests. Wallet data is unchanged."
}

/// Deliberately owns no timer, persistent cache, wallet client, or signing material.
struct ExplorerDetailsView: View {
    let txid: String
    let walletSession: UUID
    @ObservedObject var viewModel: WalletViewModel
    @AppStorage(ExplorerPrivacy.setting) private var enabled = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.classicPalette) private var palette
    @Environment(\.classicUI) private var classicUI
    @StateObject private var lookup = ExplorerLookup()

    private var context: ExplorerLookup.Context {
        .init(enabled: enabled, active: scenePhase == .active,
              walletOpen: viewModel.isWalletOpen && walletSession == viewModel.historySession,
              mainnet: viewModel.explorerMainnet, walletSession: viewModel.historySession)
    }

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
            } else if let data = lookup.observation {
                Section {
                    LabeledContent("Status", value: data.status == "pending" ? L10n.t("Pending") : L10n.t("Confirmed"))
                    LabeledContent("Confirmations", value: String(data.confirmations))
                    LabeledContent("Fee", value: data.fee_piconero.flatMap(UInt64.init).map { viewModel.formatExactPiconero($0) } ?? L10n.t("Not available"))
                    if let height = data.block_height { LabeledContent("Height", value: String(height)) }
                    if let hash = data.block_hash { Text(hash).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                    if let time = data.block_timestamp { LabeledContent("Time", value: Date(timeIntervalSince1970: Double(time)).formatted()) }
                    LabeledContent("Observed at", value: Date(timeIntervalSince1970: Double(data.observed_at)).formatted())
                    if !data.node_ready { Text("Node data may be stale or incomplete.").foregroundStyle(palette?.accent ?? .orange) }
                    if data.double_spend_seen == true {
                        Text("The node reports a conflicting spend. Do not treat this as a confirmed payment.").foregroundStyle(palette?.danger ?? .red)
                    }
                }
            }
            if enabled && viewModel.explorerMainnet {
                Section {
                    DisclosureGroup(isExpanded: Binding(get: { lookup.advancedExpanded }, set: { expanded in
                        if expanded { lookup.loadPage(0) } else { lookup.collapseAdvanced() }
                    })) {
                        if let details = lookup.observation?.details, !lookup.loading {
                            advanced(details)
                        }
                    } label: { Text("Advanced details") }
                }
            }
            if lookup.loading { ProgressView() }
            if let failure = lookup.failure {
                Text(failure == .missing
                     ? L10n.t("Not found on this node. This does not prove a payment is missing.")
                     : L10n.t("Explorer unavailable. Your wallet is unaffected. Try again."))
                    .foregroundStyle(palette?.secondaryText ?? .secondary)
            }
            if enabled && viewModel.explorerMainnet {
                Button("Refresh") { lookup.update(context); lookup.refresh() }.disabled(lookup.loading)
            }
            Section {
                Text(txid).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                let explorerURL = "https://explorer.nexawal.com/tx/\(txid)"
                Text(L10n.neon("Copy Explorer Link", classicUI: classicUI))
                    .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                    .foregroundStyle(palette?.secondaryText ?? .secondary)
                Button {
                    UIPasteboard.general.string = explorerURL
                    AppHaptics.light()
                } label: {
                    Text(verbatim: explorerURL)
                        .font(classicUI ? .system(.caption, design: .monospaced) : .caption.monospaced())
                        .underline()
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .tint(palette?.accent ?? .accentColor)
                .foregroundColor(palette?.accent ?? .accentColor)
                .accessibilityLabel(L10n.t("Copy Explorer Link"))
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
        .navigationBarBackButtonHidden(classicUI)
        .navigationTitle(L10n.neon("Explorer details", classicUI: classicUI))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(palette?.background ?? Color(.systemBackground), for: .navigationBar)
        .toolbarColorScheme(classicUI ? .dark : nil, for: .navigationBar)
        .toolbar {
            if classicUI {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    }
                    .buttonStyle(.plain)
                    .tint(palette?.accent ?? .green)
                    .accessibilityLabel(L10n.t("Transaction"))
                }
            }
        }
        .onAppear { lookup.open(txid: txid, context: context) }
        .onChange(of: context) { _, value in lookup.update(value) }
        .onChange(of: txid) { _, _ in lookup.close() }
        .onDisappear { lookup.close() }
    }

    @ViewBuilder private func advanced(_ d: ExplorerAdvanced) -> some View {
        LabeledContent("Type", value: d.coinbase ? localized("Miner transaction") : localized("Transfer"))
        LabeledContent("Version", value: String(d.version))
        LabeledContent("Serialized size", value: d.serialized_size_bytes.map { "\($0) B" } ?? L10n.t("Not available"))
        LabeledContent("Downloaded size", value: "\(d.downloaded_size_bytes) B")
        LabeledContent("Weight", value: d.weight.map { "\($0) B" } ?? L10n.t("Not available"))
        LabeledContent("Additional unlock condition", value: d.unlock_kind == "none" ? "—" : "\(localized(d.unlock_kind == "height" ? "Height" : "Time")): \(d.unlock_value)")
        LabeledContent("Inputs", value: String(d.input_count))
        LabeledContent("Outputs", value: String(d.output_count))
        if let time = d.received_timestamp { LabeledContent("Observed by node", value: Date(timeIntervalSince1970: Double(time)).formatted()) }
        if d.coinbase { Text("Miner transaction") }
        Text("Ring members are possible inputs, not proof of which output was spent.").font(.caption)
        ForEach(d.inputs, id: \.index) { row in
            DisclosureGroup("\(localized("Inputs")) #\(row.index)") {
                technical("Key image", row.key_image)
                LabeledContent("Ring size", value: String(row.ring_size))
                technical("Absolute output indices", row.absolute_indices.joined(separator: ", "))
                if row.indices_truncated { Text("Preview truncated.") }
            }
        }
        ForEach(d.outputs, id: \.index) { row in
            DisclosureGroup("\(localized("Outputs")) #\(row.index)") {
                technical("One-time output key", row.key)
                LabeledContent("Amount", value: row.public_amount_piconero.flatMap(UInt64.init).map { viewModel.formatExactPiconero($0) } ?? localized("Hidden (RingCT)"))
                LabeledContent("View tag", value: row.view_tag.map { String(format: "%02x", $0) } ?? "—")
                LabeledContent("Global output index", value: row.global_index ?? "—")
            }
        }
        Text("\(localized("Page")) \(d.page + 1)/\(d.page_count)")
        HStack {
            Button { lookup.loadPage(d.page - 1) } label: { Text("Previous") }.disabled(d.page == 0)
            Spacer()
            Button { lookup.loadPage(d.page + 1) } label: { Text("Next") }.disabled(d.page + 1 >= d.page_count)
        }
        DisclosureGroup { Text(d.extra_hex.isEmpty ? "—" : d.extra_hex).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            if d.extra_truncated { Text("Preview truncated.") }
        } label: { Text("Transaction extra (hex)") }
    }

    private func localized(_ key: String) -> String { NSLocalizedString(key, comment: "") }
    private func technical(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading) { Text(label); Text(value).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
    }
}
