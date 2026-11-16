import SwiftUI
import UIKit
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
            .formKeyboardDismissal()
            .frame(width: region.width, height: region.height)
            .position(x: region.midX, y: region.midY)
        }
    }

    private func divisions(in proxy: GeometryProxy) -> [CGRect] {
#if !targetEnvironment(macCatalyst)
        if #available(iOS 27.1, *) {
            return proxy.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed).map { region in
                let frame = region.frame
                let margins = region.margins
                return CGRect(x: frame.minX - margins.leading, y: frame.minY - margins.top,
                              width: frame.width + margins.leading + margins.trailing,
                              height: frame.height + margins.top + margins.bottom)
            }
        }
#endif
        return []
    }
}

extension View {
    /// Dismiss from non-editable form space without capturing field/control taps.
    func formKeyboardDismissal() -> some View {
        modifier(FormKeyboardDismissal())
    }
}

private struct FormKeyboardDismissal: ViewModifier {
    @State private var softwareKeyboardVisible = false

    func body(content: Content) -> some View {
#if targetEnvironment(macCatalyst)
        content
#else
        content
            .background(FormBackgroundTapObserver().allowsHitTesting(false))
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                if softwareKeyboardVisible {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(L10n.t("Done")) {
                            UIApplication.shared.sendAction(
                                #selector(UIResponder.resignFirstResponder),
                                to: nil, from: nil, for: nil
                            )
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                // Hardware keyboards and iPhone Mirroring must not leave a Done
                // button floating in the app when no software keyboard is shown.
                softwareKeyboardVisible = (frame?.height ?? 0) > 100
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                softwareKeyboardVisible = false
            }
#endif
    }
}

/// Observe taps passively, scoped to the form viewport. A SwiftUI gesture on the
/// whole form would also run when focusing a field or using native navigation.
private struct FormBackgroundTapObserver: UIViewRepresentable {
    func makeUIView(context: Context) -> TapRegion { TapRegion() }
    func updateUIView(_ uiView: TapRegion, context: Context) {}

    final class TapRegion: UIView, UIGestureRecognizerDelegate {
        private weak var observedWindow: UIWindow?
        private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))

        override func didMoveToWindow() {
            super.didMoveToWindow()
            observedWindow?.removeGestureRecognizer(tap)
            observedWindow = window
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            window?.addGestureRecognizer(tap)
        }

        @objc private func dismissKeyboard() { window?.endEditing(true) }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard window != nil, bounds.contains(touch.location(in: self)) else { return false }
            var touchedView = touch.view
            while let view = touchedView {
                if view is UITextField || view is UITextView || view is UIControl || view is UISearchBar {
                    return false
                }
                touchedView = view.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }
}
