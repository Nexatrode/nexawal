//
//  nexawalApp.swift
//  nexawal
//
//  Created by steve on 12/1/25.
//

import SwiftUI
import UIKit

@main
struct nexawalApp: App {
    @State private var termsAccepted = !MoneroConfig.needsTermsAcceptance

    init() {
        MoneroConfig.migrateAppearancePreferenceIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            Group {
#if DEBUG && targetEnvironment(simulator)
                if LayoutRegressionMode.enabled {
                    LayoutRegressionView()
                } else {
                    appContent
                }
#else
                appContent
#endif
            }
            #if targetEnvironment(macCatalyst)
            .background(CatalystWindowConfigurator())
            .onReceive(NotificationCenter.default.publisher(for: UIScene.didActivateNotification)) { _ in
                CatalystWindow.applySizeRestrictions()
            }
            #endif
        }
        #if targetEnvironment(macCatalyst)
        .defaultSize(width: CatalystWindow.defaultSize.width, height: CatalystWindow.defaultSize.height)
        .windowResizability(.automatic)
        #endif
    }

    private var appContent: some View {
        Group {
            if termsAccepted {
                // Own the ViewModel here so wallet open/sync cannot start before terms are accepted.
                AppRootView(onWipeSuccess: { termsAccepted = false })
            } else {
                TermsAcceptanceRootView {
                    termsAccepted = true
                }
            }
        }
    }
}

/// Resolves the system appearance from inside the window's SwiftUI environment.
/// Reading `colorScheme` on the `App` value can yield the default light scheme,
/// which made the first-run terms gate render with the wrong palette in dark mode.
private struct TermsAcceptanceRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(MoneroConfig.userDefaultsTechnoThemeKey)
    private var technoThemeEnabled = MoneroConfig.defaultTechnoThemeEnabled

    var onAccepted: () -> Void

    var body: some View {
        TermsAcceptanceView(onAccepted: onAccepted)
            .classicTheme(enabled: technoThemeEnabled, colorScheme: colorScheme)
    }
}

#if targetEnvironment(macCatalyst)
private enum CatalystWindow {
    static let defaultSize = CGSize(width: 1100, height: 760)
    static let minimumSize = CGSize(width: 800, height: 560)

    static func applySizeRestrictions() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            windowScene.sizeRestrictions?.minimumSize = minimumSize
            windowScene.sizeRestrictions?.maximumSize = CGSize(width: 10_000, height: 10_000)
            windowScene.sizeRestrictions?.allowsFullScreen = true
        }
    }
}

/// Catalyst defaults to a fixed window (min == max). Full screen still works; drag/zoom do not.
private struct CatalystWindowConfigurator: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        DispatchQueue.main.async {
            CatalystWindow.applySizeRestrictions()
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        CatalystWindow.applySizeRestrictions()
    }
}
#endif

/// App shell after terms acceptance: wallet lifecycle, background snapshot, foreground catch-up.
private struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = WalletViewModel()
    @State private var showWipeConfirmation = false
    @State private var wipeInProgress = false
    @State private var wipeError: String?

    var onWipeSuccess: () -> Void

    // Debounce snapshots so we don't export twice when .inactive immediately transitions to .background.
    @State private var lastSnapshotAt: Date = .distantPast
    private let snapshotDebounceSeconds: TimeInterval = 3.0

    var body: some View {
        ContentView(viewModel: viewModel, onWipeRequested: {
            showWipeConfirmation = true
        })
            .alert(
                L10n.t("Wipe wallet and start over?"),
                isPresented: $showWipeConfirmation
            ) {
                Button(L10n.t("Wipe wallet and start over"), role: .destructive) {
                    Task { await wipeWalletAndStartOver() }
                }
                Button(L10n.t("Cancel"), role: .cancel) {}
            } message: {
                Text(L10n.t("This permanently deletes the saved recovery phrase, wallet data, local sync cache, prepared-send recovery data, and app settings from this device. Make sure you have backed up your recovery phrase before continuing. You will need to accept the Terms of Use again, then create or restore a wallet."))
            }
            .alert(L10n.t("Could not wipe wallet"), isPresented: Binding(
                get: { wipeError != nil },
                set: { if !$0 { wipeError = nil } }
            )) {
                Button(L10n.t("OK"), role: .cancel) { wipeError = nil }
            } message: {
                Text(wipeError ?? "")
            }
            .overlay {
                if wipeInProgress {
                    ZStack {
                        Color.black.opacity(0.45).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text(L10n.t("Wiping wallet data…"))
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            // Keep the hierarchy alive (including auth prompts), but conceal it before snapshots.
            .opacity(scenePhase == .active ? 1 : 0)
            .overlay {
                if scenePhase != .active { Color.black.ignoresSafeArea() }
            }
#if targetEnvironment(macCatalyst)
            // Do not attach a tap recognizer to the whole Catalyst hierarchy: it can
            // compete with sidebar/list controls for mouse clicks. Only observe drags here.
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { _ in viewModel.noteUserInteraction() }
            )
#else
            // Setup/unlock controls should receive taps without an app-wide gesture
            // recognizer competing for them. The observer only matters once a wallet
            // is open and the inactivity lock timer is active.
            .modifier(ActiveWalletInteractionGesture(isEnabled: viewModel.isWalletOpen) {
                viewModel.noteUserInteraction()
            })
#endif
            .onChange(of: viewModel.isWalletOpen) {
                viewModel.noteUserInteraction()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                viewModel.markNeedsRefreshRetryIfInitialSyncInterrupted()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                viewModel.resumeOnDidBecomeActive()
            }
            .onChange(of: scenePhase) {
                if scenePhase == .active {
                    viewModel.endBriefBackgroundSync(reason: "foreground")
                    viewModel.resumeOnForeground()
                    FiatPriceService.shared.onForeground()
                    return
                }

                // Stop periodic tip catch-up while not active; brief background sync may still run.
                viewModel.stopForegroundCatchUp()
                FiatPriceService.shared.onBackground()

                // While refreshing, request iOS's short background window so a quick app-switch
                // (Messages, Control Center → back) can keep scanning for ~30s instead of freezing
                // immediately. On expiration we snapshot and let the process suspend.
                if scenePhase == .background {
                    viewModel.beginBriefBackgroundSyncIfNeeded()
                    viewModel.lockForBackground()
                    return
                }

                // Inactive (e.g. Control Center / app switcher peek): debounced cache snapshot only.
                guard scenePhase == .inactive else { return }

                let now = Date()
                guard now.timeIntervalSince(lastSnapshotAt) >= snapshotDebounceSeconds else { return }
                lastSnapshotAt = now
                viewModel.snapshotForBackground()
            }
    }

    @MainActor
    private func wipeWalletAndStartOver() async {
        guard !wipeInProgress else { return }
        wipeInProgress = true
        defer { wipeInProgress = false }
        do {
            try await viewModel.wipeWalletAndStartOver()
            onWipeSuccess()
        } catch {
            wipeError = error.localizedDescription
        }
    }
}

private struct ActiveWalletInteractionGesture: ViewModifier {
    let isEnabled: Bool
    let onInteraction: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.simultaneousGesture(
                // A zero-distance drag begins on every tap and can capture the
                // system Duo sidebar toggle before it presents/dismisses.
                DragGesture(minimumDistance: 12)
                    .onChanged { _ in onInteraction() }
            )
        } else {
            content
        }
    }
}
