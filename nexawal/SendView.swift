import SwiftUI
import NexaWalLogic

struct SendView: View {
    @ObservedObject var viewModel: WalletViewModel
    @ObservedObject private var fiatPrices = FiatPriceService.shared

    @Environment(\.classicUI) private var classicUI
    @Environment(\.classicPalette) private var classicPalette
    @Environment(\.colorScheme) private var colorScheme

    // Inputs
    @State private var toAddress: String = ""
    @State private var amountXMR: String = ""
    @State private var amountInputMode: AmountInputMode = .xmr
    @State private var paymentDescription: String = ""
    @State private var paymentRecipientName: String = ""
    @State private var suppressDestinationChange: Bool = false

    // State
    @State private var isEstimating: Bool = false
    @State private var isMaxMode: Bool = false
    /// When true, the next amountXMR change is from Send Max fill and must not clear isMaxMode.
    @State private var suppressAmountChangeClearingMaxMode: Bool = false
    @State private var isSending: Bool = false
    @State private var previewReady: Bool = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var showSendConfirmation: Bool = false
    @State private var showScanner: Bool = false

    // Subaddress send selection (account 0 only for MVP)
    @State private var fromSubaddressMinor: UInt32 = 0
    @State private var sendFromSubaddressEnabled: Bool = false
    @State private var subaddressUnlockedOverride: UInt64?

    // Outputs
    @State private var estimatedFeePiconero: UInt64?
    @State private var sentTxid: String?
    @State private var sentFeePiconero: UInt64?

    // In-flight task cancellation / debouncing for fee + sweep previews.
    @State private var feePreviewTask: Task<Void, Never>?
    @State private var sweepPreviewTask: Task<Void, Never>?

    private let walletManager = WalletManager.shared

    private func availablePiconero() -> UInt64 {
        if sendFromSubaddressEnabled, let v = subaddressUnlockedOverride {
            return v
        }
        return viewModel.unlockedBalance
    }

    private func availableLabel() -> String {
        if sendFromSubaddressEnabled {
            return L10n.t("Available (selected subaddress)")
        }
        return L10n.t("Available")
    }

    private func refreshSubaddressBalanceIfNeeded() async {
        guard sendFromSubaddressEnabled else {
            subaddressUnlockedOverride = nil
            return
        }
        do {
            let bal = try await walletManager.getBalance(fromSubaddressMinor: fromSubaddressMinor)
            subaddressUnlockedOverride = bal.unlocked
        } catch {
            // Best effort: if it fails, fall back to wallet-wide balance.
            subaddressUnlockedOverride = nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if availablePiconero() > 0 {
                        Text("\(availableLabel()): \(viewModel.formatDisplayPiconero(availablePiconero()))")
                            .font(classicUI ? .system(.subheadline, design: .monospaced) : .subheadline)
                            .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                    }

                    toAddressField
                    amountField
                    paymentUriDetails

                    if let info = infoMessage {
                        Text(info)
                            .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                            .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                    }

                    if let err = errorMessage {
                        Text(err)
                            .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                            .foregroundColor(classicPalette?.danger ?? .red)
                    }

                    if let fee = estimatedFeePiconero {
                        confirmSection(fee: fee)
                    }

                    if let txid = sentTxid, let fee = sentFeePiconero {
                        sentSection(txid: txid, fee: fee)
                    }

                    actionButtons
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .background((classicPalette?.background ?? Color(.systemBackground)).ignoresSafeArea())
            .scrollContentBackground(classicUI ? .hidden : .automatic)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(classicUI ? L10n.t("Send XMR").uppercased() : L10n.t("Send XMR"))
                        .font(classicUI ? .system(.headline, design: .monospaced).weight(.bold) : .headline)
                        .foregroundStyle(classicPalette?.primaryText ?? .primary)
                }
            }
            .tint(classicPalette?.accent ?? .accentColor)
            .sheet(isPresented: $showScanner) {
                QRScannerView { code in
                    handleScannedCode(code)
                }
                .classicTheme(enabled: classicUI, colorScheme: colorScheme)
                .presentationDragIndicator(.visible)
            }
        }
        .onAppear {
            // Reset transient state on open
            errorMessage = nil
            infoMessage = nil
            sentTxid = nil
            sentFeePiconero = nil
            isMaxMode = false

            // Ensure subaddress list is loaded for picker
            Task {
                await viewModel.loadReceiveSubaddresses()
                await refreshSubaddressBalanceIfNeeded()
            }
        }
        .onChange(of: amountXMR) { _, _ in
            // Editing the amount exits sweep mode (programmatic fill sets a suppress flag).
            guard !suppressAmountChangeClearingMaxMode else {
                suppressAmountChangeClearingMaxMode = false
                return
            }
            if isMaxMode {
                isMaxMode = false
            }
        }
        .onChange(of: toAddress) { _, newValue in
            if suppressDestinationChange {
                suppressDestinationChange = false
                return
            }

            if let parsed = MoneroPaymentURI.parse(newValue),
               MoneroPaymentURI.hasCompleteAddressShape(parsed.address) {
                applyPaymentUri(parsed, successMessage: nil)
                return
            }

            paymentDescription = ""
            paymentRecipientName = ""
            estimatedFeePiconero = nil
            previewReady = false
            if isMaxMode {
                isMaxMode = false
            }
        }
        .onChange(of: sendFromSubaddressEnabled) {
            Task { await refreshSubaddressBalanceIfNeeded() }
            if isMaxMode {
                isMaxMode = false
                estimatedFeePiconero = nil
                previewReady = false
            }
        }
        .onChange(of: fromSubaddressMinor) {
            Task { await refreshSubaddressBalanceIfNeeded() }
            if isMaxMode {
                isMaxMode = false
                estimatedFeePiconero = nil
                previewReady = false
            }
        }
        .confirmationDialog(
            isMaxMode ? L10n.t("Confirm Send Max") : "Confirm Send",
            isPresented: $showSendConfirmation,
            titleVisibility: .visible
        ) {
            Button(isMaxMode ? L10n.t("Confirm Send Max") : "Confirm Send") {
                guard !isSending else { return }
                // Disable immediately so dismiss+Task cannot race a second send.
                isSending = true
                showSendConfirmation = false
                Task {
                    await performSend()
                }
            }
            .disabled(isSending)
            Button("Cancel", role: .cancel) {
            }
            .disabled(isSending)
        } message: {
            Text(confirmationMessage())
        }
    }

    private var fieldCorner: CGFloat { classicUI ? 4 : 8 }

    private var toAddressField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("To address"))
                .font(classicUI ? .system(.subheadline, design: .monospaced) : .subheadline)
                .foregroundStyle(classicPalette?.primaryText ?? .primary)

            HStack(spacing: 8) {
                TextField(L10n.t("To address"), text: $toAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(classicPalette?.primaryText ?? .primary)
                    .accessibilityLabel(L10n.t("To address"))

                Button {
                    showScanner = true
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(classicPalette?.accent ?? Color.accentColor)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("Scan QR code"))
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .background(classicPalette?.panel ?? Color(.secondarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: fieldCorner)
                    .stroke(classicPalette?.border ?? Color(.separator), lineWidth: classicUI ? 1 : 1)
            )
            .cornerRadius(fieldCorner)
        }
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("Amount"))
                .font(classicUI ? .system(.subheadline, design: .monospaced) : .subheadline)
                .foregroundStyle(classicPalette?.primaryText ?? .primary)

            AmountUnitField(
                text: $amountXMR,
                mode: $amountInputMode,
                rate: fiatPrices.displayRate,
                placeholder: "0.0",
                accessibilityLabel: L10n.t("Amount"),
                classicUI: classicUI,
                classicPalette: classicPalette
            )
            .padding(12)
            .background(classicPalette?.panel ?? Color(.secondarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: fieldCorner)
                    .stroke(classicPalette?.border ?? Color(.separator), lineWidth: classicUI ? 1 : 1)
            )
            .cornerRadius(fieldCorner)

            if isMaxMode {
                Text(L10n.t("Send Max mode: Confirm will sweep all unlocked after fee."))
                    .font(.caption)
                    .foregroundStyle(classicPalette?.accent ?? .secondary)
            }
            if let amount = parsedAmountPiconero(),
               let secondary = AmountUnitParsing.secondaryLine(
                piconero: amount,
                mode: amountInputMode,
                rate: fiatPrices.displayRate
               ) {
                Text(secondary)
                    .font(.caption)
                    .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
            }
        }
    }

    @ViewBuilder
    private var paymentUriDetails: some View {
        if !paymentRecipientName.isEmpty || !paymentDescription.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("Payment URI"))
                    .font(classicUI ? .system(.headline, design: .monospaced).weight(.bold) : .headline)
                    .foregroundStyle(classicPalette?.primaryText ?? .primary)

                if !paymentRecipientName.isEmpty {
                    LabeledContent(L10n.t("Recipient"), value: paymentRecipientName)
                }
                if !paymentDescription.isEmpty {
                    LabeledContent {
                        Text(paymentDescription)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    } label: {
                        Text(L10n.t("Description"))
                    }
                }
            }
            .font(.subheadline)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(classicPalette?.panel ?? Color(.secondarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: classicUI ? 4 : 16)
                    .stroke(classicPalette?.border ?? Color.clear, lineWidth: classicUI ? 1 : 0)
            )
            .cornerRadius(classicUI ? 4 : 16)
        }
    }

    @ViewBuilder
    private func confirmSection(fee: UInt64) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(classicUI ? L10n.t("Confirm").uppercased() : L10n.t("Confirm"))
                .font(classicUI ? .system(.headline, design: .monospaced).weight(.bold) : .headline)
                .foregroundStyle(classicPalette?.primaryText ?? .primary)

            if isMaxMode, let amt = parsedAmountPiconero() {
                HStack {
                    Text(L10n.t("Preview amount (max)"))
                    Spacer()
                    Text(viewModel.formatExactPiconero(amt))
                        .font(.system(.caption, design: .monospaced))
                }
                FiatApproxText(
                    piconero: amt,
                    rate: fiatPrices.displayRate,
                    color: classicPalette?.secondaryText ?? .secondary
                )
            }
            HStack {
                Text("Estimated fee")
                Spacer()
                Text(viewModel.formatExactPiconero(fee))
                    .font(.system(.caption, design: .monospaced))
            }
            FiatApproxText(
                piconero: fee,
                rate: fiatPrices.displayRate,
                color: classicPalette?.secondaryText ?? .secondary
            )
            if let amt = parsedAmountPiconero() {
                HStack {
                    Text(isMaxMode ? L10n.t("Wallet debit (amount + fee)") : "Total (amount + fee)")
                    Spacer()
                    let total = safeAdd(amt, fee)
                    Text(viewModel.formatExactPiconero(total))
                        .font(.system(.caption, design: .monospaced))
                }
                FiatApproxText(
                    piconero: safeAdd(amt, fee),
                    rate: fiatPrices.displayRate,
                    color: classicPalette?.secondaryText ?? .secondary
                )
            }

            Text(toAddress)
                .font(.system(.caption2, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(classicPalette?.panel ?? Color(.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: classicUI ? 4 : 16)
                .stroke(classicPalette?.border ?? Color.clear, lineWidth: classicUI ? 1 : 0)
        )
        .cornerRadius(classicUI ? 4 : 16)
    }

    @ViewBuilder
    private func sentSection(txid: String, fee: UInt64) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(classicUI ? L10n.t("Sent").uppercased() : L10n.t("Sent"))
                .font(classicUI ? .system(.headline, design: .monospaced).weight(.bold) : .headline)
                .foregroundStyle(classicPalette?.primaryText ?? .primary)

            HStack {
                Text("TXID")
                Spacer()
                Text(txid)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            HStack {
                Text("Fee")
                Spacer()
                Text(viewModel.formatExactPiconero(fee))
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(classicPalette?.panel ?? Color(.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: classicUI ? 4 : 16)
                .stroke(classicPalette?.border ?? Color.clear, lineWidth: classicUI ? 1 : 0)
        )
        .cornerRadius(classicUI ? 4 : 16)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Text(classicUI ? L10n.t("Actions").uppercased() : L10n.t("Actions"))
                .font(classicUI ? .system(.caption, design: .monospaced).weight(.semibold) : .caption)
                .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if classicUI, let palette = classicPalette {
                Button {
                    Task { await estimateFee() }
                } label: {
                    Text(isEstimating && !isMaxMode ? "Estimating..." : "Preview Fee")
                }
                .buttonStyle(NeonSecondaryButtonStyle(palette: palette))
                .disabled(viewModel.isRefreshing || isEstimating || isSending || parsedAmountPiconero() == nil || !looksLikeAddress(toAddress))

                Button {
                    showSendConfirmation = true
                } label: {
                    Text(isSending && !isMaxMode ? "Sending..." : "Send")
                        .neonCTAStyle(classicUI: true, palette: palette)
                }
                .buttonStyle(.plain)
                .disabled(isEstimating || isSending || !canSendExact())

                Button {
                    Task { await sendMax() }
                } label: {
                    Text(isEstimating ? L10n.t("Estimating...") : L10n.t("Preview Send Max"))
                }
                .buttonStyle(NeonSecondaryButtonStyle(palette: palette))
                .disabled(viewModel.isRefreshing || isEstimating || isSending || !looksLikeAddress(toAddress))

                Button {
                    showSendConfirmation = true
                } label: {
                    Text(isSending && isMaxMode ? "Sending..." : L10n.t("Send Max"))
                        .neonCTAStyle(classicUI: true, palette: palette)
                }
                .buttonStyle(.plain)
                .disabled(isEstimating || isSending || !canSendMax())
            } else {
                Button {
                    Task { await estimateFee() }
                } label: {
                    Text(isEstimating && !isMaxMode ? "Estimating..." : "Preview Fee")
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isRefreshing || isEstimating || isSending || parsedAmountPiconero() == nil || !looksLikeAddress(toAddress))

                Button {
                    showSendConfirmation = true
                } label: {
                    Text(isSending && !isMaxMode ? "Sending..." : "Send")
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .disabled(isEstimating || isSending || !canSendExact())

                Button {
                    Task { await sendMax() }
                } label: {
                    Text(isEstimating ? L10n.t("Estimating...") : L10n.t("Preview Send Max"))
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isRefreshing || isEstimating || isSending || !looksLikeAddress(toAddress))

                Button {
                    showSendConfirmation = true
                } label: {
                    Text(isSending && isMaxMode ? "Sending..." : L10n.t("Send Max"))
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .disabled(isEstimating || isSending || !canSendMax())
            }
        }
    }

    // MARK: - Actions

    private func estimateFee() async {
        guard !viewModel.isRefreshing else {
            errorMessage = L10n.t("Wait for wallet sync to finish before preparing a send.")
            return
        }
        let walletId = await walletManager.getCurrentWalletId() ?? "(none)"
        print("🧭 UI action: estimateFee tapped wallet_id=\(walletId) isMaxMode=\(isMaxMode) sendFromSubaddressEnabled=\(sendFromSubaddressEnabled) fromSubaddressMinor=\(fromSubaddressMinor) amountXMR=\(amountXMR) toAddress_prefix=\(String(toAddress.prefix(12)))")

        // Cancel any previous fee preview and start a new one.
        feePreviewTask?.cancel()
        sweepPreviewTask?.cancel()

        feePreviewTask = Task {
            // Small debounce to coalesce rapid taps / state changes.
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }

            guard let amountPico = parsedAmountPiconero(),
                  let ring = parsedRingLen(),
                  looksLikeAddress(toAddress) else {
                await MainActor.run {
                    errorMessage = L10n.t("Enter a valid address and amount.")
                    previewReady = false
                }
                return
            }

            await MainActor.run {
                errorMessage = nil
                infoMessage = nil
                isEstimating = true
                estimatedFeePiconero = nil
                previewReady = false
                // If the user is previewing a specific amount, we are not in "Send Max" (sweep) mode.
                isMaxMode = false
            }

            do {
                let fee: UInt64
                if sendFromSubaddressEnabled {
                    fee = try await walletManager.previewFee(
                        fromSubaddressMinor: fromSubaddressMinor,
                        toAddress: toAddress,
                        amountPiconero: amountPico,
                        ringLen: ring
                    )
                    if Task.isCancelled { return }
                    await MainActor.run {
                        infoMessage = L10n.t("Fee estimated (inputs constrained to selected subaddress).")
                    }
                } else {
                    fee = try await walletManager.previewFee(toAddress: toAddress, amountPiconero: amountPico, ringLen: ring)
                    if Task.isCancelled { return }
                    await MainActor.run {
                        infoMessage = L10n.t("Fee estimated using broadcast policy.")
                    }
                }

                if Task.isCancelled { return }
                await MainActor.run {
                    estimatedFeePiconero = fee
                    previewReady = true
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    previewReady = false
                    errorMessage = L10n.format("Fee preview failed: %@", error.localizedDescription)
                }
            }

            await MainActor.run {
                isEstimating = false
            }
        }

        // Keep API signature; caller awaits immediately, but work happens in the managed task.
        await feePreviewTask?.value
    }

    private func performSend() async {
        guard !viewModel.isRefreshing else {
            errorMessage = L10n.t("Wait for wallet sync to finish before sending.")
            return
        }
        let walletId = await walletManager.getCurrentWalletId() ?? "(none)"
        print("🧭 UI action: performSend tapped wallet_id=\(walletId) isMaxMode=\(isMaxMode) sendFromSubaddressEnabled=\(sendFromSubaddressEnabled) fromSubaddressMinor=\(fromSubaddressMinor) amountXMR=\(amountXMR) previewReady=\(previewReady) feePiconero=\(estimatedFeePiconero.map(String.init) ?? "(nil)") toAddress_prefix=\(String(toAddress.prefix(12)))")

        // Confirm sets isSending before launching this task; always clear on exit.
        defer { isSending = false }

        guard let ring = parsedRingLen(),
              looksLikeAddress(toAddress) else {
            errorMessage = L10n.t("Enter a valid address and amount.")
            return
        }
        guard previewReady, estimatedFeePiconero != nil else {
            errorMessage = L10n.t("Preview the fee before sending.")
            return
        }

        errorMessage = nil
        infoMessage = nil
        isSending = true
        sentTxid = nil
        sentFeePiconero = nil

        do {
            try await viewModel.authenticateForSensitiveAction(prompt: L10n.t("Authenticate to send Monero"))
            if isMaxMode {
                // In max mode, always sweep at send time so fee changes are handled correctly.
                let result: (txid: String, amount: UInt64, fee: UInt64)
                if sendFromSubaddressEnabled {
                    result = try await walletManager.sweep(fromSubaddressMinor: fromSubaddressMinor, toAddress: toAddress, ringLen: ring)
                    infoMessage = L10n.format("Swept max spendable from selected subaddress via %@.", policyText())
                } else {
                    result = try await walletManager.sweep(toAddress: toAddress, ringLen: ring)
                    infoMessage = L10n.format("Swept max spendable via %@.", policyText())
                }

                sentTxid = result.txid
                sentFeePiconero = result.fee
                estimatedFeePiconero = result.fee
                FiatPriceService.shared.recordSend(txid: result.txid)

                // Keep UI honest: set the amount field to what was actually sent.
                suppressAmountChangeClearingMaxMode = true
                setAmountFieldToXmrPiconero(result.amount)
                isMaxMode = false
            } else {
                guard let amountPico = parsedAmountPiconero() else {
                    errorMessage = L10n.t("Enter a valid address and amount.")
                    return
                }

                // Balance sanity check for exact-amount sends.
                // If sending from a subaddress, validate against that subaddress's unlocked balance.
                let available = availablePiconero()
                if let fee = estimatedFeePiconero {
                    if !SendSafety.hasUnlockedForExactSend(
                        amountPiconero: amountPico,
                        feePiconero: fee,
                        unlockedPiconero: available
                    ) {
                        errorMessage = L10n.t("Insufficient unlocked balance for amount + fee.")
                        return
                    }
                } else if amountPico > available {
                    errorMessage = L10n.t("Insufficient unlocked balance.")
                    return
                }

                let result: (txid: String, fee: UInt64)
                if sendFromSubaddressEnabled {
                    result = try await walletManager.send(
                        fromSubaddressMinor: fromSubaddressMinor,
                        toAddress: toAddress,
                        amountPiconero: amountPico,
                        ringLen: ring
                    )
                    infoMessage = L10n.format("Transaction broadcast from selected subaddress via %@.", policyText())
                } else {
                    result = try await walletManager.send(toAddress: toAddress, amountPiconero: amountPico, ringLen: ring)
                    infoMessage = L10n.format("Transaction broadcast via %@.", policyText())
                }

                sentTxid = result.txid
                sentFeePiconero = result.fee
                estimatedFeePiconero = result.fee
                FiatPriceService.shared.recordSend(txid: result.txid)
            }

            // Refresh balance after send
            await viewModel.updateBalance()
            await refreshSubaddressBalanceIfNeeded()
        } catch {
            errorMessage = authRetryMessage(for: error) ?? L10n.format("Send failed: %@", error.localizedDescription)
        }
    }

    /// If `error` is an auth-related `WalletStorageError`, return a clear retry message.
    /// Otherwise return nil so the caller falls back to the generic "Send failed" message.
    private func authRetryMessage(for error: Error) -> String? {
        switch error {
        case WalletStorageError.cancelled,
             WalletStorageError.biometryNotAvailable,
             WalletStorageError.biometryNotEnrolled,
             WalletStorageError.authenticationFailed:
            return L10n.t("Authentication required to send. Try again.")
        default:
            return nil
        }
    }

    // MARK: - Helpers

    private func parsedRingLen() -> UInt8? {
        16
    }

    private func parsedAmountPiconero() -> UInt64? {
        AmountUnitParsing.piconero(text: amountXMR, mode: amountInputMode, rate: fiatPrices.displayRate)
    }

    private func setAmountFieldToXmrPiconero(_ piconero: UInt64) {
        amountInputMode = .xmr
        amountXMR = FiatEstimate.formatXmrForInput(piconero: piconero)
    }

    private func canSend() -> Bool {
        guard !viewModel.isRefreshing, !isSending, !isEstimating else { return false }
        guard parsedAmountPiconero() != nil, parsedRingLen() != nil else { return false }
        guard looksLikeAddress(toAddress) else { return false }
        guard previewReady, estimatedFeePiconero != nil else { return false }
        return true
    }

    private func canSendExact() -> Bool {
        canSend() && !isMaxMode
    }

    private func canSendMax() -> Bool {
        canSend() && isMaxMode
    }

    private func looksLikeAddress(_ addr: String) -> Bool {
        MoneroPaymentURI.hasCompleteAddressShape(addr)
    }

    private func policyText() -> String {
        switch MoneroConfig.networkPolicy {
        case .clearnet: return L10n.t("Clearnet only")
        case .i2p: return L10n.t("I2P only")
        case .hybrid: return L10n.t("Scan clearnet, broadcast I2P")
        }
    }

    private func safeAdd(_ a: UInt64, _ b: UInt64) -> UInt64 {
        let (sum, overflow) = a.addingReportingOverflow(b)
        return overflow ? UInt64.max : sum
    }

    private func handleScannedCode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.lowercased().hasPrefix("monero:") {
            parseMoneroUri(trimmed)
        } else if looksLikeAddress(trimmed) {
            paymentDescription = ""
            paymentRecipientName = ""
            toAddress = trimmed
            infoMessage = L10n.t("Address loaded from QR code.")
        } else {
            errorMessage = L10n.t("Invalid QR code. Expected Monero address or payment URI.")
        }

        estimatedFeePiconero = nil
        previewReady = false
        isMaxMode = false
    }

    /// Parse `monero:<address>?…` and `monero://<address>?…` without lowercasing Base58.
    private func parseMoneroUri(_ uri: String) {
        guard let parsed = MoneroPaymentURI.parse(uri) else {
            errorMessage = L10n.t("Invalid payment URI format.")
            return
        }
        guard MoneroPaymentURI.hasCompleteAddressShape(parsed.address) else {
            errorMessage = L10n.t("No valid address in payment URI.")
            return
        }

        applyPaymentUri(parsed, successMessage: L10n.t("Payment details loaded from QR code."))
    }

    private func applyPaymentUri(_ parsed: MoneroPaymentURI, successMessage: String?) {
        if toAddress != parsed.address {
            suppressDestinationChange = true
            toAddress = parsed.address
        } else {
            suppressDestinationChange = false
        }
        if let amount = parsed.amountXmr, let pico = XmrAmount.parsePiconero(amount) {
            suppressAmountChangeClearingMaxMode = true
            setAmountFieldToXmrPiconero(pico)
        }
        paymentDescription = parsed.txDescription ?? ""
        paymentRecipientName = parsed.recipientName ?? ""

        isMaxMode = false
        estimatedFeePiconero = nil
        previewReady = false
        errorMessage = nil
        infoMessage = successMessage
    }

    private func confirmationMessage() -> String {
        let destination = toAddress.isEmpty ? L10n.t("Unknown address") : toAddress
        if isMaxMode, let fee = estimatedFeePiconero, let amount = parsedAmountPiconero() {
            var message = L10n.format(
                "Send maximum spendable after fee to %@.\nPreview amount: %@\nEstimated fee: %@\nFinal amount is recalculated at send time.",
                destination,
                viewModel.formatExactPiconero(amount),
                viewModel.formatExactPiconero(fee)
            )
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            if let amountFiat = FiatEstimate.liveApproxText(piconero: amount, rate: fiatPrices.displayRate, nowMs: now) {
                message += L10n.format("\nAmount %@", amountFiat)
            }
            if let feeFiat = FiatEstimate.liveApproxText(piconero: fee, rate: fiatPrices.displayRate, nowMs: now) {
                message += L10n.format("\nFee %@", feeFiat)
            }
            return message
        }
        if let fee = estimatedFeePiconero, let amount = parsedAmountPiconero() {
            let total = safeAdd(amount, fee)
            var message = L10n.format(
                "Send %@ to %@.\nFee: %@\nTotal: %@",
                viewModel.formatExactPiconero(amount),
                destination,
                viewModel.formatExactPiconero(fee),
                viewModel.formatExactPiconero(total)
            )
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            if let amountFiat = FiatEstimate.liveApproxText(piconero: amount, rate: fiatPrices.displayRate, nowMs: now) {
                message += L10n.format("\nAmount %@", amountFiat)
            }
            if let feeFiat = FiatEstimate.liveApproxText(piconero: fee, rate: fiatPrices.displayRate, nowMs: now) {
                message += L10n.format("\nFee %@", feeFiat)
            }
            return message
        }
        return L10n.format("Preview the fee before sending to %@.", destination)
    }

    /// Preview maximum spendable amount, then keep sweep mode until Confirm runs `sweep()`.
    private func sendMax() async {
        guard !viewModel.isRefreshing else {
            errorMessage = L10n.t("Wait for wallet sync to finish before preparing a send.")
            return
        }
        let walletId = await walletManager.getCurrentWalletId() ?? "(none)"
        print("🧭 UI action: sendMax tapped wallet_id=\(walletId) isMaxMode=\(isMaxMode) sendFromSubaddressEnabled=\(sendFromSubaddressEnabled) fromSubaddressMinor=\(fromSubaddressMinor) amountXMR_before=\(amountXMR) toAddress_prefix=\(String(toAddress.prefix(12)))")

        // Cancel any previous sweep preview and start a new one.
        sweepPreviewTask?.cancel()
        feePreviewTask?.cancel()

        sweepPreviewTask = Task {
            // Small debounce to coalesce rapid taps / state changes.
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }

            await MainActor.run {
                errorMessage = nil
                infoMessage = nil
                isEstimating = true
                estimatedFeePiconero = nil
                previewReady = false
            }

            guard looksLikeAddress(toAddress) else {
                await MainActor.run {
                    errorMessage = L10n.t("Enter a valid address.")
                    isEstimating = false
                    isMaxMode = false
                }
                return
            }

            let ring = parsedRingLen() ?? 16

            do {
                let res: (amount: UInt64, fee: UInt64)
                if sendFromSubaddressEnabled {
                    res = try await walletManager.previewSweep(fromSubaddressMinor: fromSubaddressMinor, toAddress: toAddress, ringLen: ring)
                } else {
                    res = try await walletManager.previewSweep(toAddress: toAddress, ringLen: ring)
                }

                if Task.isCancelled {
                    await MainActor.run { isEstimating = false }
                    return
                }

                let amount = res.amount
                let fee = res.fee

                guard amount > 0 else {
                    await MainActor.run {
                        errorMessage = L10n.t("No unlocked balance available to send after fee.")
                        isMaxMode = false
                        previewReady = false
                        isEstimating = false
                    }
                    return
                }

                await MainActor.run {
                    estimatedFeePiconero = fee
                    previewReady = true
                    suppressAmountChangeClearingMaxMode = true
                    setAmountFieldToXmrPiconero(amount)
                    isMaxMode = true
                    infoMessage = L10n.t("Max preview ready. Confirm Send Max will sweep all unlocked after fee.")
                    isEstimating = false
                }
            } catch {
                if Task.isCancelled {
                    await MainActor.run { isEstimating = false }
                    return
                }
                await MainActor.run {
                    previewReady = false
                    isMaxMode = false
                    isEstimating = false
                    errorMessage = L10n.format("Fee preview failed: %@", error.localizedDescription)
                }
            }
        }

        await sweepPreviewTask?.value
    }
}

// MARK: - Preview

#Preview {
    // Minimal mock ViewModel for preview
    let vm = WalletViewModel()
    return SendView(viewModel: vm)
}
