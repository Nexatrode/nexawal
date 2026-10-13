import Foundation

/// Shared by UI and native manager. Lock invalidation and native restoration are linearized.
/// Only synchronous key/state mutations belong in withCurrent; never hold it across await/RPC.
public final class WalletSessionAuthority: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var generation: UInt64 = 0
    public init() {}
    public func token() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        return generation
    }
    public func invalidate() {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1
    }
    public func accepts(_ token: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return token == generation
    }
    public func check(_ token: UInt64) throws {
        guard accepts(token), !Task.isCancelled else { throw CancellationError() }
    }
    public func withCurrent<T>(_ token: UInt64, _ operation: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        try check(token)
        return try operation()
    }
}
