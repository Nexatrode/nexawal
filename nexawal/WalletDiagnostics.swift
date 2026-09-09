import Foundation

/// Never emits wallet data in release builds. Developer diagnostics are opt-in even in Debug.
enum WalletDiagnostics {
    nonisolated static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["NEXAWAL_DIAGNOSTICS"] == "1" else { return }
        Swift.print(message())
        #endif
    }
}
