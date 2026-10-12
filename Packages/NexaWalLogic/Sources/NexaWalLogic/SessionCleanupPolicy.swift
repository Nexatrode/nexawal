import Foundation

/// Used only on the manager actor. Close dominates any later seal/resume request.
public struct SessionCleanupIntent {
    public private(set) var close = false
    public private(set) var continueRefresh = false
    public init() {}
    public mutating func request(close: Bool, continueRefresh: Bool) {
        self.close = self.close || close
        self.continueRefresh = !self.close && continueRefresh
    }
}

/// Retry only the native "worker still busy" result. Never mistake a timeout for sealed keys.
public enum SessionCleanupPolicy {
    public static func complete(
        retryDelayNanoseconds: UInt64 = 1_000_000_000,
        isRetryable: (Error) -> Bool,
        operation: () throws -> Void
    ) async throws {
        while true {
            do { try operation(); return }
            catch {
                guard isRetryable(error) else { throw error }
                // Cancellation must not silently abandon cleanup. The manager owns this task,
                // independently of any screen/unlock caller that awaits it.
                try await Task.sleep(nanoseconds: retryDelayNanoseconds)
            }
        }
    }
}
