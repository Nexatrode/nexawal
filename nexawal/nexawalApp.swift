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
                AppRootView()
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

    // Debounce snapshots so we don't export twice when .inactive immediately transitions to .background.
    @State private var lastSnapshotAt: Date = .distantPast
    private let snapshotDebounceSeconds: TimeInterval = 3.0

    var body: some View {
        ContentView(viewModel: viewModel)
            // Keep the hierarchy alive (including auth prompts), but conceal it before snapshots.
            .opacity(scenePhase == .active ? 1 : 0)
            .overlay {
                if scenePhase != .active { Color.black.ignoresSafeArea() }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in viewModel.noteUserInteraction() }
            )
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
}
