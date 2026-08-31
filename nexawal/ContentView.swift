//
//  ContentView.swift
//  nexawal
//
//  Created by steve on 12/1/25.
//

import SwiftUI
import UIKit

enum MainTab: Hashable {
    case wallet
    case receive
    case send
    case settings

    var title: String {
        switch self {
        case .wallet: return L10n.t("Wallet")
        case .receive: return L10n.t("Receive")
        case .send: return L10n.t("Send")
        case .settings: return L10n.t("Settings")
        }
    }

    var neonTitle: String { title.uppercased() }

    var systemImage: String {
        switch self {
        case .wallet: return "house.fill"
        case .receive: return "qrcode"
        case .send: return "paperplane.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct ContentView: View {
    @ObservedObject var viewModel: WalletViewModel
    @AppStorage(MoneroConfig.userDefaultsTechnoThemeKey) private var technoThemeEnabled: Bool = MoneroConfig.defaultTechnoThemeEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: MainTab = .wallet

    var body: some View {
        Group {
            if viewModel.isWalletOpen {
                MainTabView(viewModel: viewModel, selectedTab: $selectedTab)
            } else if viewModel.isRestoringSession {
                UnlockingWalletView()
            } else if viewModel.needsUnlock {
                UnlockExistingWalletView(viewModel: viewModel)
            } else {
                WalletCreationView(viewModel: viewModel)
            }
        }
        // Techno Theme ON = neon terminal look; OFF (default) = standard look.
        .classicTheme(enabled: technoThemeEnabled, colorScheme: colorScheme)
        .task {
            // WalletViewModel handles loading any stored wallet on launch.
        }
        // Keep the display awake during an active scan so a full sync can finish with the
        // app open on a table. iOS will still suspend once the user backgrounds the app.
        .onChange(of: viewModel.isRefreshing) { _, refreshing in
            UIApplication.shared.isIdleTimerDisabled = refreshing
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}

/// Shown while Keychain / Face ID unlock runs so Create/Import does not flash.
private struct UnlockingWalletView: View {
    @Environment(\.classicUI) private var classicUI
    @Environment(\.classicPalette) private var classicPalette

    var body: some View {
        ZStack {
            (classicPalette?.background ?? Color(.systemBackground))
                .ignoresSafeArea()
            VStack(spacing: 16) {
                if classicUI {
                    Text("nexawal")
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .foregroundStyle(classicPalette?.accent ?? .primary)
                }
                ProgressView()
                    .tint(classicPalette?.accent ?? .accentColor)
                Text(L10n.t("Unlocking…"))
                    .font(classicUI ? .system(.body, design: .monospaced) : .body)
                    .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.t("Unlocking…"))
    }
}

/// Unlock-only surface after Face ID cancel (or unlock failure) when a stored wallet exists.
private struct UnlockExistingWalletView: View {
    @ObservedObject var viewModel: WalletViewModel
    @Environment(\.classicUI) private var classicUI
    @Environment(\.classicPalette) private var classicPalette

    var body: some View {
        ZStack {
            (classicPalette?.background ?? Color(.systemBackground))
                .ignoresSafeArea()
            VStack(spacing: 20) {
                if classicUI {
                    Text("nexawal")
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .foregroundStyle(classicPalette?.accent ?? .primary)
                } else {
                    Text("nexawal")
                        .font(.title2.weight(.bold))
                }

                Text(L10n.t("Unlock Existing Wallet"))
                    .font(classicUI ? .system(.body, design: .monospaced) : .body)
                    .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                    .multilineTextAlignment(.center)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                        .foregroundStyle(classicPalette?.danger ?? .red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    Task { await viewModel.unlockStoredWallet() }
                } label: {
                    HStack(spacing: 10) {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(classicUI ? (classicPalette?.background ?? .black) : .white)
                        }
                        Text(viewModel.isLoading ? L10n.t("Unlocking Wallet...") : L10n.t("Unlock Existing Wallet"))
                            .font(classicUI ? .system(.body, design: .monospaced).weight(.semibold) : .body.weight(.semibold))
                    }
                    .frame(maxWidth: 320)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(classicPalette?.accent ?? .accentColor)
                .disabled(viewModel.isLoading)

                Button {
                    viewModel.preferWalletSetup()
                } label: {
                    Text(L10n.t("Create or Import instead"))
                        .font(classicUI ? .system(.footnote, design: .monospaced) : .footnote)
                }
                .disabled(viewModel.isLoading)
                .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
            }
            .padding()
        }
        .accessibilityElement(children: .contain)
    }
}

/// Phone: bottom tabs. iPad / Mac Catalyst (regular × regular): sidebar + detail.
struct MainTabView: View {
    @ObservedObject var viewModel: WalletViewModel
    @Binding var selectedTab: MainTab
    @Environment(\.classicUI) private var classicUI
    @Environment(\.classicPalette) private var classicPalette
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private let tabs: [MainTab] = [.wallet, .receive, .send, .settings]

    private var usesSplitNavigation: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }

    /// iOS/Catalyst `List(selection:)` requires an optional; keep the parent tab non-optional.
    private var splitTabSelection: Binding<MainTab?> {
        Binding(
            get: { selectedTab },
            set: { if let tab = $0 { selectedTab = tab } }
        )
    }

    var body: some View {
        Group {
            if usesSplitNavigation {
                NavigationSplitView(columnVisibility: .constant(.all)) {
                    Group {
                        if classicUI {
                            technoSidebar
                        } else {
                            List(selection: splitTabSelection) {
                                ForEach(tabs, id: \.self) { tab in
                                    Label(tab.title, systemImage: tab.systemImage)
                                        .tag(tab)
                                }
                            }
                            .navigationTitle("nexawal")
                        }
                    }
                    .toolbar(removing: .sidebarToggle)
                } detail: {
                    tabRoot
                        .toolbar(removing: .sidebarToggle)
                }
                .navigationSplitViewStyle(.balanced)
                .tint(classicPalette?.accent ?? .accentColor)
            } else {
                VStack(spacing: 0) {
                    tabRoot
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    NeonTabBar(
                        tabs: tabs,
                        selectedTab: $selectedTab,
                        classicUI: classicUI,
                        palette: classicPalette
                    )
                }
            }
        }
        .background((classicPalette?.background ?? Color(.systemBackground)).ignoresSafeArea())
    }

    /// Match iOS/Android techno tab colors: neon green on black, no solid green/white selection pill.
    private var technoSidebar: some View {
        let palette = classicPalette ?? ClassicPalette.resolve(colorScheme: .dark)
        return VStack(alignment: .leading, spacing: 0) {
            Text("nexawal")
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 12)

            ForEach(tabs, id: \.self) { tab in
                let selected = selectedTab == tab
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 17, weight: selected ? .semibold : .regular))
                            .frame(width: 22, alignment: .center)
                        Text(tab.neonTitle)
                            .font(.system(.body, design: .monospaced).weight(selected ? .semibold : .regular))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(selected ? palette.accent : palette.secondaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selected ? palette.panel : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.background.ignoresSafeArea())
    }

    @ViewBuilder
    private var tabRoot: some View {
        switch selectedTab {
        case .wallet:
            WalletView(viewModel: viewModel, selectedTab: $selectedTab)
        case .receive:
            ReceiveView(viewModel: viewModel)
        case .send:
            SendView(viewModel: viewModel)
        case .settings:
            SettingsView(viewModel: viewModel)
        }
    }
}

private struct NeonTabBar: View {
    let tabs: [MainTab]
    @Binding var selectedTab: MainTab
    let classicUI: Bool
    let palette: ClassicPalette?

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(palette?.border.opacity(classicUI ? 0.45 : 0) ?? Color(.separator))
                .frame(height: classicUI ? 1 : 0.33)

            HStack(spacing: 0) {
                ForEach(tabs, id: \.self) { tab in
                    let selected = selectedTab == tab
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 20, weight: selected ? .semibold : .regular))
                                .accessibilityHidden(true)
                            Text(classicUI ? tab.neonTitle : tab.title)
                                .font(
                                    classicUI
                                        ? .system(size: 10, weight: .semibold, design: .monospaced)
                                        : .system(size: 10, weight: selected ? .semibold : .medium)
                                )
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(itemColor(selected: selected))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .padding(.bottom, 6)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .combine)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 4)
            .background(barBackground.ignoresSafeArea(edges: .bottom))
        }
    }

    private var barBackground: Color {
        if classicUI, let palette {
            return palette.panel
        }
        return Color(.secondarySystemBackground)
    }

    private func itemColor(selected: Bool) -> Color {
        if classicUI, let palette {
            return selected ? palette.accent : palette.secondaryText
        }
        return selected ? Color.accentColor : Color.secondary
    }
}

#Preview {
    ContentView(viewModel: WalletViewModel())
}
