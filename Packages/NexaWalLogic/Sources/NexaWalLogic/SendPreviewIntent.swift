import Foundation

/// An estimate authorizes only this payment, wallet session and network route.
public struct SendPreviewIntent: Equatable, Sendable {
    public let destination: String
    public let amount: UInt64?
    public let session: String
    public let node: String
    public let source: UInt32?
    public let maximum: Bool
    public init(destination: String, amount: UInt64?, session: String, node: String, source: UInt32?, maximum: Bool) {
        self.destination = destination; self.amount = amount; self.session = session
        self.node = node; self.source = source; self.maximum = maximum
    }
}
