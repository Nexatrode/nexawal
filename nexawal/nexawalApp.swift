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
    @Environment(\.scenePhase) private var scenePhase

    // Single wallet instance for the app lifecycle so we can snapshot on background.
    @StateObject private var viewModel = WalletViewModel()

    // Debounce snapshots so we don't export twice when .inactive immediately transitions to .background.
    @State private var lastSnapshotAt: Date = .distantPast
    private let snapshotDebounceSeconds: TimeInterval = 3.0

    init() {
        MoneroConfig.migrateAppearancePreferenceIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    viewModel.markNeedsRefreshRetryIfInitialSyncInterrupted()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    viewModel.resumeOnDidBecomeActive()
                }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                viewModel.endBriefBackgroundSync(reason: "foreground")
                viewModel.resumeOnForeground()
                FiatPriceService.shared.onForeground()
                return
            }

            // While refreshing, request iOS's short background window so a quick app-switch
            // (Messages, Control Center → back) can keep scanning for ~30s instead of freezing
            // immediately. On expiration we snapshot and let the process suspend.
            if scenePhase == .background {
                viewModel.beginBriefBackgroundSyncIfNeeded()
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
