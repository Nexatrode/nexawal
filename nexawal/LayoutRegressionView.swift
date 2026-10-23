#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Isolated UI fixture: no terms acceptance, stored wallet, Keychain unlock, or sync.
/// It renders the real forms with an unopened/zero-balance model, so it cannot send.
enum LayoutRegressionMode {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--ui-layout-regression") }
}

struct LayoutRegressionView: View {
    @StateObject private var model = WalletViewModel()
    @State private var selectedTab: MainTab = .send
    @State private var neon = false
    @State private var sessionRevision = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Layout test · no wallet loaded")
                Spacer()
                Menu("Test controls") {
                    ForEach([MainTab.wallet, .receive, .send, .settings], id: \.self) { tab in
                        Button(tab.title) { selectedTab = tab }
                    }
                    Toggle("Techno Theme", isOn: $neon)
                    Button("New test session") { sessionRevision += 1 }
                }
            }
            .font(.caption)
            .padding(8)
            MainTabView(viewModel: model, selectedTab: $selectedTab)
                .id(sessionRevision)
        }
        .classicTheme(enabled: neon, colorScheme: colorScheme)
    }
}
#endif
