//
//  WalletView.swift
//  nexawal
//
//  Main wallet view showing balance and address
//

import MoneroWalletCoreFFI
import NexaWalLogic
import SwiftUI
import UIKit

struct WalletView: View {
    @ObservedObject var viewModel: WalletViewModel
    @ObservedObject private var fiatPrices = FiatPriceService.shared
    @Binding var selectedTab: MainTab

    // Transaction details
    @State private var selectedTransfer: WalletCoreFFIClient.Transfer?
    @State private var showTransferDetails: Bool = false

    @Environment(\.classicUI) private var classicUI
    @Environment(\.classicPalette) private var classicPalette

    private func directionLabel(_ t: WalletCoreFFIClient.Transfer) -> String {
        switch t.direction.lowercased() {
        case "in":
            return L10n.neon("Received", classicUI: classicUI)
        case "out":
            return L10n.neon("Sent", classicUI: classicUI)
        case "self":
            return L10n.neon("Self", classicUI: classicUI)
        default:
            return classicUI ? t.direction.uppercased() : t.direction
        }
    }

    private func transferAccessibilityLabel(_ t: WalletCoreFFIClient.Transfer) -> String {
        let direction = directionLabel(t)
        let amount = viewModel.formatDisplayPiconero(t.amount)
        let status = (t.isPending || t.confirmations == 0)
            ? L10n.t("Pending")
            : L10n.format("%lld conf", Int64(t.confirmations))
        return "\(direction), \(amount), \(status)"
    }

    private func amountColor(_ t: WalletCoreFFIClient.Transfer) -> Color {
        if let p = classicPalette {
            switch t.direction.lowercased() {
            case "in":
                return p.success
            case "out":
                return p.danger
            default:
                return p.primaryText
            }
        }
        switch t.direction.lowercased() {
        case "in":
            return .green
        case "out":
            return .red
        default:
            return .primary
        }
    }

    private var panelBackground: Color {
        classicPalette?.panel ?? Color(.systemGray6)
    }

    private var pageBackground: Color {
        classicPalette?.background ?? Color(.systemBackground)
    }

    private var primaryText: Color {
        classicPalette?.primaryText ?? .primary
    }

    private var secondaryText: Color {
        classicPalette?.secondaryText ?? .secondary
    }

    private func formatTransferTimestamp(_ t: WalletCoreFFIClient.Transfer) -> String? {
        guard let ts = t.timestamp, ts > 0 else { return nil }
        let d = Date(timeIntervalSince1970: TimeInterval(ts))
        let seconds = Int(Date().timeIntervalSince(d))

        // Future timestamps shouldn't happen, but if they do, fall back to absolute formatting.
        if seconds < 0 {
            return formatTransferTimestampAbsolute(t)
        }

        // Very small deltas
        if seconds < 10 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }

        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }

        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }

        let days = hours / 24
        if days < 7 { return "\(days)d ago" }

        return formatTransferTimestampAbsolute(t)
    }

    private func formatTransferTimestampAbsolute(_ t: WalletCoreFFIClient.Transfer) -> String? {
        guard let ts = t.timestamp, ts > 0 else { return nil }
        let d = Date(timeIntervalSince1970: TimeInterval(ts))
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: d)
    }

    private func sortedTransfers(_ items: [WalletCoreFFIClient.Transfer]) -> [WalletCoreFFIClient
        .Transfer]
    {
        items.sorted { a, b in
            // Pending first
            let aPending = a.isPending || a.confirmations == 0
            let bPending = b.isPending || b.confirmations == 0
            if aPending != bPending { return aPending && !bPending }

            // Then by height desc (unknown height treated as 0)
            let ah = a.height ?? 0
            let bh = b.height ?? 0
            if ah != bh { return ah > bh }

            // Then by timestamp desc (unknown treated as 0)
            let at = a.timestamp ?? 0
            let bt = b.timestamp ?? 0
            if at != bt { return at > bt }

            // Finally stable tiebreaker
            return a.txid > b.txid
        }
    }

    private func syncHeadline() -> String {
        let key: String.LocalizationValue
        if let error = viewModel.errorMessage, !error.isEmpty, !viewModel.isRefreshing {
            key = "Node unreachable"
        } else if viewModel.isSynced {
            key = "Wallet synced"
        } else if !viewModel.hasObservedNetworkTipForUI {
            key = "Connecting to node"
        } else if viewModel.lastScannedHeight == viewModel.restoreHeight {
            key = "Scanning blockchain"
        } else {
            key = "Syncing wallet"
        }
        return L10n.neon(key, classicUI: classicUI)
    }

    private func syncDetail() -> String {
        if let error = viewModel.errorMessage, !error.isEmpty, !viewModel.isRefreshing {
            let trimmed = error.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count <= 120 { return trimmed }
            return String(trimmed.prefix(117)) + "…"
        }
        if viewModel.isSynced {
            return L10n.format("Scanned to block %lld", Int64(viewModel.lastScannedHeight))
        }
        if !viewModel.hasObservedNetworkTipForUI {
            return L10n.t("Waiting for network height")
        }
        if viewModel.lastScannedHeight == viewModel.restoreHeight {
            return L10n.format("Fetching initial blocks from %lld", Int64(viewModel.restoreHeight))
        }
        return L10n.format("%lld blocks remaining", Int64(viewModel.remainingBlocks))
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Balance / actions
                    ZStack(alignment: .topLeading) {
                        if classicUI {
                            Image("NexawalMark")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 160, height: 160)
                                .opacity(0.12)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                                .padding(.trailing, 8)
                                .allowsHitTesting(false)
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            Text(classicUI ? "NEXAWAL" : L10n.t("Wallet"))
                                .font(classicUI ? .system(.headline, design: .monospaced).weight(.bold) : .headline)
                                .foregroundColor(classicUI ? primaryText : .secondary)
                                .tracking(classicUI ? 2 : 0)

                            Text(viewModel.formatDisplayPiconero(viewModel.totalBalance))
                                .font(.system(size: 38, weight: .bold, design: .monospaced))
                                .foregroundColor(primaryText)
                            FiatApproxText(
                                piconero: viewModel.totalBalance,
                                rate: fiatPrices.displayRate,
                                font: classicUI ? .system(.subheadline, design: .monospaced) : .subheadline,
                                color: secondaryText
                            )

                            if viewModel.unlockedBalance != viewModel.totalBalance {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L10n.neon("Unlocked", classicUI: classicUI))
                                        .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                                        .foregroundColor(secondaryText)
                                    Text(viewModel.formatDisplayPiconero(viewModel.unlockedBalance))
                                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                                        .foregroundColor(classicPalette?.accent ?? .blue)
                                    FiatApproxText(
                                        piconero: viewModel.unlockedBalance,
                                        rate: fiatPrices.displayRate,
                                        font: classicUI ? .system(.caption, design: .monospaced) : .caption,
                                        color: secondaryText
                                    )
                                }
                            }

                            if viewModel.balanceIsStaleWhileSyncing {
                                Label("Balance updating while sync catches up", systemImage: "clock.arrow.circlepath")
                                    .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                                    .foregroundColor(secondaryText)
                            }

                            HStack(spacing: 12) {
                                Button(action: {
                                    selectedTab = .send
                                }) {
                                    Label(L10n.neon("Send", classicUI: classicUI), systemImage: "paperplane.fill")
                                        .font(classicUI ? .system(.body, design: .monospaced).weight(.semibold) : .body)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(classicUI ? Color.clear : Color.orange.opacity(0.9))
                                        .foregroundColor(classicUI ? (classicPalette?.accent ?? .green) : .white)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: classicUI ? 4 : 12)
                                                .stroke(classicUI ? (classicPalette?.border ?? .green) : Color.clear, lineWidth: classicUI ? 2 : 0)
                                        )
                                        .cornerRadius(classicUI ? 4 : 12)
                                }

                                Button(action: {
                                    selectedTab = .receive
                                }) {
                                    Label(L10n.neon("Receive", classicUI: classicUI), systemImage: "qrcode")
                                        .font(classicUI ? .system(.body, design: .monospaced).weight(.semibold) : .body)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(classicUI ? Color.clear : Color.green.opacity(0.9))
                                        .foregroundColor(classicUI ? (classicPalette?.accent ?? .green) : .white)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: classicUI ? 4 : 12)
                                                .stroke(classicUI ? (classicPalette?.border ?? .green) : Color.clear, lineWidth: classicUI ? 2 : 0)
                                        )
                                        .cornerRadius(classicUI ? 4 : 12)
                                }
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(panelBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: classicUI ? 4 : 16)
                            .stroke(classicUI ? (classicPalette?.border ?? .clear) : Color.clear, lineWidth: 1)
                    )
                    .cornerRadius(classicUI ? 4 : 16)
                    .padding(.horizontal)

                    // Status
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.neon("Status", classicUI: classicUI))
                            .font(classicUI ? .system(.headline, design: .monospaced).weight(.bold) : .headline)
                            .foregroundColor(primaryText)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(
                                        (viewModel.errorMessage?.isEmpty == false && !viewModel.isRefreshing)
                                            ? (classicPalette?.danger ?? .red)
                                            : (viewModel.isSynced ? (classicPalette?.success ?? .green) : (classicPalette?.accent ?? .orange))
                                    )
                                    .frame(width: 10, height: 10)
                                    .accessibilityHidden(true)
                                Text(syncHeadline())
                                    .font(classicUI ? .system(.headline, design: .monospaced) : .headline)
                                    .foregroundColor(primaryText)
                            }

                            Text(syncDetail())
                                .font(classicUI ? .system(.subheadline, design: .monospaced) : .subheadline)
                                .foregroundColor(secondaryText)

                            ProgressView(value: viewModel.syncProgress)
                                .progressViewStyle(LinearProgressViewStyle(tint: classicPalette?.progress ?? .accentColor))
                                .accessibilityValue(L10n.format("Sync progress %lld percent", Int64((viewModel.syncProgress * 100).rounded())))

                            classicStatusRow(label: L10n.neon("Node", classicUI: classicUI), value: MoneroConfig.daemonAddress)
                            classicStatusRow(label: L10n.neon("Scanned", classicUI: classicUI), value: "\(viewModel.lastScannedHeight)")
                            classicStatusRow(label: L10n.neon("Network Height", classicUI: classicUI), value: "\(viewModel.chainHeight)")
                            classicStatusRow(label: L10n.neon("Remaining", classicUI: classicUI), value: L10n.format("%lld blocks", Int64(viewModel.remainingBlocks)))
                            classicStatusRow(
                                label: L10n.neon("Throughput", classicUI: classicUI),
                                value: String(format: "%.1f blk/s", viewModel.scanBlocksPerSecond)
                            )
                        }
                        .accessibilityAddTraits(.updatesFrequently)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(panelBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: classicUI ? 4 : 16)
                            .stroke(classicUI ? (classicPalette?.border ?? .clear) : Color.clear, lineWidth: 1)
                    )
                    .cornerRadius(classicUI ? 4 : 16)
                    .padding(.horizontal)

                    // Recent transactions
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(L10n.neon("Recent Transactions", classicUI: classicUI))
                                .font(classicUI ? .system(.headline, design: .monospaced).weight(.bold) : .headline)
                                .foregroundColor(primaryText)
                            Spacer()
                            if !viewModel.transfers.isEmpty {
                                Text("\(viewModel.transfers.count)")
                                    .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                                    .foregroundColor(secondaryText)
                            }
                        }

                        if viewModel.transfers.isEmpty {
                            Text("No transactions yet.")
                                .font(classicUI ? .system(.subheadline, design: .monospaced) : .subheadline)
                                .foregroundColor(secondaryText)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(sortedTransfers(viewModel.transfers), id: \.txid) { t in
                                    Button {
                                        selectedTransfer = t
                                        showTransferDetails = true
                                    } label: {
                                        HStack(alignment: .top, spacing: 12) {
                                            Image(systemName: t.direction.lowercased() == "in" ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                                                .font(.title3)
                                                .foregroundColor(amountColor(t))
                                                .accessibilityHidden(true)

                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(directionLabel(t))
                                                    .font(classicUI ? .system(.subheadline, design: .monospaced).weight(.semibold) : .subheadline.weight(.semibold))
                                                    .foregroundColor(primaryText)

                                                HStack(spacing: 8) {
                                                    if let ts = formatTransferTimestamp(t) {
                                                        Text(ts)
                                                            .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                                                            .foregroundColor(secondaryText)
                                                            .accessibilityLabel(formatTransferTimestampAbsolute(t) ?? ts)
                                                    }
                                                    Text((t.isPending || t.confirmations == 0) ? L10n.neon("Pending", classicUI: classicUI) : L10n.format("%lld conf", Int64(t.confirmations)))
                                                        .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                                                        .foregroundColor(secondaryText)
                                                }

                                                Text(t.txid)
                                                    .font(.system(.caption2, design: .monospaced))
                                                    .foregroundColor(secondaryText)
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                            }

                                            Spacer()

                                            VStack(alignment: .trailing, spacing: 4) {
                                                Text(viewModel.formatDisplayPiconero(t.amount))
                                                    .font(.system(.subheadline, design: .monospaced))
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(amountColor(t))

                                                if let fee = t.fee {
                                                    Text(L10n.format("Fee %@", viewModel.formatDisplayPiconero(fee)))
                                                        .font(classicUI ? .system(.caption2, design: .monospaced) : .caption2)
                                                        .foregroundColor(secondaryText)
                                                }
                                            }
                                        }
                                        .padding(.vertical, 12)
                                        .accessibilityElement(children: .combine)
                                        .accessibilityLabel(transferAccessibilityLabel(t))
                                        .accessibilityAddTraits(.isButton)
                                    }
                                    .buttonStyle(.plain)

                                    if t.txid != sortedTransfers(viewModel.transfers).last?.txid {
                                        Divider()
                                            .background(classicPalette?.border.opacity(0.4) ?? Color(.separator))
                                    }
                                }
                            }
                            .sheet(
                                isPresented: $showTransferDetails,
                                onDismiss: { selectedTransfer = nil }
                            ) {
                                if let t = selectedTransfer {
                                    NavigationView {
                                        List {
                                                Section(header: Text("Summary")) {
                                                    HStack {
                                                        Text("Type")
                                                        Spacer()
                                                        Text(directionLabel(t))
                                                            .font(
                                                                .system(
                                                                    .caption, design: .monospaced)
                                                            )
                                                            .foregroundColor(.secondary)
                                                    }
                                                    HStack {
                                                        Text("Status")
                                                        Spacer()
                                                        Text((t.isPending || t.confirmations == 0) ? "Pending" : "Confirmed")
                                                            .font(
                                                                .system(
                                                                    .caption, design: .monospaced)
                                                            )
                                                            .foregroundColor(.secondary)
                                                    }
                                                    HStack {
                                                        Text("Amount")
                                                        Spacer()
                                                        Text(viewModel.formatExactPiconero(t.amount))
                                                        .font(
                                                            .system(.caption, design: .monospaced)
                                                        )
                                                        .foregroundColor(amountColor(t))
                                                    }
                                                    if let snap = FiatSnapshotStore.snapshot(for: t.txid),
                                                       let perXmr = FiatEstimate.decimal(from: snap.fiatPerXmr) {
                                                        HStack {
                                                            Spacer()
                                                            Text(FiatEstimate.recordedApproxText(
                                                                piconero: t.amount,
                                                                fiatPerXmr: perXmr,
                                                                currency: snap.currency
                                                            ))
                                                            .font(.system(.caption, design: .monospaced))
                                                            .foregroundColor(.secondary)
                                                        }
                                                    }
                                                    if let fee = t.fee {
                                                        HStack {
                                                            Text("Fee")
                                                            Spacer()
                                                            Text(viewModel.formatExactPiconero(fee))
                                                            .font(
                                                                .system(
                                                                    .caption, design: .monospaced)
                                                            )
                                                            .foregroundColor(.secondary)
                                                        }
                                                        if let snap = FiatSnapshotStore.snapshot(for: t.txid),
                                                           let perXmr = FiatEstimate.decimal(from: snap.fiatPerXmr) {
                                                            HStack {
                                                                Spacer()
                                                                Text(FiatEstimate.recordedApproxText(
                                                                    piconero: fee,
                                                                    fiatPerXmr: perXmr,
                                                                    currency: snap.currency
                                                                ))
                                                                .font(.system(.caption, design: .monospaced))
                                                                .foregroundColor(.secondary)
                                                            }
                                                        }
                                                    }
                                                }

                                                Section(header: Text("Chain")) {
                                                    HStack {
                                                        Text("Height")
                                                        Spacer()
                                                        Text(t.height.map(String.init) ?? "—")
                                                            .font(
                                                                .system(
                                                                    .caption, design: .monospaced)
                                                            )
                                                            .foregroundColor(.secondary)
                                                    }
                                                    HStack {
                                                        Text("Confirmations")
                                                        Spacer()
                                                        Text("\(t.confirmations)")
                                                            .font(
                                                                .system(
                                                                    .caption, design: .monospaced)
                                                            )
                                                            .foregroundColor(.secondary)
                                                    }
                                                    HStack {
                                                        Text("Time")
                                                        Spacer()
                                                        Text(
                                                            formatTransferTimestampAbsolute(t)
                                                                ?? "—"
                                                        )
                                                        .font(
                                                            .system(.caption, design: .monospaced)
                                                        )
                                                        .foregroundColor(.secondary)
                                                    }
                                                }

                                                Section(header: Text("Identifiers")) {
                                                    HStack {
                                                        Text("TXID")
                                                        Spacer()
                                                        Text(t.txid)
                                                            .font(
                                                                .system(
                                                                    .caption2, design: .monospaced)
                                                            )
                                                            .foregroundColor(.secondary)
                                                            .textSelection(.enabled)
                                                    }

                                                    Button {
                                                        UIPasteboard.general.string = t.txid
                                                    } label: {
                                                        HStack {
                                                            Text("Copy TXID")
                                                            Spacer()
                                                            Image(systemName: "doc.on.doc")
                                                                .foregroundColor(.secondary)
                                                        }
                                                    }

                                                    if let explorerURL = URL(string: "https://xmrchain.net/tx/\(t.txid)") {
                                                        Link(destination: explorerURL) {
                                                            HStack {
                                                                Text("Open in Explorer")
                                                                Spacer()
                                                                Image(systemName: "safari")
                                                                    .foregroundColor(.secondary)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                            .navigationTitle("Transaction")
                                            .toolbar {
                                                ToolbarItem(placement: .cancellationAction) {
                                                    Button("Close") { showTransferDetails = false }
                                                }
                                            }
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(panelBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: classicUI ? 4 : 16)
                            .stroke(classicUI ? (classicPalette?.border ?? .clear) : Color.clear, lineWidth: 1)
                    )
                    .cornerRadius(classicUI ? 4 : 16)
                    .padding(.horizontal)

                    HStack(spacing: 12) {
                        Button(action: {
                            Task {
                                await viewModel.refreshWallet()
                            }
                        }) {
                            HStack {
                                if viewModel.isRefreshing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: classicUI ? (classicPalette?.accent ?? .accentColor) : .white))
                                        .accessibilityHidden(true)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .accessibilityHidden(true)
                                }
                                Text(viewModel.isRefreshing
                                     ? L10n.neon("Refreshing...", classicUI: classicUI)
                                     : L10n.neon("Refresh Wallet", classicUI: classicUI))
                                    .font(classicUI ? .system(.body, design: .monospaced).weight(.semibold) : .body)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(classicUI ? Color.clear : Color.blue)
                            .foregroundColor(classicUI ? (classicPalette?.accent ?? .blue) : .white)
                            .overlay(
                                RoundedRectangle(cornerRadius: classicUI ? 4 : 12)
                                    .stroke(classicUI ? (classicPalette?.border ?? .clear) : Color.clear, lineWidth: classicUI ? 2 : 0)
                            )
                            .cornerRadius(classicUI ? 4 : 12)
                        }
                        .disabled(viewModel.isRefreshing)

                        if viewModel.isRefreshing {
                            Button(action: {
                                viewModel.cancelRefresh()
                            }) {
                                HStack {
                                    Image(systemName: "xmark.circle.fill")
                                        .accessibilityHidden(true)
                                    Text(L10n.neon("Cancel", classicUI: classicUI))
                                        .font(classicUI ? .system(.body, design: .monospaced).weight(.semibold) : .body)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(classicUI ? Color.clear : Color.red.opacity(0.9))
                                .foregroundColor(classicUI ? (classicPalette?.danger ?? .red) : .white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: classicUI ? 4 : 12)
                                        .stroke(classicUI ? (classicPalette?.danger ?? .red) : Color.clear, lineWidth: classicUI ? 2 : 0)
                                )
                                .cornerRadius(classicUI ? 4 : 12)
                            }
                        }
                    }
                    .padding(.horizontal)

                    if let error = viewModel.errorMessage {
                        ScrollView {
                            Text(error)
                                .foregroundColor(classicPalette?.danger ?? .red)
                                .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background((classicPalette?.danger ?? .red).opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                        .accessibilityAddTraits(.updatesFrequently)
                    }
                }
                .padding(.vertical)
            }
            .background(pageBackground.ignoresSafeArea())
            .navigationTitle("")
            .refreshable {
                await viewModel.refreshWallet()
            }
            .task {
                await FiatPriceService.shared.refreshIfNeeded(force: false)
            }
        }
    }

    @ViewBuilder
    private func classicStatusRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(classicUI ? .system(.caption, design: .monospaced) : .body)
                .foregroundColor(secondaryText)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: WalletViewModel
    @State private var nodeAddress: String
    @State private var networkPolicy: MoneroConfig.NetworkPolicy
    @State private var i2pRPCAddress: String
    @State private var i2pProxyAddress: String
    @State private var rescanHeightInput: String
    @State private var gapLimitInput: String
    @State private var accountGapInput: String
    @State private var requireBiometrics: Bool
    @State private var fiatEstimatesEnabled: Bool
    @State private var fiatCurrency: String
    @State private var biometricsAvailable: Bool = false
    @State private var biometricsEnrolled: Bool = false
    @State private var showAdvancedRecovery: Bool = false
    @State private var saveConfirmation: String?
    @AppStorage(MoneroConfig.userDefaultsClassicUIKey) private var classicUIEnabled: Bool = false
    @Environment(\.classicUI) private var classicUI
    @Environment(\.classicPalette) private var classicPalette

    init(viewModel: WalletViewModel) {
        self._viewModel = ObservedObject(initialValue: viewModel)
        self._nodeAddress = State(initialValue: MoneroConfig.daemonAddress)
        self._networkPolicy = State(initialValue: MoneroConfig.networkPolicy)
        self._i2pRPCAddress = State(initialValue: MoneroConfig.i2pRPCAddress)
        self._i2pProxyAddress = State(initialValue: MoneroConfig.i2pHTTPProxyAddress ?? "")
        let heightValue = viewModel.restoreHeight
        self._rescanHeightInput = State(initialValue: heightValue == 0 ? "" : String(heightValue))
        self._gapLimitInput = State(initialValue: String(MoneroConfig.gapLimit))
        self._accountGapInput = State(initialValue: String(MoneroConfig.accountGap))
        self._requireBiometrics = State(initialValue: viewModel.biometricsEnabled)
        self._fiatEstimatesEnabled = State(initialValue: MoneroConfig.fiatEstimatesEnabled)
        self._fiatCurrency = State(initialValue: MoneroConfig.fiatCurrency)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: NeonSectionHeader(title: L10n.t("Appearance"))) {
                    NeonToggle(title: L10n.t("Classic UI"), isOn: $classicUIEnabled)
                    Text("Standard non-neon look. Leave off for the neon terminal theme (default).")
                        .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                        .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                }

                Section(header: NeonSectionHeader(title: L10n.t("How to connect"))) {
                    Picker("How to connect", selection: $networkPolicy) {
                        Text("Clearnet only").tag(MoneroConfig.NetworkPolicy.clearnet)
                        Text("I2P only").tag(MoneroConfig.NetworkPolicy.i2p)
                        Text("Both (scan clearnet, broadcast I2P)").tag(MoneroConfig.NetworkPolicy.hybrid)
                    }
                    .tint(classicPalette?.accent ?? .accentColor)
                    .onChange(of: networkPolicy) { _, newValue in
                        applyNetwork(policy: newValue)
                    }
                    Text("Clearnet only uses a clearnet node. I2P only uses an I2P node and proxy. Both scans on clearnet and broadcasts over I2P.")
                        .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                        .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                }

                if networkPolicy != .i2p {
                    Section(header: NeonSectionHeader(title: L10n.t("Clearnet node"))) {
                        TextField("https://rpc.nexatrode.com", text: $nodeAddress)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(classicPalette?.primaryText ?? .primary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit { applyNetwork() }
                        Text("Type the full URL, including http:// or https://.")
                            .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                            .foregroundStyle(classicPalette?.secondaryText ?? .secondary)

                        if classicUI, let palette = classicPalette {
                            Button("Use this node") {
                                applyNetwork()
                            }
                            .buttonStyle(NeonSecondaryButtonStyle(palette: palette))
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                        } else {
                            Button("Use this node") {
                                applyNetwork()
                            }
                        }
                    }
                }

                if networkPolicy != .clearnet {
                    Section(header: NeonSectionHeader(title: L10n.t("I2P"))) {
                        TextField("I2P node (host:port)", text: $i2pRPCAddress)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(classicPalette?.primaryText ?? .primary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit { applyNetwork() }

                        TextField("I2P HTTP proxy (host:port)", text: $i2pProxyAddress)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(classicPalette?.primaryText ?? .primary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit { applyNetwork() }

                        Text("Proxy example: 127.0.0.1:4444. Leave blank if you want — sync will fail until a working I2P node and proxy are set.")
                            .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                            .foregroundStyle(classicPalette?.secondaryText ?? .secondary)

                        if classicUI, let palette = classicPalette {
                            Button("Apply I2P settings") {
                                applyNetwork()
                            }
                            .buttonStyle(NeonSecondaryButtonStyle(palette: palette))
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                        } else {
                            Button("Apply I2P settings") {
                                applyNetwork()
                            }
                        }
                    }
                }

                Section(header: NeonSectionHeader(title: L10n.t("Security"))) {
                    NeonToggle(
                        title: L10n.t("Require Face ID / Touch ID"),
                        isOn: $requireBiometrics,
                        disabled: !biometricsAvailable || !biometricsEnrolled
                    )
                    .onChange(of: requireBiometrics) { _, newValue in
                        persistBiometrics(newValue)
                    }

                    if !biometricsAvailable {
                        Text("Biometric or device authentication is not available on this device.")
                            .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                            .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                    } else if !biometricsEnrolled {
                        Text("Biometric authentication is available, but no biometric data is enrolled.")
                            .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                            .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                    } else {
                        Text("When enabled, opening the stored wallet and sending funds will require device authentication.")
                            .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                            .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                    }
                }

                Section(header: NeonSectionHeader(title: L10n.t("Recovery"))) {
                    Text("Wrong node? Change how to connect or the node above — you do not need a rescan.\nMissing funds? Rescan from your restore height.\nLast resort: full rescan from block 0.")
                        .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                        .foregroundStyle(classicPalette?.secondaryText ?? .secondary)

                    TextField("Restore height", text: $rescanHeightInput)
                        .keyboardType(.numberPad)
                        .foregroundStyle(classicPalette?.primaryText ?? .primary)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    if classicUI, let palette = classicPalette {
                        Button("Rescan from Height") {
                            initiateRescan()
                        }
                        .buttonStyle(NeonSecondaryButtonStyle(palette: palette))
                        .disabled(parsedRescanHeight() == nil)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                        Button("Full Rescan (from block 0)") {
                            rescanHeightInput = "0"
                            initiateRescan()
                        }
                        .buttonStyle(NeonSecondaryButtonStyle(palette: palette))
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
                    } else {
                        Button("Rescan from Height") {
                            initiateRescan()
                        }
                        .disabled(parsedRescanHeight() == nil)

                        Button("Full Rescan (from block 0)") {
                            rescanHeightInput = "0"
                            initiateRescan()
                        }
                    }
                }

                Section(header: NeonSectionHeader(title: L10n.t("Advanced Recovery"))) {
                    NeonDisclosureGroup(
                        title: L10n.t("Scan additional accounts or subaddresses"),
                        isExpanded: $showAdvancedRecovery
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Only change these values if a wallet import appears incomplete after using the correct restore height.")
                                .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                                .foregroundStyle(classicPalette?.secondaryText ?? .secondary)

                            TextField("Gap limit (1-100000)", text: $gapLimitInput)
                                .keyboardType(.numberPad)
                                .foregroundStyle(classicPalette?.primaryText ?? .primary)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            Text("Controls how many receive subaddresses are scanned for this wallet.")
                                .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                                .foregroundStyle(classicPalette?.secondaryText ?? .secondary)

                            TextField("Account lookahead (1-1000)", text: $accountGapInput)
                                .keyboardType(.numberPad)
                                .foregroundStyle(classicPalette?.primaryText ?? .primary)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            Text("Controls how many Monero accounts are scanned starting at account 0.")
                                .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                                .foregroundStyle(classicPalette?.secondaryText ?? .secondary)

                            Button {
                                persistScanTuning()
                                flashStatus(L10n.t("Saved scan lookahead"))
                            } label: {
                                Text("Save scan lookahead")
                                    .frame(maxWidth: .infinity)
                            }

                            Button {
                                Task {
                                    do {
                                        try await WalletManager.shared.clearScanCache()
                                        flashStatus(L10n.t("Cleared scan cache"))
                                    } catch {
                                        flashStatus(L10n.format("Clear cache failed: %@", error.localizedDescription))
                                    }
                                }
                            } label: {
                                Text("Clear scan cache (this network)")
                                    .frame(maxWidth: .infinity)
                            }
                            .foregroundColor(classicUI ? (classicPalette?.danger ?? .red) : .red)
                        }
                    }
                }

                Section(header: NeonSectionHeader(title: L10n.t("Fiat estimates"))) {
                    NeonToggle(title: L10n.t("Show fiat estimates"), isOn: $fiatEstimatesEnabled)
                        .onChange(of: fiatEstimatesEnabled) { _, newValue in
                            MoneroConfig.setFiatEstimatesEnabled(newValue)
                            fiatCurrency = MoneroConfig.fiatCurrency
                            FiatPriceService.shared.settingsDidChange()
                        }
                    Text("Optional. When on, NexaWal fetches a public XMR price from Kraken (api.kraken.com) and, if needed, fiat FX from Frankfurter (api.frankfurter.dev). Those servers see your IP. Amounts and addresses are not sent. Fiat lookups use clearnet HTTPS and are separate from node / I2P proxy settings. Estimates only — XMR is what you send and hold.")
                        .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                        .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                    if fiatEstimatesEnabled {
                        Picker("Currency", selection: $fiatCurrency) {
                            ForEach(FiatEstimate.supportedCurrencies, id: \.self) { code in
                                Text("\(code) — \(FiatEstimate.currencyNames[code] ?? code)").tag(code)
                            }
                        }
                        .onChange(of: fiatCurrency) { _, newValue in
                            MoneroConfig.setFiatCurrency(newValue)
                            FiatPriceService.shared.settingsDidChange()
                        }
                    }
                }

                Section(header: NeonSectionHeader(title: L10n.t("About"))) {
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                    Text(L10n.format("NexaWal %@ (%@)", version, build))
                        .foregroundStyle(classicPalette?.primaryText ?? .primary)
                    Text("MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact api.kraken.com and api.frankfurter.dev.")
                        .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                        .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                    Link("Privacy policy", destination: URL(string: "https://github.com/cacaosteve/nexawal/blob/main/docs/PRIVACY.md")!)
                    Link("Source & license (MIT)", destination: URL(string: "https://github.com/cacaosteve/nexawal/blob/main/LICENSE")!)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .neonFormChrome(classicUI: classicUI, palette: classicPalette)
            .tint(classicPalette?.accent ?? .accentColor)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(L10n.neon("Settings", classicUI: classicUI))
                        .font(classicUI ? .system(.headline, design: .monospaced).weight(.bold) : .headline)
                        .foregroundStyle(classicPalette?.primaryText ?? .primary)
                }
            }
            .overlay(alignment: .bottom) {
                if let saveConfirmation {
                    Text(saveConfirmation)
                        .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                        .foregroundStyle(classicPalette?.primaryText ?? .primary)
                        .padding(10)
                        .background((classicPalette?.panel ?? Color(.secondarySystemBackground)).opacity(0.95))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }
            }
            .task {
                let availability = await viewModel.biometricAvailability()
                biometricsAvailable = availability.available
                biometricsEnrolled = availability.enrolled
            }
        }
    }

    private func applyNetwork(policy: MoneroConfig.NetworkPolicy? = nil) {
        let policy = policy ?? networkPolicy
        if networkPolicy != policy {
            networkPolicy = policy
        }
        let i2pNode = i2pRPCAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let proxy = i2pProxyAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        MoneroConfig.setNetworkPolicy(policy)
        MoneroConfig.setI2PRPCAddress(i2pNode)
        MoneroConfig.setI2PHTTPProxyAddress(proxy.isEmpty ? nil : proxy)
        MoneroConfig.setUseI2P(policy != .clearnet)

        if policy != .i2p {
            var trimmed = nodeAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                trimmed = MoneroConfig.defaultAddress
                nodeAddress = trimmed
            }
            guard let explicit = NetworkRouting.explicitNodeURL(trimmed) else {
                flashStatus(L10n.t("Start the node URL with http:// or https://"))
                return
            }
            nodeAddress = explicit
            MoneroConfig.setDaemonAddress(explicit)
        }

        persistScanTuning()
        FiatPriceService.shared.settingsDidChange()

        let status: String
        switch policy {
        case .clearnet:
            status = viewModel.isWalletOpen ? L10n.format("Connecting to %@", MoneroConfig.daemonAddress) : L10n.t("Saved clearnet")
        case .i2p:
            status = viewModel.isWalletOpen ? L10n.t("Connecting over I2P") : L10n.t("Saved I2P")
        case .hybrid:
            status = viewModel.isWalletOpen ? L10n.t("Connecting (clearnet scan, I2P broadcast)") : L10n.t("Saved both")
        }

        Task {
            await viewModel.applyNetworkAndReconnect()
            if let err = viewModel.errorMessage, !err.isEmpty, viewModel.isWalletOpen {
                flashStatus(err)
            } else {
                flashStatus(status)
            }
        }
    }

    private func persistBiometrics(_ enabled: Bool) {
        guard enabled != viewModel.biometricsEnabled else { return }
        Task {
            await viewModel.updateBiometricProtection(enabled: enabled)
            if viewModel.biometricsEnabled != enabled {
                requireBiometrics = viewModel.biometricsEnabled
                flashStatus(viewModel.errorMessage ?? L10n.t("Could not update Face ID setting"))
            }
        }
    }

    private func persistScanTuning() {
        if let gap = parsedGapLimit() {
            MoneroConfig.setGapLimit(gap)
            Task {
                if let id = await WalletManager.shared.getCurrentWalletId() {
                    try? WalletCoreFFIClient.setGapLimit(walletId: id, gapLimit: gap)
                }
            }
        }
        if let acc = Int(accountGapInput.trimmingCharacters(in: .whitespacesAndNewlines)) {
            MoneroConfig.setAccountGap(max(1, min(acc, 1000)))
        }
    }

    private func flashStatus(_ message: String) {
        withAnimation {
            saveConfirmation = message
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run {
                withAnimation {
                    if saveConfirmation == message {
                        saveConfirmation = nil
                    }
                }
            }
        }
    }

    private func parsedGapLimit() -> UInt32? {
        let trimmed = gapLimitInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let v = UInt32(trimmed) else { return nil }
        let clamped = min(max(v, 1), 100_000)
        return clamped
    }

    private func parsedRescanHeight() -> UInt64? {
        let trimmed = rescanHeightInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = UInt64(trimmed) else {
            return nil
        }
        return value
    }

    private func initiateRescan() {
        guard let height = parsedRescanHeight() else { return }
        persistScanTuning()
        Task {
            await viewModel.rescan(from: height)
            if let err = viewModel.errorMessage, !err.isEmpty {
                flashStatus(err)
            } else {
                flashStatus(L10n.format("Rescanning from %lld", Int64(height)))
            }
        }
    }
}
