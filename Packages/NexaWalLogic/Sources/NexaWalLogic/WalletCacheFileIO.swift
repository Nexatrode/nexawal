import Foundation

/// Crash-safe cache replacement and recoverable quarantine shared by iOS and Catalyst.
public enum WalletCacheFileIO {
    /// Returns `nil` only when the file is absent. Existing but unreadable or malformed
    /// JSON is surfaced to the caller so safety-critical recovery state cannot vanish.
    public static func loadJSONIfPresent<T: Decodable>(
        _ type: T.Type,
        from target: URL,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T? {
        guard FileManager.default.fileExists(atPath: target.path) else { return nil }
        return try decoder.decode(type, from: Data(contentsOf: target))
    }

    public static func writeAtomically(_ data: Data, to target: URL) throws {
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: target, options: .atomic)
    }

    /// Moves a rejected cache out of the active slot without deleting diagnostic evidence.
    /// Returns `nil` when the active cache no longer exists.
    @discardableResult
    public static func quarantineRejectedFile(
        at target: URL,
        timestampMilliseconds: UInt64 = UInt64(Date().timeIntervalSince1970 * 1_000)
    ) throws -> URL? {
        let manager = FileManager.default
        guard manager.fileExists(atPath: target.path) else { return nil }

        var attempt = 0
        while true {
            let collisionSuffix = attempt == 0 ? "" : "-\(attempt)"
            let candidate = URL(
                fileURLWithPath: target.path + ".rejected-\(timestampMilliseconds)\(collisionSuffix)"
            )
            if manager.fileExists(atPath: candidate.path) {
                attempt += 1
                continue
            }
            do {
                try manager.moveItem(at: target, to: candidate)
                return candidate
            } catch {
                // Another process may have claimed this diagnostic name between
                // the existence check and the move. Retry only that collision;
                // surface permission and filesystem failures to the caller.
                if manager.fileExists(atPath: candidate.path) {
                    attempt += 1
                } else {
                    throw error
                }
            }
        }
    }
}
