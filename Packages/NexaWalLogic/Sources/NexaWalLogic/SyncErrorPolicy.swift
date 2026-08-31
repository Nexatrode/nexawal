import Foundation

public enum SyncErrorKind: Equatable {
    case stalled
    case nodeUnreachable
    case failed
}

/// Keeps local/cache/protocol failures from being presented as node outages.
public enum SyncErrorPolicy {
    public static func classify(message: String, stalled: Bool = false) -> SyncErrorKind {
        let lower = message.lowercased()
        if stalled || lower.contains("sync stalled") || lower.contains("no scan progress") {
            return .stalled
        }

        let transportPatterns = [
            "connection refused",
            "connection reset",
            "connection timed out",
            "timed out",
            "timeout/disconnect",
            "failed to connect",
            "could not connect",
            "couldn't connect",
            "network is unreachable",
            "node unreachable",
            "not reachable",
            "no route to host",
            "name or service not known",
            "transport error",
            "dns",
            "tls handshake",
        ]
        return transportPatterns.contains(where: lower.contains) ? .nodeUnreachable : .failed
    }
}
