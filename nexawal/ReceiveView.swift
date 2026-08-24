import SwiftUI
import CoreImage.CIFilterBuiltins
import NexaWalLogic

struct ReceiveView: View {
    @ObservedObject var viewModel: WalletViewModel
    @ObservedObject private var fiatPrices = FiatPriceService.shared

    @State private var amountInput: String = ""
    @State private var amountInputMode: AmountInputMode = .xmr
    @State private var descriptionInput: String = ""
    @State private var showCopyConfirmation: Bool = false
    @State private var copyConfirmationText: String = L10n.t("Address copied to clipboard")
    @State private var showShareSheet: Bool = false

    // Subaddress UI
    @State private var showCreateSubaddressPrompt: Bool = false
    @State private var newSubaddressLabel: String = ""

    @Environment(\.classicUI) private var classicUI
    @Environment(\.classicPalette) private var classicPalette
    @Environment(\.colorScheme) private var colorScheme

    private let addressFont = Font.system(.caption, design: .monospaced)

    private var qrQuietZoneBackground: Color {
        if classicUI {
            return classicPalette?.background ?? .black
        }
        return colorScheme == .dark ? Color(.secondarySystemBackground) : .white
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    qrSection
                    amountSection
                    actionSection
                    subaddressSection
                    if showCopyConfirmation {
                        copyConfirmation
                    }
                }
                .padding()
            }
            .navigationTitle(classicUI ? L10n.t("Receive XMR").uppercased() : L10n.t("Receive XMR"))
            .navigationBarTitleDisplayMode(.inline)
            .background((classicPalette?.background ?? Color(.systemBackground)).ignoresSafeArea())
            .tint(classicPalette?.accent ?? .accentColor)
            .scrollContentBackground(classicUI ? .hidden : .automatic)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(classicUI ? L10n.t("Receive XMR").uppercased() : L10n.t("Receive XMR"))
                        .font(classicUI ? .system(.headline, design: .monospaced).weight(.bold) : .headline)
                        .foregroundStyle(classicPalette?.primaryText ?? .primary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        copyAddress()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .foregroundStyle(classicPalette?.accent ?? .accentColor)
                    .accessibilityLabel(L10n.t("Copy Address"))
                    .accessibilityAddTraits(.isButton)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityView(activityItems: [moneroURI])
            }
        }
        .onAppear {
            Task { await viewModel.loadReceiveSubaddresses() }
        }
        .alert("New address label (optional)", isPresented: $showCreateSubaddressPrompt) {
            TextField("Label", text: $newSubaddressLabel)
                .accessibilityLabel(L10n.t("Label"))
            Button("Cancel", role: .cancel) {
                newSubaddressLabel = ""
            }
            Button("Create") {
                let label = newSubaddressLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                newSubaddressLabel = ""
                Task { await viewModel.createNewReceiveSubaddress(label: label) }
            }
        } message: {
            Text("A new receive address (subaddress) will be generated for privacy.")
        }
    }

    private var subaddressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Receive Address")
                .font(classicUI ? .system(.headline, design: .monospaced).weight(.bold) : .headline)
                .foregroundStyle(classicPalette?.primaryText ?? .primary)

            if viewModel.receiveSubaddresses.isEmpty {
                Text("Loading addresses…")
                    .font(.caption)
                    .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Address", selection: $viewModel.selectedReceiveSubaddressIndex) {
                        ForEach(viewModel.receiveSubaddresses, id: \.subaddressIndex) { e in
                            let label = e.label.trimmingCharacters(in: .whitespacesAndNewlines)
                            let title = label.isEmpty ? L10n.format("Subaddress %lld", Int64(e.subaddressIndex)) : label
                            Text(title).tag(e.subaddressIndex)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(classicPalette?.accent ?? .accentColor)

                    if classicUI, let palette = classicPalette {
                        Button {
                            showCreateSubaddressPrompt = true
                        } label: {
                            Label("New Address", systemImage: "plus.circle")
                        }
                        .buttonStyle(NeonSecondaryButtonStyle(palette: palette))
                    } else {
                        Button {
                            showCreateSubaddressPrompt = true
                        } label: {
                            Label("New Address", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var qrSection: some View {
        VStack(spacing: 16) {
            QRCodeView(message: moneroURI)
                .background(qrQuietZoneBackground)
                .cornerRadius(classicUI ? 4 : 12)
                .overlay(
                    RoundedRectangle(cornerRadius: classicUI ? 4 : 12)
                        .stroke(classicPalette?.border ?? Color.clear, lineWidth: classicUI ? 1 : 0)
                )
                .shadow(color: (classicUI || colorScheme == .dark) ? .clear : Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                .accessibilityLabel(L10n.t("Monero receive QR"))

            Text(moneroURI)
                .font(addressFont)
                .multilineTextAlignment(.leading)
                .foregroundColor(classicPalette?.primaryText ?? .primary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(classicPalette?.panel ?? Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: classicUI ? 4 : 8)
                        .stroke(classicPalette?.border ?? Color.clear, lineWidth: classicUI ? 1 : 0)
                )
                .cornerRadius(classicUI ? 4 : 8)
                .textSelection(.enabled)
        }
    }

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.neon("Payment Request (optional)", classicUI: classicUI))
                .font(classicUI ? .system(.headline, design: .monospaced).weight(.bold) : .headline)
                .foregroundColor(classicPalette?.primaryText ?? .primary)

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("Amount"))
                        .font(classicUI ? .system(.subheadline, design: .monospaced) : .subheadline)
                        .foregroundColor(classicPalette?.secondaryText ?? .secondary)
                    AmountUnitField(
                        text: $amountInput,
                        mode: $amountInputMode,
                        rate: fiatPrices.displayRate,
                        placeholder: "0.0000",
                        accessibilityLabel: L10n.t("Amount"),
                        classicUI: classicUI,
                        classicPalette: classicPalette
                    )
                    .padding(12)
                    .background(classicPalette?.panel ?? Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: classicUI ? 4 : 8)
                            .stroke(classicPalette?.border ?? Color.clear, lineWidth: classicUI ? 1 : 0)
                    )
                    .cornerRadius(classicUI ? 4 : 8)
                    if let piconero = AmountUnitParsing.piconero(
                        text: amountInput,
                        mode: amountInputMode,
                        rate: fiatPrices.displayRate
                    ),
                       let secondary = AmountUnitParsing.secondaryLine(
                        piconero: piconero,
                        mode: amountInputMode,
                        rate: fiatPrices.displayRate
                       ) {
                        Text(secondary)
                            .font(classicUI ? .system(.caption, design: .monospaced) : .caption)
                            .foregroundColor(classicPalette?.secondaryText ?? .secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(classicUI ? .system(.subheadline, design: .monospaced) : .subheadline)
                        .foregroundColor(classicPalette?.secondaryText ?? .secondary)
                    TextField("Note for the payer", text: $descriptionInput)
                        .textInputAutocapitalization(.sentences)
                        .disableAutocorrection(true)
                        .foregroundColor(classicPalette?.primaryText)
                        .padding(12)
                        .background(classicPalette?.panel ?? Color(.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: classicUI ? 4 : 8)
                                .stroke(classicPalette?.border ?? Color.clear, lineWidth: classicUI ? 1 : 0)
                        )
                        .cornerRadius(classicUI ? 4 : 8)
                        .accessibilityLabel(L10n.t("Description"))
                }
            }
        }
        .padding()
        .background(classicPalette?.panel ?? Color(.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: classicUI ? 4 : 16)
                .stroke(classicPalette?.border ?? Color.clear, lineWidth: classicUI ? 1 : 0)
        )
        .cornerRadius(classicUI ? 4 : 16)
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            if classicUI, let palette = classicPalette {
                if #available(iOS 16.0, *) {
                    ShareLink(item: moneroURI) {
                        Label("Share Payment Link", systemImage: "square.and.arrow.up")
                            .neonSecondaryButtonStyle(classicUI: true, palette: palette)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("Share Payment Link"))
                } else {
                    Button {
                        showShareSheet = true
                    } label: {
                        Label("Share Payment Link", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(NeonSecondaryButtonStyle(palette: palette))
                    .accessibilityLabel(L10n.t("Share Payment Link"))
                }

                Button(action: copyAddress) {
                    Label("Copy Address", systemImage: "doc.on.doc")
                        .neonCTAStyle(classicUI: true, palette: palette)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("Copy Address"))
            } else {
                if #available(iOS 16.0, *) {
                    ShareLink(item: moneroURI) {
                        Label("Share Payment Link", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(L10n.t("Share Payment Link"))
                } else {
                    Button {
                        showShareSheet = true
                    } label: {
                        Label("Share Payment Link", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(L10n.t("Share Payment Link"))
                }

                Button(action: copyAddress) {
                    Label("Copy Address", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(L10n.t("Copy Address"))
            }
        }
    }

    private var copyConfirmation: some View {
        Text(copyConfirmationText)
            .font(classicUI ? .system(.footnote, design: .monospaced) : .footnote)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background((classicPalette?.success ?? .green).opacity(0.15))
            .foregroundColor(classicPalette?.success ?? .green)
            .cornerRadius(8)
            .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var moneroURI: String {
        let descriptor = descriptionInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return MoneroPaymentURI.build(
            address: viewModel.currentReceiveAddress(),
            amountXmr: sanitizedAmountString,
            description: descriptor.isEmpty ? nil : descriptor
        )
    }

    private var sanitizedAmountString: String? {
        guard let piconero = AmountUnitParsing.piconero(
            text: amountInput,
            mode: amountInputMode,
            rate: fiatPrices.displayRate
        ), piconero > 0 else {
            return nil
        }
        return FiatEstimate.formatXmrForInput(piconero: piconero)
    }

    private func copyAddress() {
        flashCopyConfirmation(
            text: viewModel.currentReceiveAddress(),
            message: L10n.t("Address copied to clipboard")
        )
    }

    private func flashCopyConfirmation(text: String, message: String) {
        UIPasteboard.general.string = text
        copyConfirmationText = message
        withAnimation {
            showCopyConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showCopyConfirmation = false
            }
        }
    }
}

// MARK: - QR Code Rendering

private struct QRCodeView: View {
    let message: String
    var maxSide: CGFloat = 320
    @Environment(\.classicUI) private var classicUI
    @Environment(\.classicPalette) private var classicPalette
    @Environment(\.colorScheme) private var colorScheme

    private static let context = CIContext()
    private static let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        GeometryReader { proxy in
            let side = min(min(proxy.size.width, proxy.size.height), maxSide)
            Group {
                if let image = generateQRCode(for: message, side: max(side, 1)) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: side, height: side)
                } else {
                    Color.secondary
                        .overlay(
                            Image(systemName: "xmark.octagon")
                                .font(.largeTitle)
                                .foregroundColor(.white)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(width: side, height: side)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: maxSide, maxHeight: maxSide)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 200)
    }

    private func generateQRCode(for string: String, side: CGFloat) -> UIImage? {
        guard !string.isEmpty else { return nil }
        let data = Data(string.utf8)
        QRCodeView.filter.setValue(data, forKey: "inputMessage")
        QRCodeView.filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = QRCodeView.filter.outputImage else {
            return nil
        }

        let extent = max(outputImage.extent.size.width, 1)
        let scale = max(side / extent, 10)
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let colored: CIImage
        if classicUI, let palette = classicPalette {
            // Neon modules on matching background (scannable green-on-black / dark-green-on-light).
            let falseColor = CIFilter.falseColor()
            falseColor.inputImage = scaledImage
            falseColor.color0 = CIColor(color: UIColor(palette.accent)) // QR modules (was black)
            falseColor.color1 = CIColor(color: UIColor(palette.background)) // quiet zone (was white)
            colored = falseColor.outputImage ?? scaledImage
        } else if colorScheme == .dark {
            // Regular dark mode: light modules on dark quiet zone (not a white tile).
            let falseColor = CIFilter.falseColor()
            falseColor.inputImage = scaledImage
            falseColor.color0 = CIColor(color: .label)
            falseColor.color1 = CIColor(color: .secondarySystemBackground)
            colored = falseColor.outputImage ?? scaledImage
        } else {
            colored = scaledImage
        }

        guard let cgImage = QRCodeView.context.createCGImage(colored, from: colored.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
