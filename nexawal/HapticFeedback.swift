import UIKit

/// Small, optional tactile cues for deliberate user actions.
/// No audio is produced; UIKit leaves haptics subject to the user's system settings.
@MainActor
enum AppHaptics {
    static let setting = MoneroConfig.userDefaultsHapticFeedbackKey

    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: setting) as? Bool
            ?? MoneroConfig.defaultHapticFeedbackEnabled
    }

    static func light() {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func failure() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
