import Foundation

/// A manual rescan belongs to one authenticated session, including cancellation/join and
/// final UI cleanup. A late continuation must never mutate a locked or replacement session.
@MainActor
public enum WalletRescanLifecycle {
    public static func run<Status>(
        authority: WalletSessionAuthority,
        token: UInt64,
        cancelRefresh: () async -> Void,
        begin: () -> Void,
        scan: () async throws -> Status,
        finish: (Status) async throws -> Void,
        cleanup: () -> Void,
        failure: (Error) -> Void
    ) async {
        do {
            try authority.check(token)
            await cancelRefresh()
            try authority.check(token)
            begin()
            defer {
                // Do not tear down polling/flags owned by a newer session. Cancellation
                // within this same session still requires cleanup.
                if authority.accepts(token) { cleanup() }
            }
            let status = try await scan()
            try authority.check(token)
            try await finish(status)
        } catch is CancellationError {
            // Locking, replacement, or task cancellation is not a rescan failure dialog.
        } catch {
            guard authority.accepts(token), !Task.isCancelled else { return }
            failure(error)
        }
    }
}
