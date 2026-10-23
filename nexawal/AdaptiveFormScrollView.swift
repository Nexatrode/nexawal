import SwiftUI
import NexaWalLogic

/// Keep the same scroll/content identity while moving it clear of an active fold.
/// Ordinary phones, iPads, and older OS versions retain a full safe-area viewport.
struct AdaptiveFormScrollView<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let region = ContiguousLayoutRegion.resolve(
                bounds: CGRect(origin: .zero, size: proxy.size), divisions: divisions(in: proxy)
            )
            ScrollView {
                content()
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .frame(width: region.width, height: region.height)
            .position(x: region.midX, y: region.midY)
        }
    }

    private func divisions(in proxy: GeometryProxy) -> [CGRect] {
        if #available(iOS 27.1, *) {
            return proxy.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed).map { region in
                let frame = region.frame
                let margins = region.margins
                return CGRect(x: frame.minX - margins.leading, y: frame.minY - margins.top,
                              width: frame.width + margins.leading + margins.trailing,
                              height: frame.height + margins.top + margins.bottom)
            }
        }
        return []
    }
}
