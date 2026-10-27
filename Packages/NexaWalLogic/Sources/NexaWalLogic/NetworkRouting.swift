import Foundation

/// Pure network-policy helpers shared by Settings / WalletManager (no UserDefaults).
public enum NetworkRouting: Sendable {
    public static let defaultI2PRPCAddress = "7lfi73h743qm663hv4x5q6ccgc4jc5ncl65dfvpe665m6pawwdxa.b32.i2p"

    public enum ConfigurationError: LocalizedError {
        case invalidI2PNode, invalidI2PProxy
        public var errorDescription: String? {
            switch self {
            case .invalidI2PNode: return "Enter an HTTP I2P RPC address ending in .i2p, with a valid port (not the P2P address)."
            case .invalidI2PProxy: return "Enter an I2P HTTP proxy as host:port, usually 127.0.0.1:4444. SOCKS and HTTPS proxies are not supported."
            }
        }
    }

    public static func validateI2PConfiguration(nodeAddress: String, proxyAddress: String?) throws {
        guard let node = URLComponents(string: normalizeURL(nodeAddress)),
              node.scheme?.lowercased() == "http",
              let host = node.host?.lowercased(), host.hasSuffix(".i2p"),
              node.query == nil, node.fragment == nil,
              node.port.map({ (1...65535).contains($0) }) ?? true else {
            throw ConfigurationError.invalidI2PNode
        }
        let raw = proxyAddress?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let url = raw.contains("://") ? raw : "http://\(raw)"
        guard let proxy = URLComponents(string: url), proxy.scheme?.lowercased() == "http",
              let host = proxy.host, !host.isEmpty,
              let port = proxy.port, (1...65535).contains(port),
              proxy.user == nil, proxy.password == nil, proxy.query == nil, proxy.fragment == nil,
              proxy.path.isEmpty || proxy.path == "/" else {
            throw ConfigurationError.invalidI2PProxy
        }
    }

    public enum Policy: String, Sendable {
        case clearnet
        case i2p
        case hybrid

        public static func fromRaw(_ raw: String?) -> Policy {
            switch raw?.lowercased() {
            case "i2p": return .i2p
            case "hybrid": return .hybrid
            default: return .clearnet
            }
        }
    }

    public static func normalizeURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicit = explicitNodeURL(trimmed) {
            return explicit
        }
        // I2P / legacy host:port values have no scheme. Default those to http.
        return trimmed.isEmpty ? trimmed : "http://\(trimmed)"
    }

    /// Clearnet node field: user must type http:// or https://. No scheme guessing.
    public static func explicitNodeURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else {
            return nil
        }
        return trimmed
    }

    public static func scanNodeAddress(policy: Policy, clearnetNodeAddress: String, i2pRPCAddress: String) -> String {
        switch policy {
        case .clearnet, .hybrid:
            return clearnetNodeAddress
        case .i2p:
            return i2pRPCAddress
        }
    }

    public static func broadcastNodeAddress(policy: Policy, clearnetNodeAddress: String, i2pRPCAddress: String) -> String {
        switch policy {
        case .clearnet:
            return clearnetNodeAddress
        case .i2p, .hybrid:
            return i2pRPCAddress
        }
    }

    public static func scanNodeURL(policy: Policy, clearnetNodeURL: String, i2pRPCAddress: String) -> String {
        switch policy {
        case .clearnet, .hybrid:
            return clearnetNodeURL
        case .i2p:
            return normalizeURL(i2pRPCAddress)
        }
    }

    public static func broadcastNodeURL(policy: Policy, clearnetNodeURL: String, i2pRPCAddress: String) -> String {
        switch policy {
        case .clearnet:
            return clearnetNodeURL
        case .i2p, .hybrid:
            return normalizeURL(i2pRPCAddress)
        }
    }

    /// True when daemon RPC for this policy should go through the I2P HTTP proxy.
    public static func shouldUseI2PHTTPProxy(
        policy: Policy,
        proxyConfigured: Bool,
        forBroadcast: Bool
    ) -> Bool {
        guard proxyConfigured else { return false }
        switch policy {
        case .clearnet: return false
        case .i2p: return true
        case .hybrid: return forBroadcast
        }
    }
}
