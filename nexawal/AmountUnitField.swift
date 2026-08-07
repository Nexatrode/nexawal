import SwiftUI
import NexaWalLogic

enum AmountInputMode: Equatable {
    case xmr
    case fiat
}

/// Amount text field with optional XMR ⇄ fiat swap when a live rate is available.
struct AmountUnitField: View {
    @Binding var text: String
    @Binding var mode: AmountInputMode
    let rate: FiatRate?
    var placeholder: String = "0.0"
    var accessibilityLabel: String = "Amount"
    var classicUI: Bool = false
    var classicPalette: ClassicPalette? = nil

    private var swapAvailable: Bool { rate != nil }

    private var unitLabel: String {
        switch mode {
        case .xmr: return "XMR"
        case .fiat: return rate?.currency ?? "USD"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(classicPalette?.primaryText ?? .primary)
                .accessibilityLabel(accessibilityLabel)

            Text(unitLabel)
                .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                .font(classicUI ? .system(.body, design: .monospaced) : .body)

            if swapAvailable {
                Button(action: swapUnits) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(classicPalette?.accent ?? Color.accentColor)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    L10n.format("Switch between XMR and %@", rate?.currency ?? "USD")
                )
            }
        }
        .onChange(of: rate?.currency) { _, _ in
            // If rate disappears while in fiat mode, fall back to XMR.
            if rate == nil, mode == .fiat {
                forceXmrPreservingValue()
            }
        }
        .onChange(of: rate == nil) { _, isNil in
            if isNil, mode == .fiat {
                forceXmrPreservingValue()
            }
        }
    }

    private func swapUnits() {
        guard let rate else { return }
        let pico = resolvedPiconero(rate: rate)
        switch mode {
        case .xmr:
            if let pico {
                text = FiatEstimate.formatFiatForInput(piconero: pico, rate: rate)
            }
            mode = .fiat
        case .fiat:
            if let pico {
                text = FiatEstimate.formatXmrForInput(piconero: pico)
            }
            mode = .xmr
        }
    }

    private func forceXmrPreservingValue() {
        if let rate, let pico = FiatEstimate.piconeroFromFiat(fiatText: text, rate: rate) {
            text = FiatEstimate.formatXmrForInput(piconero: pico)
        }
        mode = .xmr
    }

    private func resolvedPiconero(rate: FiatRate) -> UInt64? {
        switch mode {
        case .xmr:
            return XmrAmount.parsePiconero(text)
        case .fiat:
            return FiatEstimate.piconeroFromFiat(fiatText: text, rate: rate)
        }
    }
}

enum AmountUnitParsing {
    static func piconero(text: String, mode: AmountInputMode, rate: FiatRate?) -> UInt64? {
        switch mode {
        case .xmr:
            return XmrAmount.parsePiconero(text)
        case .fiat:
            guard let rate else { return nil }
            return FiatEstimate.piconeroFromFiat(fiatText: text, rate: rate)
        }
    }

    static func secondaryLine(piconero: UInt64?, mode: AmountInputMode, rate: FiatRate?) -> String? {
        guard let piconero else { return nil }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        switch mode {
        case .xmr:
            return FiatEstimate.liveApproxText(piconero: piconero, rate: rate, nowMs: now)
        case .fiat:
            return FiatEstimate.formatXmrApprox(piconero: piconero)
        }
    }
}
