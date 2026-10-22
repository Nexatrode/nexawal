import SwiftUI

/// Blocking first-run / re-accept gate for NexaWal terms.
/// Shown when `MoneroConfig.acceptedTermsVersion < MoneroConfig.currentTermsVersion`.
struct TermsAcceptanceView: View {
    var onAccepted: () -> Void

    @State private var hasCheckedAgree = false
    @State private var termsMarkdown = LegalDocumentView.loadMarkdown(named: "terms")
    @Environment(\.classicUI) private var classicUI
    @Environment(\.classicPalette) private var classicPalette

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.t("Terms of Use"))
                        .font(classicUI ? .system(.title2, design: .monospaced).weight(.bold) : .title2.bold())
                        .foregroundStyle(classicPalette?.primaryText ?? .primary)

                    Text(L10n.t("nexawal by Nexatrode LLC is a self-custodial interface for managing digital assets. You hold exclusive responsibility for your private keys and 25-word seed phrase."))
                        .font(classicUI ? .system(.body, design: .monospaced) : .body)
                        .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(L10n.t("The app is provided as is, with no warranties express or implied. Use is at your own risk. Nexatrode LLC is not liable for lost assets, user errors, downtime, or issues with third-party services or nodes."))
                        .font(classicUI ? .system(.body, design: .monospaced) : .body)
                        .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(L10n.t("Running or connecting to your own Monero node is recommended. Public defaults are for convenience only."))
                        .font(classicUI ? .system(.body, design: .monospaced) : .body)
                        .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    LegalMarkdownContent(markdown: termsMarkdown)

                    Toggle(isOn: $hasCheckedAgree) {
                        Text(L10n.t("I have read and agree to the Terms of Use"))
                            .font(classicUI ? .system(.body, design: .monospaced) : .body)
                            .foregroundStyle(classicPalette?.primaryText ?? .primary)
                    }
                    .disabled(termsMarkdown.isEmpty)
                    .toggleStyle(.switch)
                    .tint(classicPalette?.accent ?? Color.accentColor)
                    .padding(.top, 8)
                }
                .padding(24)
            }

            VStack(spacing: 12) {
                Button {
                    MoneroConfig.acceptCurrentTerms()
                    onAccepted()
                } label: {
                    Text(L10n.t("I Agree"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasCheckedAgree || termsMarkdown.isEmpty)
                .opacity(hasCheckedAgree ? 1 : 0.45)

                Button(role: .destructive) {
                    // Decline: leave the gate up and exit the process.
                    exit(0)
                } label: {
                    Text(L10n.t("Quit"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background((classicPalette?.background ?? Color(.systemBackground)).ignoresSafeArea())
        .interactiveDismissDisabled(true)
    }
}
