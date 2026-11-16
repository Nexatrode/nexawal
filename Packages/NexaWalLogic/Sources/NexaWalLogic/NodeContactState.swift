import Foundation

/// Evidence of contact with the configured daemon, independent of wallet scanning.
/// A fresh observation is not proof of chain consensus or daemon honesty.
public struct NodeContactState: Sendable {
    public enum Status: Equatable, Sendable { case unknown, fresh, stale, unavailable }
    public private(set) var generation = UUID()
    public private(set) var lastSuccess: Date?
    private var probe: UUID?
    private var failed = false
    public var isChecking: Bool { probe != nil }

    public init() {}

    public func status(at now: Date) -> Status {
        if failed { return .unavailable }
        guard let lastSuccess else { return .unknown }
        let age = now.timeIntervalSince(lastSuccess)
        // Three missed minute-spaced observations, or a clock discontinuity.
        return age >= 0 && age <= 180 ? .fresh : .stale
    }

    public mutating func reset() { self = Self() }

    public mutating func beginProbe() -> UUID? {
        guard probe == nil else { return nil }
        let id = UUID()
        probe = id
        return id
    }

    public func accepts(_ id: UUID) -> Bool { probe == id }

    public mutating func cancel(probe id: UUID) {
        if accepts(id) { probe = nil }
    }

    public mutating func cancelProbe() { probe = nil }

    @discardableResult
    public mutating func succeed(probe id: UUID, at now: Date) -> Bool {
        guard accepts(id) else { return false }
        return recordSuccessfulContact(generation: generation, at: now)
    }

    @discardableResult
    public mutating func fail(probe id: UUID) -> Bool {
        guard accepts(id) else { return false }
        probe = nil
        failed = true
        return true
    }

    @discardableResult
    public mutating func recordSuccessfulContact(generation expected: UUID, at now: Date) -> Bool {
        guard expected == generation else { return false }
        probe = nil // A completed refresh supersedes any older tip observation.
        lastSuccess = now
        failed = false
        return true
    }
}
