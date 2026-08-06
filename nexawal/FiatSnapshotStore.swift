import Foundation
import NexaWalLogic

struct FiatTxSnapshot: Codable, Equatable, Sendable {
    var currency: String
    var fiatPerXmr: String
    var recordedAtMs: Int64
    var kind: String
}

enum FiatSnapshotStore {
    static let snapshotsKey = "wallet.tx_fiat.v1"
    static let observedKey = "wallet.tx_fiat.seen.v1"

    static func snapshot(for txid: String) -> FiatTxSnapshot? {
        loadSnapshots()[txid]
    }

    static func record(txid: String, rate: FiatRate?, kind: String, nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        let trimmed = txid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var observed = loadObserved()
        observed.insert(trimmed)
        saveObserved(observed)

        guard let rate, FiatEstimate.isFresh(fetchedAtMs: rate.fetchedAtMs, nowMs: nowMs) else { return }
        var map = loadSnapshots()
        if map[trimmed] != nil { return }
        map[trimmed] = FiatTxSnapshot(
            currency: rate.currency,
            fiatPerXmr: FiatEstimate.decimalString(rate.fiatPerXmr),
            recordedAtMs: nowMs,
            kind: kind
        )
        saveSnapshots(map)
    }

    static func recordNewTransfers(
        transfers: [(txid: String, timestampSeconds: Int64?)],
        rate: FiatRate?,
        optedInAtMs: Int64,
        nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        var observed = loadObserved()
        var snapshots = loadSnapshots()
        var observedChanged = false
        var snapshotsChanged = false

        for item in transfers {
            let trimmed = item.txid.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if observed.contains(trimmed) { continue }
            observed.insert(trimmed)
            observedChanged = true

            guard FiatEstimate.shouldRecordSeenSnapshot(
                txTimestampSeconds: item.timestampSeconds,
                optedInAtMs: optedInAtMs
            ) else { continue }
            guard snapshots[trimmed] == nil else { continue }
            guard let rate, FiatEstimate.isFresh(fetchedAtMs: rate.fetchedAtMs, nowMs: nowMs) else { continue }
            snapshots[trimmed] = FiatTxSnapshot(
                currency: rate.currency,
                fiatPerXmr: FiatEstimate.decimalString(rate.fiatPerXmr),
                recordedAtMs: nowMs,
                kind: "seen"
            )
            snapshotsChanged = true
        }

        if observedChanged { saveObserved(observed) }
        if snapshotsChanged { saveSnapshots(snapshots) }
    }

    private static func loadSnapshots() -> [String: FiatTxSnapshot] {
        guard let data = UserDefaults.standard.data(forKey: snapshotsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: FiatTxSnapshot].self, from: data)) ?? [:]
    }

    private static func saveSnapshots(_ map: [String: FiatTxSnapshot]) {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: snapshotsKey)
        }
    }

    private static func loadObserved() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: observedKey),
              let rows = try? JSONDecoder().decode([String].self, from: data)
        else {
            return Set(loadSnapshots().keys)
        }
        return Set(rows)
    }

    private static func saveObserved(_ set: Set<String>) {
        if let data = try? JSONEncoder().encode(Array(set)) {
            UserDefaults.standard.set(data, forKey: observedKey)
        }
    }
}
