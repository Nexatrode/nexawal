import SwiftUI

enum LegalDocumentKind {
    case terms
    case privacy
    case license

    var resourceName: String {
        switch self {
        case .terms: return "terms"
        case .privacy: return "privacy"
        case .license: return "license"
        }
    }

    var titleKey: String.LocalizationValue {
        switch self {
        case .terms: return "Terms of Use"
        case .privacy: return "Privacy policy"
        case .license: return "MIT License"
        }
    }
}

/// Offline Markdown reader for bundled Terms / Privacy / MIT License (nexawal/Legal/*.md).
struct LegalDocumentView: View {
    let kind: LegalDocumentKind
    var onClose: (() -> Void)? = nil

    @Environment(\.classicUI) private var classicUI
    @Environment(\.classicPalette) private var classicPalette
    @Environment(\.dismiss) private var dismiss

    private var markdown: String {
        Self.loadMarkdown(named: kind.resourceName)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(SimpleMarkdown.parse(markdown).enumerated()), id: \.offset) { _, block in
                        switch block {
                        case let .heading(level, text):
                            Text(text)
                                .font(headingFont(level))
                                .foregroundStyle(classicPalette?.primaryText ?? .primary)
                                .padding(.top, level <= 2 ? 8 : 4)
                        case let .bullet(text):
                            Text("• \(text)")
                                .font(bodyFont)
                                .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                        case let .paragraph(text):
                            Text(text)
                                .font(bodyFont)
                                .foregroundStyle(classicPalette?.secondaryText ?? .secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background((classicPalette?.background ?? Color(.systemBackground)).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(L10n.t(kind.titleKey))
                        .font(classicUI ? .system(.headline, design: .monospaced).weight(.bold) : .headline)
                        .foregroundStyle(classicPalette?.primaryText ?? .primary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("Close")) {
                        if let onClose {
                            onClose()
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundStyle(classicPalette?.accent ?? Color.accentColor)
                }
            }
        }
    }

    private var bodyFont: Font {
        classicUI ? .system(.body, design: .monospaced) : .body
    }

    private func headingFont(_ level: Int) -> Font {
        let size: Font.TextStyle = level == 1 ? .title2 : (level == 2 ? .title3 : .headline)
        return classicUI
            ? .system(size, design: .monospaced).weight(.bold)
            : .system(size).weight(.bold)
    }

    private static func loadMarkdown(named name: String) -> String {
        if let url = Bundle.main.url(forResource: name, withExtension: "md", subdirectory: "Legal"),
           let text = try? String(contentsOf: url, encoding: .utf8)
        {
            return text
        }
        // Filesystem-synced groups sometimes flatten resources to the bundle root.
        if let url = Bundle.main.url(forResource: name, withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8)
        {
            return text
        }
        return ""
    }
}

enum SimpleMarkdown {
    enum Block {
        case heading(level: Int, text: String)
        case bullet(String)
        case paragraph(String)
    }

    static func parse(_ source: String) -> [Block] {
        var out: [Block] = []
        var para = ""
        func flush() {
            let text = para.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                out.append(.paragraph(text))
            }
            para = ""
        }
        for raw in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
            } else if trimmed.hasPrefix("### ") {
                flush()
                out.append(.heading(level: 3, text: String(trimmed.dropFirst(4))))
            } else if trimmed.hasPrefix("## ") {
                flush()
                out.append(.heading(level: 2, text: String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("# ") {
                flush()
                out.append(.heading(level: 1, text: String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("- ") {
                flush()
                out.append(.bullet(String(trimmed.dropFirst(2))))
            } else {
                if !para.isEmpty { para += " " }
                para += trimmed
            }
        }
        flush()
        return out
    }
}
