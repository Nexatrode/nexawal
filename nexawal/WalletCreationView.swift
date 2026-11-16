//
//  WalletCreationView.swift
//  nexawal
//
//  View for creating or importing a wallet from mnemonic
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import MoneroWalletCoreFFI
import NexaWalLogic

struct WalletCreationView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var viewModel: WalletViewModel
    @State private var mnemonicInput: String = Self.debugTestMnemonic()
    @State private var restoreHeightInput: String = Self.debugTestRestoreHeight()
    @State private var isMainnet: Bool = true
    @FocusState private var isMnemonicFocused: Bool
    @Environment(\.classicUI) private var classicUI
    @Environment(\.classicPalette) private var classicPalette

    enum WalletSetupMode: CaseIterable, Identifiable, Hashable {
        case create
        case `import`
        var id: Self { self }

        var title: String {
            switch self {
            case .create: return L10n.t("Create new wallet (fast)")
            case .import: return L10n.t("Import existing wallet")
            }
        }
    }

    /// DEBUG-only first-run testing: scheme Environment Variables
    /// `NEXAWAL_TEST_MNEMONIC` and `NEXAWAL_TEST_RESTORE_HEIGHT` prefill Import fields.
    private static func debugTestMnemonic() -> String {
        #if DEBUG
        ProcessInfo.processInfo.environment["NEXAWAL_TEST_MNEMONIC"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        #else
        ""
        #endif
    }

    private static func debugTestRestoreHeight() -> String {
        #if DEBUG
        let raw = ProcessInfo.processInfo.environment["NEXAWAL_TEST_RESTORE_HEIGHT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "0" : raw.replacingOccurrences(of: ",", with: "")
        #else
        "0"
        #endif
    }

    // Create-mode seed backup gate: the app generates the mnemonic and requires
    // explicit acknowledgement that the recovery phrase was written down.
    @State private var generatedMnemonic: String = ""
    @State private var wroteSeedDown: Bool = false
    @State private var seedGenerationError: String?
    @State private var seedCopied = false

    @State private var setupMode: WalletSetupMode = .create

    // Import scan tuning presets (for experiments / quick switching)


    // Fast-restore-height (create mode only): we fetch daemon height info and set
    // restoreHeight = node tip - 10.
    @State private var suggestedRestoreHeight: UInt64?
    @State private var suggestedHeightNetworkKey: String?
    @State private var isFetchingSuggestedHeight: Bool = false
    @State private var suggestedHeightError: String?

    // Single-wallet UX: confirm before replacing any existing stored wallet on device.
    @State private var showReplaceConfirm: Bool = false
    @State private var hasStoredWallet: Bool = false
    // Fail protected until the availability probe completes, never briefly default off.
    @State private var requireBiometrics: Bool = true
    @State private var biometricsAvailable: Bool = false

    // Pre-wallet route config (same UserDefaults keys as Settings).
    @State private var nodeAddress: String = MoneroConfig.daemonAddress
    @State private var networkPolicy: MoneroConfig.NetworkPolicy = MoneroConfig.networkPolicy
    @State private var i2pRPCAddress: String = MoneroConfig.i2pRPCAddress
    @State private var i2pProxyAddress: String = MoneroConfig.i2pHTTPProxyAddress ?? ""
    @State private var nodeSaveStatus: String?

    private var setupNetworkKey: String {
        [
            networkPolicy.rawValue,
            nodeAddress,
            i2pRPCAddress,
            i2pProxyAddress,
            isMainnet ? "mainnet" : "testnet",
        ].joined(separator: "\u{0}")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: NeonSectionHeader(title: L10n.t("Wallet Setup"))) {
                    Text("Choose whether you're creating a brand new wallet (fast sync) or importing an existing wallet (full scan unless you set a restore height).")
                        .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                        .foregroundStyle(classicPalette?.secondaryText ?? .secondary)

                    if classicUI, let palette = classicPalette {
                        neonSetupModePicker(palette: palette)
                    } else {
                        standardSetupModePicker
                    }

                    switch setupMode {
                    case .create:
                        seedBackupGateView
                    case .import:
                        TextEditor(text: $mnemonicInput)
                            .frame(minHeight: 120)
                            .font(.system(.body, design: .monospaced))
                            .focused($isMnemonicFocused)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .privacySensitive()
                            .accessibilityLabel(L10n.t("Mnemonic (paste):"))
                    }

                    // Restore height controls:
                    // - Create mode: hide the editable field (fast restore height is applied automatically when restoreHeightInput == 0)
                    // - Import mode: show editable restore height (critical for correctness)
                    switch setupMode {
                    case .create:
                        VStack(alignment: .leading, spacing: 6) {
                            if isFetchingSuggestedHeight {
                                Text("Starting height: fetching from node…")
                                    .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                                    .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                            } else if let suggested = suggestedRestoreHeight {
                                Text(L10n.format("Starting height (fast): %lld (node tip − 10)", Int64(suggested)))
                                    .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                                    .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                            } else {
                                Text("Starting height (fast): unavailable (will use 0)")
                                    .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                                    .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                            }

                            if let msg = suggestedHeightError {
                                Text(msg)
                                    .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                                    .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                            }
                        }

                    case .import:
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Restore Height:")
                                    TextField("Restore height", text: $restoreHeightInput, prompt: Text(verbatim: "0"))
                                        .labelsHidden()
                                        .keyboardType(.numberPad)
                                        .accessibilityLabel(L10n.t("Restore Height:"))
                                }

                                let height = UInt64(restoreHeightInput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                                if height == 0 {
                                    Text("Tip: 0 scans the full chain history. This is the safest option if you're unsure, but it can take longer to sync.")
                                        .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                                        .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                                } else {
                                    Text("Warning: If you set a restore height after your first transaction, older funds will not appear until you rescan from an earlier height.")
                                        .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                                        .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                                }
                            }
                        }
                    }

                    NeonToggle(title: L10n.t("Mainnet"), isOn: $isMainnet)

                    NeonToggle(
                        title: L10n.t("Require device auth"),
                        isOn: $requireBiometrics,
                        disabled: !biometricsAvailable
                    )

                    if !biometricsAvailable {
                        Text("Biometric or device authentication is not available on this device.")
                            .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                            .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                    }
                }

                Section {
                    if hasStoredWallet {
                        Button(action: {
                            Task { await viewModel.unlockStoredWallet() }
                        }) {
                            HStack {
                                if viewModel.isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                }
                                Text(viewModel.isLoading ? L10n.t("Unlocking Wallet...") : L10n.t("Unlock Existing Wallet"))
                            }
                        }
                        .disabled(viewModel.isLoading)
                    }

                    if setupMode == .import {
                        Button {
                            if hasStoredWallet {
                                showReplaceConfirm = true
                            } else {
                                Task { await createOrImport(isReplace: false) }
                            }
                        } label: {
                            HStack {
                                if viewModel.isLoading {
                                    ProgressView()
                                }
                                Text(viewModel.isLoading ? L10n.t("Importing Wallet...") : L10n.t("Import Wallet"))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isLoading || isFetchingSuggestedHeight || mnemonicInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        Button {
                            // If we already have a persisted wallet, confirm before replacing it.
                            if hasStoredWallet {
                                showReplaceConfirm = true
                            } else {
                                Task { await createOrImport(isReplace: false) }
                            }
                        } label: {
                            HStack {
                                if viewModel.isLoading {
                                    ProgressView()
                                }
                                Text(viewModel.isLoading ? L10n.t("Creating Wallet...") : L10n.t("Create Wallet"))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isLoading || isFetchingSuggestedHeight || !isSeedBackupGatePassed())
                    }
                }
                .alert("Replace existing wallet?", isPresented: $showReplaceConfirm) {
                    Button("Cancel", role: .cancel) {}
                    Button("Replace", role: .destructive) {
                        Task { await createOrImport(isReplace: true) }
                    }
                } message: {
                    Text("This will replace the existing wallet on this device.\n\nIf you continue, the currently stored mnemonic and scan state will be removed. Make sure you have your mnemonic backed up before proceeding.")
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(classicPalette?.danger ?? .red)
                            .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                    }
                }

                Section(header: NeonSectionHeader(title: L10n.t("Network & Node"))) {
                    Picker("How to connect", selection: $networkPolicy) {
                        Text("Clearnet only").tag(MoneroConfig.NetworkPolicy.clearnet)
                        Text("I2P only").tag(MoneroConfig.NetworkPolicy.i2p)
                        Text("Both (scan clearnet, broadcast I2P)").tag(MoneroConfig.NetworkPolicy.hybrid)
                    }
                    .pickerStyle(.menu)
                    .tint(classicPalette?.accent ?? .accentColor)

                    Text(L10n.t("Clearnet only uses a clearnet node. I2P only uses an I2P node and proxy. Both scans on clearnet and broadcasts over I2P."))
                        .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                        .foregroundStyle(classicPalette?.secondaryText ?? .secondary)

                    if networkPolicy != .i2p {
                        TextField("https://rpc.nexawal.com", text: $nodeAddress)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(classicPalette?.primaryText ?? .primary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .accessibilityLabel(L10n.t("Clearnet node URL"))
                        Text(L10n.t("Type the full URL, including http:// or https://.\nDefault: https://rpc.nexawal.com"))
                            .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                            .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                    }

                    if networkPolicy != .clearnet {
                        TextField("I2P node (host:port)", text: $i2pRPCAddress)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(classicPalette?.primaryText ?? .primary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .accessibilityLabel(L10n.t("I2P node (host:port)"))
                        TextField("I2P HTTP proxy (host:port)", text: $i2pProxyAddress)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(classicPalette?.primaryText ?? .primary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .accessibilityLabel(L10n.t("I2P HTTP proxy (host:port)"))
                        Text(L10n.t("I2P requires an HTTP proxy reachable from this device. 127.0.0.1 refers to this device."))
                            .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                            .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                    }

                    Button {
                        saveNetworkSettings()
                    } label: {
                        Text(L10n.neon("Use this node", classicUI: classicUI))
                    }
                    .neonCTAStyle(classicUI: classicUI, palette: classicPalette)
                    .disabled(isFetchingSuggestedHeight)

                    if let nodeSaveStatus {
                        Text(nodeSaveStatus)
                            .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                            .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
                .disabled(isFetchingSuggestedHeight || viewModel.isLoading)

                Section(header: NeonSectionHeader(title: L10n.t("Info"))) {
                    HStack {
                        Text("WalletCore Version:")
                            .foregroundColor(classicPalette?.secondaryText)
                        Spacer()
                        Text(viewModel.getVersion())
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(classicPalette?.primaryText)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .neonFormChrome(classicUI: classicUI, palette: classicPalette)
            .tint(classicPalette?.accent ?? .accentColor)
            .formKeyboardDismissal()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(classicUI ? "nexawal" : L10n.t("Create Wallet"))
                        .font(classicUI ? .system(.headline, design: .monospaced).weight(.bold) : .headline)
                        .foregroundStyle(classicPalette?.primaryText ?? .primary)
                        .tracking(classicUI ? 2 : 0)
                }

            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background {
                mnemonicInput = ""
                generatedMnemonic = ""
                wroteSeedDown = false
            } else if scenePhase == .active, setupMode == .create, generatedMnemonic.isEmpty {
                // Backgrounding deliberately discards an uncommitted seed. Make a fresh
                // candidate as soon as the user returns instead of leaving the setup blank.
                generateNewSeed()
            }
        }
        .onDisappear {
            mnemonicInput = ""
            generatedMnemonic = ""
        }
        .task {
            // Seed creation is local and must not wait for the optional node-height lookup.
            // A slow/unreachable RPC must never leave the Create Wallet screen without words.
            if setupMode == .create, scenePhase == .active, generatedMnemonic.isEmpty {
                generateNewSeed()
            }

            // Authoritative: check persisted wallet presence (metadata) rather than in-memory UI state.
            hasStoredWallet = await viewModel.hasStoredWallet()
            let available = await viewModel.deviceAuthenticationAvailable()
            biometricsAvailable = available
            requireBiometrics = available

        }
        .onChange(of: setupMode) {
            if setupMode != .create {
                suggestedRestoreHeight = nil
                suggestedHeightNetworkKey = nil
                suggestedHeightError = nil
            }
            if setupMode == .create, generatedMnemonic.isEmpty {
                generateNewSeed()
            }
        }
        .onChange(of: setupNetworkKey) {
            suggestedRestoreHeight = nil
            suggestedHeightNetworkKey = nil
            suggestedHeightError = nil
        }
    }

    // MARK: - Neon setup mode picker

    /// Button-backed standard picker. This avoids relying on a segmented Picker's
    /// native hit testing inside the app's first-run setup hierarchy.
    private var standardSetupModePicker: some View {
        HStack(spacing: 0) {
            ForEach(WalletSetupMode.allCases) { mode in
                let selected = setupMode == mode
                Button {
                    setupMode = mode
                } label: {
                    Text(mode.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color(uiColor: .systemBackground))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9))
    }

    @ViewBuilder
    private func neonSetupModePicker(palette: ClassicPalette) -> some View {
        HStack(spacing: 0) {
            ForEach(WalletSetupMode.allCases) { mode in
                let selected = setupMode == mode
                Button {
                    setupMode = mode
                } label: {
                    Text(mode.title)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(selected ? palette.ctaText : palette.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selected ? palette.cta : Color.clear)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .background(palette.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Create-mode seed backup gate

    @ViewBuilder
    private var seedBackupGateView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Write these words down in order and store them somewhere safe offline. You'll need them to restore the wallet if this phone is lost. NexaWal also keeps an encrypted copy on device for unlock — treat the backup like cash.")
                .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                .foregroundStyle(classicPalette?.secondaryText ?? .secondary)

            mnemonicWordGrid

            Button {
                copyRecoverySeed()
            } label: {
                Label(seedCopied ? L10n.t("Copied") : L10n.t("Copy recovery seed"), systemImage: seedCopied ? "checkmark" : "doc.on.doc")
            }
            .disabled(generatedMnemonic.isEmpty)

            if let seedGenerationError {
                Text(seedGenerationError)
                    .font(.caption)
                    .foregroundColor(classicPalette?.danger ?? .red)
            }

            Button(action: { generateNewSeed() }) {
                Text("Generate new seed")
            }
            .accessibilityLabel(L10n.t("Generate new seed"))
            .disabled(viewModel.isLoading)

            NeonToggle(title: L10n.t("I wrote down my recovery seed"), isOn: $wroteSeedDown)
                .disabled(generatedMnemonic.isEmpty)

        }
    }

    private var mnemonicWordGrid: some View {
        let words = generatedMnemonic.split(separator: " ").map(String.init)
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                HStack(spacing: 4) {
                    Text("\(index + 1).")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                        .frame(width: 24, alignment: .trailing)
                    Text(word)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(classicPalette?.primaryText ?? .primary)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        .textSelection(.disabled)
        .privacySensitive()
    }

    private func copyRecoverySeed() {
        let phrase = generatedMnemonic.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !phrase.isEmpty else { return }
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: phrase]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)]
        )
        seedCopied = true
        UIAccessibility.post(notification: .announcement, argument: L10n.t("Copied"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { seedCopied = false }
    }

    private func generateNewSeed() {
        guard scenePhase == .active else { return }
        seedGenerationError = nil
        do {
            generatedMnemonic = try WalletCoreFFIClient.generateMnemonicEnglish()
        } catch {
            generatedMnemonic = ""
            seedGenerationError = L10n.format("Couldn't generate a seed: %@", error.localizedDescription)
        }
        wroteSeedDown = false
        seedCopied = false
    }

    private func isSeedBackupGatePassed() -> Bool {
        !generatedMnemonic.isEmpty && wroteSeedDown
    }

    private func createOrImport(isReplace: Bool) async {
        guard applySetupNetwork() else { return }
        if setupMode == .create, suggestedHeightNetworkKey != setupNetworkKey {
            // Keep the normal Create Wallet path fast by attempting the optional
            // near-tip height after the selected route is validated and applied.
            // The lookup is bounded and failures retain the full-scan height of 0.
            await refreshSuggestedRestoreHeightIfNeeded()
        }
        // For create mode, we hide the restore height input and use the suggested height.
        // For import mode, we take the user's input.
        let rawHeight = UInt64(restoreHeightInput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let effectiveHeight: UInt64 = {
            // Feather-style optimization: for *new wallets only*, if the user leaves restore
            // height at 0, use a fast restore height near tip only when it came from this route.
            if setupMode == .create,
               rawHeight == 0,
               suggestedHeightNetworkKey == setupNetworkKey,
               let suggested = suggestedRestoreHeight {
                return suggested
            }
            return rawHeight
        }()

        let effectiveMnemonic = (setupMode == .create) ? generatedMnemonic : mnemonicInput

        if isReplace {
            await viewModel.replaceWallet(
                mnemonic: effectiveMnemonic,
                restoreHeight: effectiveHeight,
                mainnet: isMainnet,
                requireBiometrics: requireBiometrics
            )
        } else {
            await viewModel.createWallet(
                mnemonic: effectiveMnemonic,
                restoreHeight: effectiveHeight,
                mainnet: isMainnet,
                requireBiometrics: requireBiometrics
            )
        }

        // After importing/replacing, refresh persisted-wallet flag.
        hasStoredWallet = await viewModel.hasStoredWallet()
    }

    private func applySetupNetwork() -> Bool {
        let effectiveI2PNode = NetworkRouting.effectiveI2PRPCAddress(i2pRPCAddress)
        let proxy = i2pProxyAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        var explicitClearnetNode: String?

        if networkPolicy != .i2p {
            let trimmed = nodeAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let explicit = NetworkRouting.explicitNodeURL(trimmed) else {
                nodeSaveStatus = L10n.t("Start the node URL with http:// or https://")
                return false
            }
            guard !NetworkRouting.isI2PHostnameURL(explicit) else {
                nodeSaveStatus = L10n.t("I2P node addresses require I2P only or Both and an HTTP proxy.")
                return false
            }
            explicitClearnetNode = explicit
        }

        if networkPolicy != .clearnet {
            do {
                try NetworkRouting.validateI2PConfiguration(nodeAddress: effectiveI2PNode, proxyAddress: proxy)
            } catch {
                nodeSaveStatus = error.localizedDescription
                return false
            }
        }

        // Write preferences only after every active endpoint has passed validation.
        i2pRPCAddress = effectiveI2PNode
        MoneroConfig.setNetworkPolicy(networkPolicy)
        MoneroConfig.setI2PRPCAddress(effectiveI2PNode)
        MoneroConfig.setI2PHTTPProxyAddress(proxy.isEmpty ? nil : proxy)
        MoneroConfig.setUseI2P(networkPolicy != .clearnet)
        if let explicitClearnetNode {
            nodeAddress = explicitClearnetNode
            MoneroConfig.setDaemonAddress(explicitClearnetNode)
        }

        switch networkPolicy {
        case .clearnet: nodeSaveStatus = L10n.t("Saved clearnet")
        case .i2p: nodeSaveStatus = L10n.t("Saved I2P")
        case .hybrid: nodeSaveStatus = L10n.t("Saved both")
        }
        return true
    }

    private func saveNetworkSettings() {
        guard applySetupNetwork() else { return }
        Task { await refreshSuggestedRestoreHeightIfNeeded() }
    }

    private func refreshSuggestedRestoreHeightIfNeeded() async {
        guard setupMode == .create else {
            suggestedRestoreHeight = nil
            suggestedHeightError = nil
            isFetchingSuggestedHeight = false
            return
        }

        isFetchingSuggestedHeight = true
        suggestedHeightError = nil
        suggestedRestoreHeight = nil
        suggestedHeightNetworkKey = nil
        let requestNetworkKey = setupNetworkKey

        // Fetch daemon height info and compute restoreHeight = node tip - 10.
        do {
            let baseURL = MoneroConfig.scanNodeURL()
            if MoneroConfig.networkPolicy == .i2p {
                try NetworkRouting.validateI2PConfiguration(
                    nodeAddress: baseURL, proxyAddress: MoneroConfig.i2pHTTPProxyAddress)
            }

            // If scanning over I2P, route the request through the configured HTTP proxy.
            let proxy: String? = (MoneroConfig.networkPolicy == .i2p) ? MoneroConfig.i2pHTTPProxyAddress : nil

            #if DEBUG
            WalletDiagnostics.log("🛰️ Suggested height: policy=\(MoneroConfig.networkPolicy), url=\(baseURL), proxy=\(proxy ?? "(none)")")
            #endif

            let info = try await MoneroDaemonClient.getInfo(
                baseURL: baseURL,
                proxyAddress: proxy,
                timeout: MoneroConfig.daemonProbeTimeout
            )
            let tip = info.targetHeight
            let suggested = tip > 10 ? (tip - 10) : 0
            if requestNetworkKey == setupNetworkKey {
                suggestedRestoreHeight = suggested
                suggestedHeightNetworkKey = requestNetworkKey
                suggestedHeightError = nil
            }
        } catch {
            // Non-fatal: this is only used to suggest a fast height.
            if requestNetworkKey == setupNetworkKey {
                suggestedRestoreHeight = nil
                suggestedHeightError = L10n.t("Couldn't fetch a fast restore height from the node. Leaving restore height as 0.")
                #if DEBUG
                WalletDiagnostics.log("🛰️ Suggested height failed: \(error.localizedDescription)")
                #endif
            }
        }

        isFetchingSuggestedHeight = false
    }
}
