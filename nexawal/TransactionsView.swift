import SwiftUI
import Combine
import MoneroWalletCoreFFI
import NexaWalLogic

struct TransactionsView: View {
    @ObservedObject var viewModel: WalletViewModel
    var initialFilter = "all"
    @StateObject private var model = TransactionsModel(onRows: { rows in
        FiatPriceService.shared.recordSeenTransfers(rows.map {
            (txid: $0.txid, timestampSeconds: $0.timestamp.flatMap(Int64.init(exactly:)))
        })
    })
    @State private var search = ""
    @State private var filter = "all"
    @State private var initialized = false
    @State private var dateFilter = false
    @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var to = Date()
    @State private var selected: WalletCoreFFIClient.Transfer?
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var exportURL: URL?
    @State private var isSharePresented = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.classicUI) private var classicUI
    @Environment(\.classicPalette) private var palette
    private var query: WalletCoreFFIClient.HistoryQuery {
        .init(filter: filter, search: search.trimmingCharacters(in: .whitespacesAndNewlines),
              fromTimestamp: dateFilter ? UInt64(max(0, Calendar.current.startOfDay(for: from).timeIntervalSince1970)) : nil,
              toTimestamp: dateFilter ? UInt64(max(0, (Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: to)) ?? to).timeIntervalSince1970 - 1)) : nil)
    }
    var body: some View {
        ScrollViewReader { proxy in
        List {
            Section {
                if classicUI, let palette {
                    NeonTransactionFilter(selection: $filter, palette: palette)
                } else {
                    Picker("Filter", selection: $filter) {
                        Text("All").tag("all"); Text("Received").tag("received")
                        Text("Sent").tag("sent"); Text("Pending").tag("pending")
                    }
                }
                if classicUI, let palette {
                    Toggle(L10n.neon("Date range", classicUI: true), isOn: $dateFilter)
                        .toggleStyle(NeonDateRangeToggleStyle(palette: palette))
                } else {
                    Toggle("Date range", isOn: $dateFilter)
                }
                if dateFilter {
                    DatePicker("From", selection: $from, displayedComponents: .date)
                    DatePicker("Through", selection: $to, in: from..., displayedComponents: .date)
                }
                if classicUI, let palette {
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(palette.accent)
                        TextField(L10n.neon("Search transaction ID", classicUI: true), text: $search)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(palette.primaryText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .accessibilityLabel(L10n.t("Search transaction ID"))
                        if !search.isEmpty {
                            Button { search = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(palette.secondaryText)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.t("Clear"))
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(palette.background)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(palette.border.opacity(0.8), lineWidth: 1)
                    }
                }
                Text("\(model.count) matching · \(model.total) total").font(.caption).foregroundStyle(.secondary)
                Button {
                    Task {
                        isExporting = true
                        exportError = nil
                        do {
                            exportURL = try await model.exportCSV(walletId: viewModel.historyWalletId, query: query)
                            isSharePresented = exportURL != nil
                        } catch is CancellationError {
                            // A changed query, wallet, or history session invalidates this export.
                        } catch {
                            exportError = L10n.t("CSV export failed. Try again.")
                        }
                        isExporting = false
                    }
                } label: {
                    if isExporting {
                        Label(L10n.t("Loading transaction…"), systemImage: "arrow.down.doc")
                    } else {
                        Label(L10n.t("Export matching transactions (CSV)"), systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(model.count == 0 || model.loading || model.changed || isExporting)
                if let exportError { Text(exportError).font(.caption).foregroundStyle(.red) }
                if !viewModel.isSynced { Text("History may be incomplete while syncing.").font(.caption).foregroundStyle(.secondary) }
                if model.changed {
                    Button("History changed · Reload transactions") { Task { await model.reload() } }
                }
                if let error = model.error {
                    Text(error).foregroundStyle(.red)
                    Button("Retry loading history") { Task { await model.retry() } }
                }
                if model.loading { ProgressView("Loading transactions…") }
            }
            .listRowBackground(palette?.panel ?? Color(.secondarySystemGroupedBackground))
            if model.count == 0 && !model.loading && model.error == nil {
                Text(model.total > 0 ? L10n.t("No transactions match these filters.") :
                     (viewModel.isSynced ? L10n.t("No transactions yet.") : L10n.t("No transactions found yet. Sync is not complete.")))
                    .foregroundStyle(palette?.secondaryText ?? .primary)
                    .listRowBackground(palette?.panel ?? Color(.secondarySystemGroupedBackground))
            }
            // List virtualizes row views. Only four pages of actual records are retained.
            ForEach(0..<model.count, id: \.self) { index in
                Group {
                    if let row = model.cache.row(at: index) {
                        Button {
                            // The loaded history record already carries the fields displayed
                            // on the detail screen. Avoid delaying presentation on another FFI
                            // query, which made the first tap appear unresponsive.
                            selected = row
                        } label: { WalletTransferRow(transfer: row, viewModel: viewModel) }
                            .buttonStyle(.plain)
                    } else {
                        Text(model.changed ? L10n.t("Reload history to continue.") : L10n.t("Loading transaction…"))
                            .foregroundStyle(.secondary).frame(minHeight: 74)
                    }
                }
                .id(index)
                .onAppear {
                    model.visibleIndices.insert(index)
                    // Page work belongs to the screen, not a recycled List cell. The model
                    // generation rejects it when the screen/query/session is invalidated.
                    Task { await model.load(index: index, onlyIfVisible: true) }
                }
                .onDisappear { model.visibleIndices.remove(index) }
                .listRowBackground(palette?.panel ?? Color(.secondarySystemGroupedBackground))
            }
        }
        .tint(palette?.accent ?? .accentColor)
        .foregroundStyle(palette?.primaryText ?? .primary)
        .scrollContentBackground(palette == nil ? .visible : .hidden)
        .background(palette?.background ?? Color(.systemGroupedBackground))
        .navigationTitle(classicUI ? "" : L10n.t("Transactions"))
        .navigationBarTitleDisplayMode(classicUI ? .inline : .large)
        .navigationBarBackButtonHidden(classicUI)
        .toolbarBackground(palette?.background ?? Color(.systemBackground), for: .navigationBar)
        .toolbarColorScheme(classicUI ? .dark : nil, for: .navigationBar)
        .font(classicUI ? .system(.body, design: .monospaced) : .body)
        .toolbar {
            if classicUI {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    }
                    .buttonStyle(.plain)
                    .tint(palette?.accent ?? .green)
                    .accessibilityLabel(L10n.t("Wallet"))
                }
                ToolbarItem(placement: .principal) {
                    Text(L10n.neon("Transactions", classicUI: true))
                        .font(.system(.headline, design: .monospaced).weight(.bold))
                        .foregroundStyle(palette?.accent ?? .green)
                }
            }
        }
        .modifier(NativeTransactionSearch(enabled: !classicUI, text: $search))
        .onAppear { if !initialized { filter = initialFilter; initialized = true } }
        .onChange(of: model.scrollTarget) { _, target in if let target { proxy.scrollTo(target, anchor: .top) } }
        .task(id: query) {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            await model.reset(walletId: viewModel.historyWalletId, query: query)
        }
        .onChange(of: viewModel.historySession) { _, _ in
            model.cancel(); selected = nil
            Task { await model.reset(walletId: viewModel.historyWalletId, query: query) }
        }
        .onChange(of: viewModel.historyRevision) { _, new in
            if let revision = model.revision, let new, revision != new { model.changed = true }
        }
        .onDisappear { model.cancel() }
        .sheet(item: $selected) { row in
            WalletTransferDetails(transfer: row, viewModel: viewModel)
                .environment(\.classicUI, classicUI)
                .environment(\.classicPalette, palette)
        }
        .sheet(isPresented: $isSharePresented, onDismiss: cleanupExportFile) {
            if let exportURL {
                ActivityView(activityItems: [exportURL], completion: { _, _, _, _ in cleanupExportFile() })
            }
        }
        }
    }

private struct NativeTransactionSearch: ViewModifier {
    let enabled: Bool
    @Binding var text: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $text, prompt: "Search transaction ID")
        } else {
            content
        }
    }
}

private struct NeonDateRangeToggleStyle: ToggleStyle {
    let palette: ClassicPalette

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack {
                configuration.label
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(palette.primaryText)
                Spacer(minLength: 8)
                ZStack {
                    Capsule()
                        .fill(palette.panel)
                        .overlay {
                            Capsule().stroke(
                                configuration.isOn ? palette.accent : palette.secondaryText,
                                lineWidth: 1.5
                            )
                        }
                        .frame(width: 52, height: 30)
                    Circle()
                        .fill(configuration.isOn ? palette.accent : palette.secondaryText)
                        .frame(width: 22, height: 22)
                        .offset(x: configuration.isOn ? 10 : -10)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { configuration.isOn.toggle() }
    }
}

private struct NeonTransactionFilter: View {
    @Binding var selection: String
    let palette: ClassicPalette
    private let options: [(value: String, title: LocalizedStringKey)] = [
        ("all", "All"), ("received", "Received"), ("sent", "Sent"), ("pending", "Pending")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                Button { selection = option.value } label: {
                    Text(option.title)
                        .textCase(.uppercase)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(selection == option.value ? palette.background : palette.primaryText)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(selection == option.value ? palette.accent : palette.panel)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(option.title))
                .accessibilityValue(selection == option.value ? "Selected" : "")
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(palette.border.opacity(0.8), lineWidth: 1)
        }
    }
}

    private func cleanupExportFile() {
        if let exportURL { try? FileManager.default.removeItem(at: exportURL) }
        exportURL = nil
        isSharePresented = false
    }
}

extension WalletCoreFFIClient.Transfer: @retroactive Identifiable { public var id: String { txid } }

struct WalletTransferRow: View {
    let transfer: WalletCoreFFIClient.Transfer
    @ObservedObject var viewModel: WalletViewModel
    @Environment(\.classicUI) private var classicUI
    @Environment(\.classicPalette) private var palette
    private var incoming: Bool { transfer.direction == "in" }
    private var label: String { incoming ? "Received" : transfer.direction == "out" ? "Sent" : "Self" }
    private var color: Color { incoming ? (palette?.success ?? .green) : transfer.direction == "out" ? (palette?.danger ?? .red) : (palette?.accent ?? .primary) }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ViewThatFits(in: .horizontal) {
                HStack { title; Spacer(); amount }
                VStack(alignment: .leading) { title; amount }
            }
            if let timestamp = transfer.timestamp, timestamp > 0 {
                Text(Date(timeIntervalSince1970: Double(timestamp)), format: .dateTime.year().month().day().hour().minute())
                    .font(.caption).foregroundStyle(palette?.secondaryText ?? .secondary)
            }
            Text(transfer.isPending ? L10n.t("Pending") : L10n.format("%lld conf", Int64(HistoryConfirmations.count(height: transfer.height, pending: transfer.isPending, chainHeight: viewModel.chainHeight, cached: transfer.confirmations))))
                .font(.caption).foregroundStyle(palette?.secondaryText ?? .secondary)
            Text(transfer.txid).font(.system(.caption2, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(palette?.secondaryText ?? .secondary)
            if let fee = transfer.fee {
                Text(L10n.format("Fee %@%@", viewModel.formatDisplayPiconero(fee), ""))
                    .font(.caption2).foregroundStyle(palette?.secondaryText ?? .secondary)
                if incoming {
                    Text("Paid by the sender. Not deducted from the amount received.")
                        .font(.caption2).foregroundStyle(palette?.secondaryText ?? .secondary)
                }
            }
        }
        .padding(.vertical, 8).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
    private var title: some View {
        Label(LocalizedStringKey(label), systemImage: incoming ? "arrow.down.left" : "arrow.up.right")
            .font(.system(.subheadline, design: classicUI ? .monospaced : .default).weight(.semibold)).foregroundStyle(color)
    }
    private var amount: some View {
        Text((incoming ? "+ " : transfer.direction == "out" ? "− " : "") + viewModel.formatDisplayPiconero(transfer.amount))
            .font(.system(.subheadline, design: .monospaced).weight(.semibold)).foregroundStyle(color)
    }
}

struct WalletTransferDetails: View {
    let transfer: WalletCoreFFIClient.Transfer
    @ObservedObject var viewModel: WalletViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.classicUI) private var classicUI
    @Environment(\.classicPalette) private var palette

    private func detailField(_ label: String.LocalizationValue, value: String) -> some View {
        LabeledContent {
            Text(value)
                .font(classicUI ? .system(.body, design: .monospaced) : .body)
                .foregroundStyle(palette?.primaryText ?? .secondary)
                .multilineTextAlignment(.trailing)
        } label: {
            Text(L10n.neon(label, classicUI: classicUI))
                .font(classicUI ? .system(.body, design: .monospaced) : .body)
                .foregroundStyle(palette?.secondaryText ?? .primary)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    detailField("Type", value: transfer.direction == "in" ? L10n.t("Received") : transfer.direction == "out" ? L10n.t("Sent") : L10n.t("Self"))
                    detailField("Status", value: transfer.isPending ? L10n.t("Pending") : L10n.t("Confirmed"))
                    detailField("Amount", value: viewModel.formatExactPiconero(transfer.amount))
                    if transfer.direction == "out" {
                        Text("Amount is the total wallet debit, including the network fee.")
                            .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                            .foregroundStyle(palette?.secondaryText ?? .secondary)
                    }
                    if let fee = transfer.fee {
                        detailField("Fee", value: viewModel.formatExactPiconero(fee))
                        if transfer.direction == "in" {
                            Text("Paid by the sender. Not deducted from the amount received.")
                                .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                                .foregroundStyle(palette?.secondaryText ?? .secondary)
                        }
                    }
                    detailField("Confirmations", value: "\(HistoryConfirmations.count(height: transfer.height, pending: transfer.isPending, chainHeight: viewModel.chainHeight, cached: transfer.confirmations))")
                    if let height = transfer.height { detailField("Height", value: "\(height)") }
                    if let timestamp = transfer.timestamp, timestamp > 0 {
                        detailField("Time", value: Date(timeIntervalSince1970: Double(timestamp)).formatted(date: .abbreviated, time: .standard))
                    }
                    if let snap = FiatSnapshotStore.snapshot(for: transfer.txid), let price = FiatEstimate.decimal(from: snap.fiatPerXmr) {
                        Text(FiatEstimate.recordedApproxText(piconero: transfer.amount, fiatPerXmr: price, currency: snap.currency))
                            .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                            .foregroundStyle(palette?.secondaryText ?? .secondary)
                    }
                } header: {
                    Text(L10n.neon("Summary", classicUI: classicUI))
                        .font(classicUI ? .system(.subheadline, design: .monospaced).weight(.bold) : .subheadline)
                        .foregroundStyle(palette?.accent ?? .secondary)
                }
                Section {
                    Text(transfer.txid)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(palette?.secondaryText ?? .primary)
                        .textSelection(.enabled)
                    Button("Copy TXID") {
                        UIPasteboard.general.string = transfer.txid
                        AppHaptics.light()
                    }
                    NavigationLink {
                        ExplorerDetailsView(txid: transfer.txid, walletSession: viewModel.historySession, viewModel: viewModel)
                    } label: {
                        Label(
                            L10n.neon("Explorer details", classicUI: classicUI),
                            systemImage: "arrow.up.right.square"
                        )
                    }
                    .tint(palette?.accent ?? .accentColor)
                    .foregroundColor(palette?.accent ?? .accentColor)
                    if let url = URL(string: "https://explorer.nexawal.com/tx/\(transfer.txid)") {
                        Text(L10n.neon("Copy Explorer Link", classicUI: classicUI))
                            .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                            .foregroundStyle(palette?.secondaryText ?? .secondary)
                        Button {
                            UIPasteboard.general.string = url.absoluteString
                            AppHaptics.light()
                        } label: {
                            Text(verbatim: url.absoluteString)
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
                } header: {
                    Text(L10n.neon("Identifiers", classicUI: classicUI))
                        .font(classicUI ? .system(.subheadline, design: .monospaced).weight(.bold) : .subheadline)
                        .foregroundStyle(palette?.accent ?? .secondary)
                }
            }
            .listRowBackground(palette?.panel ?? Color(.secondarySystemGroupedBackground))
            .listSectionSeparatorTint(palette?.border.opacity(0.5))
            .scrollContentBackground(palette == nil ? .visible : .hidden)
            .background(palette?.background ?? Color(.systemGroupedBackground))
            .tint(palette?.accent ?? .accentColor)
            .navigationTitle(classicUI ? "" : L10n.t("Transaction"))
            .navigationBarTitleDisplayMode(classicUI ? .inline : .large)
            .toolbarBackground(palette?.background ?? Color(.systemBackground), for: .navigationBar)
            .toolbarColorScheme(classicUI ? .dark : nil, for: .navigationBar)
            .font(classicUI ? .system(.body, design: .monospaced) : .body)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if classicUI {
                    ToolbarItem(placement: .principal) {
                        Text(L10n.neon("Transaction", classicUI: true))
                            .font(.system(.headline, design: .monospaced).weight(.bold))
                            .foregroundStyle(palette?.accent ?? .green)
                    }
                }
            }
        }
        .background(palette?.background ?? Color(.systemGroupedBackground))
        .tint(palette?.accent ?? .accentColor)
    }
}
