import Foundation

/// Public, untrusted explorer observation. Never used for wallet balance/send decisions.
public struct ExplorerObservation: Decodable, Sendable {
    public let api_version: Int
    public let network: String
    public let txid: String
    public let status: String
    public let fee_piconero: String?
    public let block_height: UInt64?
    public let block_hash: String?
    public let block_timestamp: UInt64?
    public let confirmations: UInt64
    public let chain_height: UInt64
    public let tip_hash: String
    public let node_ready: Bool
    public let observed_at: UInt64

    public static func validID(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    public static func parse(_ data: Data, txid: String, now: UInt64) throws -> Self {
        guard data.count <= 16_384, validID(txid) else { throw URLError(.cannotParseResponse) }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.api_version == 1, value.network == "mainnet", value.txid == txid,
              validID(value.tip_hash), value.chain_height > 0,
              value.observed_at > 0, value.observed_at <= now + 120,
              now <= value.observed_at + 300 else { throw URLError(.cannotParseResponse) }
        if let fee = value.fee_piconero {
            guard !fee.isEmpty, fee.utf8.count <= 20, fee.utf8.allSatisfy({ (48...57).contains($0) }), UInt64(fee) != nil else { throw URLError(.cannotParseResponse) }
        }
        switch value.status {
        case "pending":
            guard value.block_height == nil, value.block_hash == nil, value.block_timestamp == nil, value.confirmations == 0 else { throw URLError(.cannotParseResponse) }
        case "confirmed":
            guard let height = value.block_height, height < value.chain_height,
                  value.confirmations == value.chain_height - height,
                  let hash = value.block_hash, validID(hash),
                  let time = value.block_timestamp, time > 0, time <= now + 600 else { throw URLError(.cannotParseResponse) }
        default: throw URLError(.cannotParseResponse)
        }
        return value
    }
}
