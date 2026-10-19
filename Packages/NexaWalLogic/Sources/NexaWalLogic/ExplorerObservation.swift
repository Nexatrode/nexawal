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
    public let double_spend_seen: Bool?
    public let details: ExplorerAdvanced?

    public static func validID(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    public static func parse(_ data: Data, txid: String, now: UInt64, page: UInt64? = nil) throws -> Self {
        guard data.count <= (page == nil ? 16_384 : 65_536), validID(txid) else { throw URLError(.cannotParseResponse) }
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
        guard (page == nil) == (value.details == nil) else { throw URLError(.cannotParseResponse) }
        if let details = value.details, let page { try details.validate(page: page, now: now, pending: value.status == "pending") }
        return value
    }
}

public struct ExplorerAdvanced: Decodable, Sendable {
    public struct Input: Decodable, Sendable {
        public let index: UInt64
        public let key_image: String
        public let ring_size: UInt64
        public let absolute_indices: [String]
        public let indices_truncated: Bool
    }
    public struct Output: Decodable, Sendable {
        public let index: UInt64
        public let key: String
        public let public_amount_piconero: String?
        public let view_tag: UInt8?
        public let global_index: String?
    }
    public let page: UInt64
    public let page_size: UInt64
    public let page_count: UInt64
    public let version: UInt8
    public let coinbase: Bool
    public let serialized_size_bytes: UInt64?
    public let downloaded_size_bytes: UInt64
    public let weight: UInt64?
    public let unlock_kind: String
    public let unlock_value: String
    public let input_count: UInt64
    public let output_count: UInt64
    public let inputs: [Input]
    public let outputs: [Output]
    public let extra_hex: String
    public let extra_truncated: Bool
    public let received_timestamp: UInt64?

    public static func unsigned(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.count <= 20 && s.utf8.allSatisfy { (48...57).contains($0) } && UInt64(s) != nil
    }
    fileprivate func validate(page requested: UInt64, now: UInt64, pending: Bool) throws {
        func check(_ value: Bool) throws { if !value { throw URLError(.cannotParseResponse) } }
        try check(page == requested && page_size == 10 && input_count > 0 && input_count <= 4096 && output_count > 0 && output_count <= 4096)
        try check(page_count == (max(input_count, output_count) + 9) / 10 && page < page_count && (version == 1 || version == 2))
        try check(!coinbase || input_count == 1)
        let start = page * 10
        let count = coinbase ? 0 : input_count
        try check(inputs.count == Int(min(10, count > start ? count - start : 0)))
        try check(outputs.count == Int(min(10, output_count > start ? output_count - start : 0)))
        for (i, row) in inputs.enumerated() {
            try check(row.index == start + UInt64(i) && ExplorerObservation.validID(row.key_image) && row.ring_size > 0 && row.ring_size <= 1_048_576)
            try check(row.absolute_indices.count == Int(min(row.ring_size, 128)) && row.indices_truncated == (row.ring_size > 128))
            var previous: UInt64?
            for raw in row.absolute_indices {
                try check(Self.unsigned(raw))
                let index = UInt64(raw)!
                if let previous { try check(index > previous) }
                previous = index
            }
        }
        for (i, row) in outputs.enumerated() {
            try check(row.index == start + UInt64(i) && ExplorerObservation.validID(row.key))
            if let raw = row.global_index { try check(Self.unsigned(raw)) }
            if let raw = row.public_amount_piconero { try check(Self.unsigned(raw)) }
            try check((row.public_amount_piconero == nil) == (version == 2 && !coinbase))
        }
        try check(downloaded_size_bytes > 0 && downloaded_size_bytes <= 1_048_576)
        if let size = serialized_size_bytes { try check(size == downloaded_size_bytes) }
        if let weight { try check(weight > 0 && weight <= 4_194_304 && serialized_size_bytes != nil) }
        try check(Self.unsigned(unlock_value))
        let unlock = UInt64(unlock_value)!
        try check((unlock_kind == "none" && unlock == 0) || (unlock_kind == "height" && unlock > 0 && unlock < 500_000_000) || (unlock_kind == "timestamp" && unlock >= 500_000_000))
        try check(extra_hex.utf8.count <= 4096 && extra_hex.utf8.count % 2 == 0 && extra_hex.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) })
        try check(!extra_truncated || extra_hex.utf8.count == 4096)
        if let time = received_timestamp { try check(pending && time > 0 && time <= now + 120) }
    }
}
