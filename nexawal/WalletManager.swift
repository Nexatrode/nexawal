//
//  WalletManager.swift
//  nexawal
//
//  Created by steve on 12/1/25.
//

import Foundation
import MoneroWalletCoreFFI
import NexaWalLogic

enum WalletError: LocalizedError {
    case invalidMnemonic
    case walletOpenFailed(String)
    case refreshFailed(String)
    case balanceFailed(String)
    case statusFailed(String)
    case addressDerivationFailed(String)
    case pendingSendRecoveryFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidMnemonic:
            return "Invalid mnemonic phrase. Must be 25 words."
        case .walletOpenFailed(let message):
            return "Failed to open wallet: \(message)"
        case .refreshFailed(let message):
            return message
        case .balanceFailed(let message):
            return "Failed to get balance: \(message)"
        case .statusFailed(let message):
            return "Failed to get sync status: \(message)"
        case .addressDerivationFailed(let message):
            return "Failed to derive address: \(message)"
        case .pendingSendRecoveryFailed(let message):
            return message
        }
    }
}

actor WalletManager {
    static let shared = WalletManager()

    private var currentWalletId: String?
    private var cachedBalance: (total: UInt64, unlocked: UInt64)?
    private var refreshInProgress: Bool = false
    private var refreshBatch: Int = 0
    private var currentNetworkMainnet: Bool = true
    private var cachePersistenceSuppressed: Bool = false

    // Explicit cancellation support for refresh. WalletCore exposes an authoritative per-wallet
    // job state, so cancellation does not complete locally until the native worker is actually
    // idle (or has reported a terminal failure).
    private var refreshWaitTask: Task<WalletCoreFFIClient.SyncStatus, Error>?
    private var refreshCancelRequested: Bool = false
    /// Serializes send/sweep so double-tap Confirm cannot broadcast twice.
    private let sendGate = SendGate()

    private init() {}

    private func withSendLock<T>(_ body: () throws -> T) throws -> T {
        try sendGate.withLock(body)
    }

    private func normalizedMnemonic(_ mnemonic: String) -> String {
        mnemonic
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Subaddress-constrained helpers (account 0)

    private func filterForSubaddressMinor(_ minor: UInt32) -> [String: Any] {
        // Core currently supports {"subaddress_minor": <u32>} and assumes major == 0.
        ["subaddress_minor": minor]
    }

    /// Get total/unlocked balance constrained to account 0, subaddress minor.
    /// Note: this does NOT use the wallet-wide cached balance.
    func getBalance(fromSubaddressMinor minor: UInt32) throws -> (total: UInt64, unlocked: UInt64) {
        guard let walletId = currentWalletId else {
            throw WalletError.balanceFailed("No wallet is currently open")
        }
        do {
            return try WalletCoreFFIClient.getBalanceWithFilter(
                walletId: walletId,
                filter: filterForSubaddressMinor(minor)
            )
        } catch {
            throw WalletError.balanceFailed(error.localizedDescription)
        }
    }

    /// Open or create a wallet from a mnemonic phrase
    func openWallet(
        mnemonic: String,
        walletId: String = "main_wallet",
        restoreHeight: UInt64 = 0,
        mainnet: Bool = true,
        importCache: Bool = true
    ) throws {
        let normalizedMnemonic = normalizedMnemonic(mnemonic)
        // Validate mnemonic (should be 25 words)
        let words = normalizedMnemonic.components(separatedBy: .whitespaces)
        guard words.count == 25 else {
            throw WalletError.invalidMnemonic
        }

        do {
            try WalletCoreFFIClient.openWalletFromMnemonic(
                walletId: walletId,
                mnemonic: normalizedMnemonic,
                restoreHeight: restoreHeight,
                mainnet: mainnet
            )
            currentNetworkMainnet = mainnet
            currentWalletId = walletId
            cachePersistenceSuppressed = false
            cachedBalance = nil // Clear cached balance
            if importCache {
                importCacheIfPresent(for: walletId)
            }
            // Re-apply after cache import so subaddress lookahead is registered on the restored scanner.
            try WalletCoreFFIClient.setGapLimit(
                walletId: walletId,
                gapLimit: MoneroConfig.gapLimit
            )
            recoverPendingPreparedSendBestEffort(for: walletId)
        } catch {
            throw WalletError.walletOpenFailed(error.localizedDescription)
        }
    }



    /// Refresh the wallet against the Monero node
    func refreshWallet() async throws -> WalletCoreFFIClient.SyncStatus {
        guard let walletId = currentWalletId else {
            throw WalletError.refreshFailed("No wallet is currently open")
        }

        // Serialize refreshes: if one is in-flight, wait for it to finish and return latest status
        if refreshInProgress {
            while refreshInProgress {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            return try getSyncStatus()
        }
        refreshInProgress = true
        refreshCancelRequested = false

        applyNetworkProxy()
        applyScanTuning()
        // Always pass an explicit node URL into the core so bulk modes are eligible even when the app is using a "default" node.
        // Passing `nil` forces the core into per-block mode due to the clearnet gating check.
        let nodeURL = MoneroConfig.scanNodeURL()
        print("🌐 Refresh starting with nodeURL=\(nodeURL)")
        defer {
            refreshInProgress = false
            refreshCancelRequested = false
            refreshWaitTask = nil
        }

        do {
            // Run the refresh in a dedicated task so UI can request cancellation explicitly.
            let waitTask = Task { () throws -> WalletCoreFFIClient.SyncStatus in
                // performRefresh triggers refreshWalletAsync then waits/polls for completion
                return try await performRefresh(walletId: walletId, nodeURL: nodeURL)
            }
            refreshWaitTask = waitTask

            let status = try await waitTask.value

            // Final export at end of refresh (authoritative)
            exportCacheAndPersist(for: walletId)
            cachedBalance = nil
            return status
        } catch let nodeError {
            // Best-effort: persist any progress even on failure/cancellation.
            // This helps resumes after backgrounding, network loss, or app termination.
            exportCacheAndPersist(for: walletId)

            // Never treat cancel as a successful sync. Returning status here used to
            // checkpoint a partial lastScanned height as trusted.
            if refreshCancelRequested || (nodeError as? CancellationError) != nil {
                print("ℹ️ Refresh cancelled")
                cachedBalance = nil
                throw CancellationError()
            }
            print("⚠️ Refresh with nodeURL '\(nodeURL)' failed: \(nodeError.localizedDescription)")

            let coreLastErr = WalletCoreFFIClient.lastErrorMessage() ?? ""
            let combinedErr = ([nodeError.localizedDescription, coreLastErr])
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            if !combinedErr.isEmpty {
                print("⚠️ Refresh error detail: \(combinedErr)")
            }
            let errorDetail = combinedErr.isEmpty ? nodeError.localizedDescription : combinedErr
            let detailedError: String
            if SyncErrorPolicy.classify(message: errorDetail) == .nodeUnreachable {
                detailedError = """
                Failed to refresh wallet.

                Attempted node: \(nodeURL)
                Error: \(errorDetail)

                Possible issues:
                - Node at \(nodeURL) is not reachable from this device
                - Network connectivity issue
                - Node is not running or not accepting connections
                - Check Settings to verify node address is correct
                - If using simulator, ensure it can reach the network
                """
            } else {
                detailedError = """
                Failed to refresh wallet.

                Attempted node: \(nodeURL)
                Error: \(errorDetail)
                """
            }
            throw WalletError.refreshFailed(detailedError)
        }
    }

    /// Get the wallet balance (total and unlocked in piconero)
    func getBalance() throws -> (total: UInt64, unlocked: UInt64) {
        guard let walletId = currentWalletId else {
            throw WalletError.balanceFailed("No wallet is currently open")
        }

        // Return cached balance if available
        if let cached = cachedBalance {
            return cached
        }

        do {
            let balance = try WalletCoreFFIClient.getBalance(walletId: walletId)
            cachedBalance = balance
            return balance
        } catch {
            throw WalletError.balanceFailed(error.localizedDescription)
        }
    }

    /// Retrieve the latest sync status values cached by the core
    func getSyncStatus() throws -> WalletCoreFFIClient.SyncStatus {
        guard let walletId = currentWalletId else {
            throw WalletError.statusFailed("No wallet is currently open")
        }

        do {
            return try WalletCoreFFIClient.syncStatus(walletId: walletId)
        } catch {
            throw WalletError.statusFailed(error.localizedDescription)
        }
    }

    private func performRefresh(walletId: String, nodeURL: String?) async throws -> WalletCoreFFIClient.SyncStatus {
        let effectiveURL = nodeURL ?? MoneroConfig.scanNodeURL()
        print("🌐 performRefresh(walletId=\(walletId)) using nodeURL=\(effectiveURL)")

        // A previous UI task may have been cancelled before its native worker observed the cancel
        // flag. Join that worker instead of racing wallet_refresh_async and receiving -31.
        if try WalletCoreFFIClient.refreshJobStatus(walletId: walletId).state == .running {
            print("⏳ Waiting for previous native refresh worker to stop walletId=\(walletId)")
            _ = try await waitForNativeRefreshTerminal(using: walletId)
        }
        try WalletCoreFFIClient.refreshWalletAsync(walletId: walletId, nodeURL: effectiveURL)
        return try await waitForRefreshCompletion(using: walletId)
    }

    @discardableResult
    private func waitForNativeRefreshTerminal(
        using walletId: String,
        timeout: TimeInterval = 20,
        pollInterval: TimeInterval = 0.05
    ) async throws -> WalletCoreFFIClient.RefreshJobStatus {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let job = try WalletCoreFFIClient.refreshJobStatus(walletId: walletId)
            switch job.state {
            case .idle:
                return job
            case .failed:
                return job
            case .running:
                break
            }
            guard Date() < deadline else {
                throw WalletError.refreshFailed(
                    "Timed out waiting for the native refresh worker to stop"
                )
            }
            try await Task.sleep(
                nanoseconds: UInt64(max(0.01, pollInterval) * 1_000_000_000)
            )
        }
    }

    /// Request cancellation of the in-flight refresh.
    ///
    /// This will:
    /// - ask the Rust core to cancel the active refresh loop (best-effort)
    /// - cancel the Swift wait/poll task
    /// - persist best-effort cache progress so a later refresh resumes faster
    func cancelRefresh() async {
        let nativeRunning: Bool
        if let walletId = currentWalletId {
            nativeRunning = (try? WalletCoreFFIClient.refreshJobStatus(walletId: walletId))?.state == .running
        } else {
            nativeRunning = false
        }
        guard refreshInProgress || nativeRunning else { return }
        refreshCancelRequested = true

        // Ask the core to cancel the active refresh loop (best-effort).
        do {
            if let walletId = currentWalletId {
                try WalletCoreFFIClient.refreshCancel(walletId: walletId)
            } else {
                print("⚠️ Core refresh cancel requested, but no wallet is currently open")
            }
        } catch {
            // Don't fail UI cancel if core cancel isn't available; still cancel waiting/polling.
            print("⚠️ Core refresh cancel request failed: \(error.localizedDescription)")
        }

        // Let the Swift waiter observe refreshCancelRequested itself. Cancelling that task here
        // would make its sleeps throw before it could join the native worker.
        var nativeSettled = true
        if let walletId = currentWalletId {
            do {
                let terminal = try await waitForNativeRefreshTerminal(using: walletId)
                if terminal.state == .failed, let error = terminal.error {
                    print("ℹ️ Native refresh ended while cancelling: \(error)")
                }
            } catch {
                nativeSettled = false
                print("⚠️ Native refresh cancellation did not settle cleanly: \(error.localizedDescription)")
            }
        }

        if nativeSettled, let walletId = currentWalletId {
            exportCacheAndPersist(for: walletId)
            print("🗂️ Cache export reason: cancel walletId=\(walletId)")
        }
        cachedBalance = nil
        refreshInProgress = false
        refreshWaitTask = nil
        print("🛑 Cancel refresh requested")
    }

    private func waitForRefreshCompletion(using walletId: String, stallTimeout: TimeInterval = 45, pollInterval: TimeInterval = 0.2) async throws -> WalletCoreFFIClient.SyncStatus {
        var targetHeight: UInt64?
        var lastProgressAt = Date()
        var lastScannedSnapshot: UInt64 = 0

        // Periodic persistence while refresh is running.
        // Exporting cache is expensive on iOS, so avoid doing it on a short wall-clock cadence.
        // Prefer a larger interval and only persist after meaningful scan progress.
        var lastPersistAt = Date.distantPast
        var lastPersistedScannedHeight: UInt64 = 0
        let persistInterval: TimeInterval = 120.0
        let persistBlockDelta: UInt64 = 1000

        // Base the watchdog on the shared WalletCore default. The actual request sizing
        // remains controlled by WalletCore defaults or an explicit environment override.
        let batch = MoneroConfig.defaultScanBatch
        let dynamicStallTimeout = max(
            stallTimeout,
            min(300.0, max(60.0, Double(batch) * 0.25))
        )

        // If the UI requested cancel, exit early.
        if refreshCancelRequested || Task.isCancelled {
            _ = try await waitForNativeRefreshTerminal(using: walletId)
            exportCacheAndPersist(for: walletId)
            print("🗂️ Cache export reason: cancel walletId=\(walletId)")
            throw CancellationError()
        }

        while true {
            let refreshJob = try WalletCoreFFIClient.refreshJobStatus(walletId: walletId)
            if refreshJob.state == .failed {
                exportCacheAndPersist(for: walletId)
                throw WalletError.refreshFailed(
                    refreshJob.error ?? "Native refresh failed without an error message"
                )
            }
            let status = try WalletCoreFFIClient.syncStatus(walletId: walletId)

            // Capture the initial target chain height once (so we don't chase a moving tip).
            // Avoid locking onto restoreHeight as the target (which reads as chainHeight initially).
            if targetHeight == nil, status.chainHeight > status.restoreHeight {
                targetHeight = status.chainHeight
                print("🧭 Refresh target height set to \(targetHeight!) (restoreHeight=\(status.restoreHeight))")
            }

            // Track progress and detect stalls
            if status.lastScanned > lastScannedSnapshot {
                lastScannedSnapshot = status.lastScanned
                lastProgressAt = Date()
                // Periodic progress log
                print("⏳ Refresh progress: scanned=\(status.lastScanned), target=\(targetHeight ?? status.chainHeight), tip=\(status.chainHeight)")
            }

            // Persist scan progress periodically while refresh is still running.
            // This improves resume after backgrounding, app termination, or transient network issues.
            let now = Date()
            if now.timeIntervalSince(lastPersistAt) >= persistInterval,
               status.lastScanned > 0,
               status.lastScanned >= lastPersistedScannedHeight + persistBlockDelta {
                exportCacheAndPersist(for: walletId)
                print("🗂️ Cache export reason: periodic walletId=\(walletId)")
                lastPersistAt = now
                lastPersistedScannedHeight = status.lastScanned
            }

            // Only compute effective target after targetHeight is known (daemon reported > restore)
            if let target = targetHeight {
                let effectiveTarget = max(target, status.restoreHeight)

                // Completion is based on the fixed target height snapshot.
                //
                // IMPORTANT:
                // Do NOT return early "within tolerance" here. That can skip the last few blocks
                // of the fixed target window and miss incoming transfers (exactly what we observed).
                if effectiveTarget > 0,
                   status.lastScanned >= effectiveTarget,
                   refreshJob.state == .idle {
                    print("✅ Refresh reached target height \(effectiveTarget) (lastScanned=\(status.lastScanned))")
                    return status
                }
            }

            if refreshJob.state == .idle,
               let target = targetHeight,
               status.lastScanned < max(target, status.restoreHeight) {
                exportCacheAndPersist(for: walletId)
                throw WalletError.refreshFailed(
                    "Native refresh stopped before reaching its target " +
                    "(lastScanned=\(status.lastScanned), target=\(target))"
                )
            }

            // Surface stalls without silently changing the scan profile. The user can retry
            // manually, or provide an explicit WalletCore environment override.
            if Date().timeIntervalSince(lastProgressAt) > dynamicStallTimeout {
                print("🛑 Stall detected (>\(Int(dynamicStallTimeout))s); surfacing error without changing scan profile.")
                exportCacheAndPersist(for: walletId)
                throw WalletError.refreshFailed(
                    "Sync stalled: no scan progress for over \(Int(dynamicStallTimeout))s (lastScanned=\(lastScannedSnapshot), target=\(targetHeight ?? 0))"
                )
            }

            let interval = max(pollInterval, 0.05)
            let nanoseconds = UInt64(interval * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanoseconds)
            if refreshCancelRequested || Task.isCancelled {
                _ = try await waitForNativeRefreshTerminal(using: walletId)
                exportCacheAndPersist(for: walletId)
                print("🗂️ Cache export reason: cancel walletId=\(walletId)")
                throw CancellationError()
            }
        }
    }

    /// Derive the primary address from the current wallet's mnemonic
    /// Note: This requires storing the mnemonic, which we'll handle in the ViewModel
    func derivePrimaryAddress(mnemonic: String, mainnet: Bool = true) throws -> String {
        let normalizedMnemonic = normalizedMnemonic(mnemonic)
        do {
            return try WalletCoreFFIClient.derivePrimaryAddressFromMnemonic(normalizedMnemonic, mainnet: mainnet)
        } catch {
            throw WalletError.addressDerivationFailed(error.localizedDescription)
        }
    }

    /// Get the WalletCore version
    func getVersion() -> String {
        return WalletCoreFFIClient.version()
    }

    /// Check if a wallet is currently open
    func isWalletOpen() -> Bool {
        return currentWalletId != nil
    }

    /// Get the current wallet ID
    func getCurrentWalletId() -> String? {
        return currentWalletId
    }

    /// Best-effort snapshot of the current wallet scan state for fast resume.
    /// Intended to be called when the app backgrounds.
    ///
    /// Notes:
    /// - Uses the existing cache export/import mechanism.
    /// - Does not force a refresh; it only persists current core state.
    func snapshotState() throws {
        guard let walletId = currentWalletId else {
            throw WalletError.statusFailed("No wallet is currently open")
        }

        // IMPORTANT: A snapshot is not a cancel and must not interfere with an active refresh.
        // Export whatever state the core currently has and persist it.
        exportCacheAndPersist(for: walletId)
        print("🗂️ Cache export reason: snapshot walletId=\(walletId)")
    }

    /// Rewind the in-memory scan cursor without deleting the on-disk cache.
    /// Used after an interrupted refresh whose checkpoint jumped to tip.
    func rewindScanCursor(from height: UInt64) async throws {
        guard let walletId = currentWalletId else {
            throw WalletError.refreshFailed("No wallet is currently open")
        }
        try WalletCoreFFIClient.forceRescanFromHeight(walletId: walletId, fromHeight: height)
        cachedBalance = nil
        print("🧭 rewindScanCursor walletId=\(walletId) fromHeight=\(height)")
    }

    /// Force rescan from a specific height. Resets core scan state, clears local cache, and refreshes.
    func rescan(from height: UInt64) async throws -> WalletCoreFFIClient.SyncStatus {
        guard let walletId = currentWalletId else {
            throw WalletError.refreshFailed("No wallet is currently open")
        }
        // Reset core state to the requested height
        try WalletCoreFFIClient.forceRescanFromHeight(walletId: walletId, fromHeight: height)
        // Clear persisted cache so we don't restore old state on next launch
        deletePersistedScanCache(walletId: walletId)
        cachePersistenceSuppressed = false
        // Trigger a refresh; this will also export a fresh cache on success
        return try await refreshWallet()
    }

    /// Import a previously exported core cache blob for this wallet, if present.
    /// - Migration note: also migrates any legacy cache stored in UserDefaults to a file.
    private func importCacheIfPresent(for walletId: String) {
        // 1) Migrate legacy cache (UserDefaults -> file)
        let legacyKey = "wallet_cache_\(walletId)"
        if let legacyBlob = UserDefaults.standard.data(forKey: legacyKey) {
            do {
                let fileURL = cacheFileURL(for: walletId)
                try ensureCacheDirectory()
                try WalletCacheFileIO.writeAtomically(legacyBlob, to: fileURL)
                try excludeFromBackup(url: fileURL)
                UserDefaults.standard.removeObject(forKey: legacyKey)
                print("🗂️ Migrated legacy cache to file (\(legacyBlob.count) bytes) at \(fileURL.lastPathComponent)")
            } catch {
                print("⚠️ Legacy cache migration failed for \(walletId): \(error.localizedDescription)")
            }
        }

        // 2) Import from file if present
        let fileURL = cacheFileURL(for: walletId)
        do {
            let data = try Data(contentsOf: fileURL)
            do {
                try WalletCoreFFIClient.importCache(walletId: walletId, cacheBlob: data)
                print("🗂️ Imported wallet cache (\(data.count) bytes) for \(walletId) from file")
            } catch {
                let coreMsg = WalletCoreFFIClient.lastErrorMessage() ?? ""
                let reason = [error.localizedDescription, coreMsg]
                    .filter { !$0.isEmpty }
                    .joined(separator: " | ")
                let quarantined = quarantineRejectedCache(
                    at: fileURL,
                    walletId: walletId,
                    reason: reason
                )
                if coreMsg.lowercased().contains("incompatible cache version") {
                    // Best-effort: reset in-memory tracked outputs/quarantine in the core as well.
                    // (If the function isn't available in this build, ignore; refresh will rebuild anyway.)
                    try? WalletCoreFFIClient.resetTrackedOutputs(walletId: walletId)
                }
                print("⚠️ Cache import rejected for \(walletId); quarantined=\(quarantined?.lastPathComponent ?? "none") reason=\(reason)")
                return
            }
        } catch {
            // File may not exist on first run; ignore not found, log others
            if (error as NSError).domain != NSCocoaErrorDomain || (error as NSError).code != NSFileReadNoSuchFileError {
                let quarantined = quarantineRejectedCache(
                    at: fileURL,
                    walletId: walletId,
                    reason: "read failed: \(error.localizedDescription)"
                )
                print("⚠️ Cache read failed for \(walletId); quarantined=\(quarantined?.lastPathComponent ?? "none") error=\(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    private func quarantineRejectedCache(at fileURL: URL, walletId: String, reason: String) -> URL? {
        do {
            let quarantined = try WalletCacheFileIO.quarantineRejectedFile(at: fileURL)
            if let quarantined {
                print("🧹 Cache quarantined walletId=\(walletId) reason=\(reason) movedTo=\(quarantined.lastPathComponent)")
            }
            return quarantined
        } catch {
            print("⚠️ Cache quarantine failed walletId=\(walletId) reason=\(reason) error=\(error.localizedDescription)")
            return nil
        }
    }

    /// Export the core cache blob and persist it to Application Support for fast resume across launches.
    private func exportCacheAndPersist(for walletId: String) {
        guard !cachePersistenceSuppressed else {
            print("🗂️ Cache export suppressed after explicit clear walletId=\(walletId)")
            return
        }
        do {
            guard let data = try WalletCoreFFIClient.exportCache(walletId: walletId) else {
                print("🗂️ Exported wallet cache is empty for \(walletId)")
                return
            }
            try ensureCacheDirectory()
            let fileURL = cacheFileURL(for: walletId)
            try WalletCacheFileIO.writeAtomically(data, to: fileURL)
            try excludeFromBackup(url: fileURL)
            print("🗂️ Exported wallet cache (\(data.count) bytes) to \(fileURL.lastPathComponent) for \(walletId)")
        } catch {
            print("⚠️ Cache export failed for \(walletId): \(error.localizedDescription)")
        }
    }

    // MARK: - Cache file utilities

    /// Directory used to store wallet cache blobs.
    private func cacheDirectoryURL() -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        // Namespace for NexaWal caches with per-network subdirectory
        let netDir = currentNetworkMainnet ? "mainnet" : "stagenet"
        return appSupport
            .appendingPathComponent("WalletCaches", isDirectory: true)
            .appendingPathComponent(netDir, isDirectory: true)
    }

    /// Full path for a wallet's cache blob.
    private func cacheFileURL(for walletId: String) -> URL {
        cacheDirectoryURL().appendingPathComponent("\(walletId).cache")
    }

    /// Durable prepared-send payload so relay can resume after a crash mid-broadcast.
    private func preparedFileURL(for walletId: String) -> URL {
        cacheDirectoryURL().appendingPathComponent("\(walletId).prepared.json")
    }

    private struct PendingPreparedEnvelope: Codable {
        let nodeURL: String
        let prepared: WalletCoreFFIClient.PreparedSend
        let createdAt: Date
    }

    private func persistPendingPrepared(
        for walletId: String,
        nodeURL: String,
        prepared: WalletCoreFFIClient.PreparedSend
    ) throws {
        try ensureCacheDirectory()
        let envelope = PendingPreparedEnvelope(nodeURL: nodeURL, prepared: prepared, createdAt: Date())
        let data = try JSONEncoder().encode(envelope)
        let fileURL = preparedFileURL(for: walletId)
        try data.write(to: fileURL, options: .atomic)
        try excludeFromBackup(url: fileURL)
        print("🗂️ Persisted prepared send txid=\(prepared.txid) to \(fileURL.lastPathComponent)")
    }

    private func clearPendingPrepared(for walletId: String) {
        let fileURL = preparedFileURL(for: walletId)
        try? FileManager.default.removeItem(at: fileURL)
        print("🗂️ Cleared prepared send file \(fileURL.lastPathComponent)")
    }

    private func loadPendingPrepared(for walletId: String) throws -> PendingPreparedEnvelope? {
        let fileURL = preparedFileURL(for: walletId)
        do {
            return try WalletCacheFileIO.loadJSONIfPresent(
                PendingPreparedEnvelope.self,
                from: fileURL
            )
        } catch {
            print("⚠️ Failed to decode prepared send file: \(error.localizedDescription)")
            throw WalletError.pendingSendRecoveryFailed(
                "Pending send recovery data exists but cannot be read. New sends are blocked until it is recovered or removed: \(error.localizedDescription)"
            )
        }
    }

    private struct RecoveredPreparedSend {
        let txid: String
        let amount: UInt64
        let fee: UInt64
    }

    /// If a prepared payload is on disk, relay it (idempotent) and return that result.
    /// Callers must not construct a second transaction in the same user action.
    @discardableResult
    private func completePendingPreparedSend(for walletId: String, preferredNodeURL: String) throws -> RecoveredPreparedSend? {
        guard let pending = try loadPendingPrepared(for: walletId) else { return nil }
        applyBroadcastProxy()
        let endpoint = pending.nodeURL.isEmpty ? preferredNodeURL : pending.nodeURL
        print("↩️ Recovering pending prepared send txid=\(pending.prepared.txid) via \(endpoint)")
        let relay = try WalletCoreFFIClient.relayPrepared(
            walletId: walletId,
            prepared: pending.prepared,
            nodeURL: endpoint
        )
        clearPendingPrepared(for: walletId)
        exportCacheAndPersist(for: walletId)
        print("✅ Recovered pending prepared send txid=\(relay.txid) status=\(relay.status)")
        return RecoveredPreparedSend(
            txid: relay.txid,
            amount: pending.prepared.amount,
            fee: pending.prepared.fee
        )
    }

    private func recoverPendingPreparedSendBestEffort(for walletId: String) {
        do {
            _ = try completePendingPreparedSend(
                for: walletId,
                preferredNodeURL: MoneroConfig.broadcastNodeURL()
            )
        } catch {
            print("⚠️ Pending prepared send recovery deferred: \(error.localizedDescription)")
        }
    }

    /// Ensure the cache directory exists and is excluded from backups.
    private func ensureCacheDirectory() throws {
        let fm = FileManager.default
        let dir = cacheDirectoryURL()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        try excludeFromBackup(url: dir)
    }

    /// Mark a URL (file or directory) as excluded from iCloud backups.
    private func excludeFromBackup(url: URL) throws {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(resourceValues)
    }

    /// Apply HTTP proxy environment for I2P scan (I2P-only policy).
    private func applyNetworkProxy() {
        if MoneroConfig.shouldUseI2PHTTPProxy(forBroadcast: false),
           let proxy = MoneroConfig.i2pHTTPProxyAddress {
            applyProxyEnv(proxy)
        } else {
            clearProxyEnv()
        }
    }

    /// Apply proxy settings for broadcast path (I2P only or hybrid).
    private func applyBroadcastProxy() {
        if MoneroConfig.shouldUseI2PHTTPProxy(forBroadcast: true),
           let proxy = MoneroConfig.i2pHTTPProxyAddress {
            applyProxyEnv(proxy)
        } else {
            clearProxyEnv()
        }
    }

    private func applyProxyEnv(_ proxy: String) {
        let proxyURL = proxy.hasPrefix("http://") || proxy.hasPrefix("https://") ? proxy : "http://\(proxy)"
        setenv("HTTP_PROXY", proxyURL, 1)
        setenv("http_proxy", proxyURL, 1)
        setenv("ALL_PROXY", proxyURL, 1)
        setenv("all_proxy", proxyURL, 1)
        unsetenv("NO_PROXY")
        unsetenv("no_proxy")
    }

    private func clearProxyEnv() {
        unsetenv("HTTP_PROXY")
        unsetenv("http_proxy")
        unsetenv("ALL_PROXY")
        unsetenv("all_proxy")
    }

    /// Keep scan tuning in WalletCore. The shared core defaults are range/75/75;
    /// explicit WalletCore environment variables remain available for diagnostics.
    private func applyScanTuning() {
        refreshBatch = MoneroConfig.defaultScanBatch

        unsetenv("WALLETCORE_SCAN_PAR")
        unsetenv("WALLETCORE_SCAN_BATCH")
        unsetenv("WALLETCORE_WALLET2_FAST_FALLBACK")
        unsetenv("WALLETCORE_BULK_BIN_DEBUG")
        #if DEBUG
        setenv("WALLETCORE_SCAN_LOG", "1", 1)
        #else
        setenv("WALLETCORE_SCAN_LOG", "0", 1)
        #endif

        let node = MoneroConfig.scanNodeURL()
        print("🧪 scan tuning: WalletCore defaults (range/75/75) node=\(node)")
    }

    // NOTE: Removed the reason-tagging wrapper to avoid recursive overload confusion.
    // Call `exportCacheAndPersist(for:)` directly and print a reason at the call site instead.

    /// Delete persisted scan cache for a wallet id without requiring an open wallet.
    /// Used before create/replace so Occupied in-memory state cannot import another wallet's blob.
    func deletePersistedScanCache(walletId: String) {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        for net in ["mainnet", "stagenet"] {
            let fileURL = appSupport
                .appendingPathComponent("WalletCaches", isDirectory: true)
                .appendingPathComponent(net, isDirectory: true)
                .appendingPathComponent("\(walletId).cache")
            if fm.fileExists(atPath: fileURL.path) {
                try? fm.removeItem(at: fileURL)
                print("🗂️ Cleared wallet cache at \(fileURL.lastPathComponent) for \(walletId)")
            }
        }
        let legacyKey = "wallet_cache_\(walletId)"
        if UserDefaults.standard.object(forKey: legacyKey) != nil {
            UserDefaults.standard.removeObject(forKey: legacyKey)
            print("🗂️ Removed legacy cache blob for \(walletId)")
        }
    }

    // Clear on-disk scan cache for current wallet (per network).
    // Removes per-network cache file and any legacy cache stored in UserDefaults.
    func clearScanCache() async throws {
        guard let walletId = currentWalletId else {
            throw WalletError.refreshFailed("No wallet is currently open")
        }
        await cancelRefresh()
        deletePersistedScanCache(walletId: walletId)
        cachePersistenceSuppressed = true
        let fileURL = cacheFileURL(for: walletId)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            print("🗂️ No cache file to clear for \(walletId)")
        }
    }

    /// Estimate fee for a single-destination transfer using current broadcast policy.
    func previewFee(toAddress: String, amountPiconero: UInt64, ringLen: UInt8 = 16) throws -> UInt64 {
        guard let walletId = currentWalletId else {
            throw WalletError.statusFailed("No wallet is currently open")
        }
        applyBroadcastProxy()

        // Verbose logging: amount, policy, endpoint, proxy, balances
        let policy = MoneroConfig.networkPolicy
        let endpoint = MoneroConfig.broadcastNodeURL()
        let proxyDesc = MoneroConfig.i2pHTTPProxyAddress ?? "(none)"
        let amountXMR = Double(amountPiconero) / 1_000_000_000_000.0
        if let (total, unlocked) = try? getBalance() {
            let totalXMR = Double(total) / 1_000_000_000_000.0
            let unlockedXMR = Double(unlocked) / 1_000_000_000_000.0
            print("🔎 Preview start: amount=\(String(format: "%.12f", amountXMR)) XMR, ring=\(ringLen), policy=\(policy), broadcast=\(endpoint), proxy=\(proxyDesc), balances total=\(String(format: "%.12f", totalXMR)) XMR, unlocked=\(String(format: "%.12f", unlockedXMR)) XMR")
        } else {
            print("🔎 Preview start: amount=\(String(format: "%.12f", amountXMR)) XMR, ring=\(ringLen), policy=\(policy), broadcast=\(endpoint), proxy=\(proxyDesc)")
        }

        let dest = WalletCoreFFIClient.Destination(address: toAddress, amount: amountPiconero)
        let fee: UInt64
        do {
            fee = try previewFeeWithOptionalSiblingFallback(
                walletId: walletId,
                nodeURL: endpoint,
                ringLen: ringLen,
                destinations: [dest]
            )
        } catch {
            let coreMsg = WalletCoreFFIClient.lastErrorMessage() ?? "(none)"
            print("❌ Preview fee failed: error=\(error.localizedDescription) walletcore_last_error=\(coreMsg)")
            throw error
        }

        let feeXMR = Double(fee) / 1_000_000_000_000.0
        print("📦 Estimated fee: \(fee) piconero (\(String(format: "%.12f", feeXMR)) XMR)")

        return fee
    }

    /// Estimate fee for a single-destination transfer constrained to a subaddress (account 0, minor).
    func previewFee(
        fromSubaddressMinor: UInt32,
        toAddress: String,
        amountPiconero: UInt64,
        ringLen: UInt8 = 16
    ) throws -> UInt64 {
        guard let walletId = currentWalletId else {
            throw WalletError.statusFailed("No wallet is currently open")
        }
        applyBroadcastProxy()

        let policy = MoneroConfig.networkPolicy
        let endpoint = MoneroConfig.broadcastNodeURL()
        let proxyDesc = MoneroConfig.i2pHTTPProxyAddress ?? "(none)"
        let amountXMR = Double(amountPiconero) / 1_000_000_000_000.0
        print("🔎 Preview (subaddr \(fromSubaddressMinor)) start: amount=\(String(format: "%.12f", amountXMR)) XMR, ring=\(ringLen), policy=\(policy), broadcast=\(endpoint), proxy=\(proxyDesc)")

        let dest = WalletCoreFFIClient.Destination(address: toAddress, amount: amountPiconero)
        let fee: UInt64
        do {
            fee = try previewFeeWithFilterOptionalSiblingFallback(
                walletId: walletId,
                nodeURL: endpoint,
                ringLen: ringLen,
                destinations: [dest],
                filter: filterForSubaddressMinor(fromSubaddressMinor)
            )
        } catch {
            let coreMsg = WalletCoreFFIClient.lastErrorMessage() ?? "(none)"
            print("❌ Preview fee (subaddr \(fromSubaddressMinor)) failed: error=\(error.localizedDescription) walletcore_last_error=\(coreMsg)")
            throw error
        }

        let feeXMR = Double(fee) / 1_000_000_000_000.0
        print("📦 Estimated fee (subaddr \(fromSubaddressMinor)): \(fee) piconero (\(String(format: "%.12f", feeXMR)) XMR)")

        return fee
    }

    /// Sweep preview ("Send Max") constrained to a subaddress (account 0, minor).
    func previewSweep(
        fromSubaddressMinor: UInt32,
        toAddress: String,
        ringLen: UInt8 = 16
    ) throws -> (amount: UInt64, fee: UInt64) {
        guard let walletId = currentWalletId else {
            throw WalletError.statusFailed("No wallet is currently open")
        }
        applyBroadcastProxy()

        let endpoint = MoneroConfig.broadcastNodeURL()
        do {
            let res = try previewSweepWithFilterOptionalSiblingFallback(
                walletId: walletId,
                nodeURL: endpoint,
                ringLen: ringLen,
                toAddress: toAddress,
                filter: filterForSubaddressMinor(fromSubaddressMinor)
            )
            return res
        } catch {
            let coreMsg = WalletCoreFFIClient.lastErrorMessage() ?? "(none)"
            print("❌ Sweep preview (subaddr \(fromSubaddressMinor)) failed: error=\(error.localizedDescription) walletcore_last_error=\(coreMsg)")
            throw error
        }
    }

    /// Sweep ("Send Max") constrained to a subaddress (account 0, minor).
    func sweep(
        fromSubaddressMinor: UInt32,
        toAddress: String,
        ringLen: UInt8 = 16
    ) throws -> (txid: String, amount: UInt64, fee: UInt64) {
        try withSendLock {
            guard let walletId = currentWalletId else {
                throw WalletError.statusFailed("No wallet is currently open")
            }
            applyBroadcastProxy()

            let endpoint = MoneroConfig.broadcastNodeURL()
            if let recovered = try completePendingPreparedSend(for: walletId, preferredNodeURL: endpoint) {
                return (txid: recovered.txid, amount: recovered.amount, fee: recovered.fee)
            }

            let prepared: WalletCoreFFIClient.PreparedSend
            let usedEndpoint: String
            do {
                (prepared, usedEndpoint) = try prepareSweepWithFilterOptionalSiblingFallback(
                    walletId: walletId,
                    nodeURL: endpoint,
                    ringLen: ringLen,
                    toAddress: toAddress,
                    filter: filterForSubaddressMinor(fromSubaddressMinor)
                )
            } catch {
                let coreMsg = WalletCoreFFIClient.lastErrorMessage() ?? "(none)"
                print("❌ Prepare sweep (subaddr \(fromSubaddressMinor)) failed: error=\(error.localizedDescription) walletcore_last_error=\(coreMsg)")
                throw error
            }

            return try persistAndRelayPrepared(
                walletId: walletId,
                usedEndpoint: usedEndpoint,
                prepared: prepared,
                logLabel: "sweep subaddr \(fromSubaddressMinor)"
            )
        }
    }

    /// Send exact amount constrained to a subaddress (account 0, minor). Fee is added on top (normal behavior).
    func send(
        fromSubaddressMinor: UInt32,
        toAddress: String,
        amountPiconero: UInt64,
        ringLen: UInt8 = 16
    ) throws -> (txid: String, fee: UInt64) {
        try withSendLock {
            guard let walletId = currentWalletId else {
                throw WalletError.statusFailed("No wallet is currently open")
            }
            applyBroadcastProxy()

            let endpoint = MoneroConfig.broadcastNodeURL()
            if let recovered = try completePendingPreparedSend(for: walletId, preferredNodeURL: endpoint) {
                return (txid: recovered.txid, fee: recovered.fee)
            }

            let dest = WalletCoreFFIClient.Destination(address: toAddress, amount: amountPiconero)
            let prepared: WalletCoreFFIClient.PreparedSend
            let usedEndpoint: String
            do {
                (prepared, usedEndpoint) = try prepareSendWithFilterOptionalSiblingFallback(
                    walletId: walletId,
                    nodeURL: endpoint,
                    ringLen: ringLen,
                    destinations: [dest],
                    filter: filterForSubaddressMinor(fromSubaddressMinor)
                )
            } catch {
                let coreMsg = WalletCoreFFIClient.lastErrorMessage() ?? "(none)"
                print("❌ Prepare send (subaddr \(fromSubaddressMinor)) failed: error=\(error.localizedDescription) walletcore_last_error=\(coreMsg)")
                throw error
            }

            let result = try persistAndRelayPrepared(
                walletId: walletId,
                usedEndpoint: usedEndpoint,
                prepared: prepared,
                logLabel: "send subaddr \(fromSubaddressMinor)"
            )
            return (txid: result.txid, fee: result.fee)
        }
    }

    /// Preview sweep ("Send Max") to a destination.
    /// - Returns: (amount, fee) in piconero where `amount` is computed by the core (roughly unlocked - fee).
    func previewSweep(toAddress: String, ringLen: UInt8 = 16) throws -> (amount: UInt64, fee: UInt64) {
        guard let walletId = currentWalletId else {
            throw WalletError.statusFailed("No wallet is currently open")
        }
        applyBroadcastProxy()

        let policy = MoneroConfig.networkPolicy
        let endpoint = MoneroConfig.broadcastNodeURL()
        let proxyDesc = MoneroConfig.i2pHTTPProxyAddress ?? "(none)"
        if let (total, unlocked) = try? getBalance() {
            let totalXMR = Double(total) / 1_000_000_000_000.0
            let unlockedXMR = Double(unlocked) / 1_000_000_000_000.0
            print("🔎 Sweep preview start: ring=\(ringLen), policy=\(policy), broadcast=\(endpoint), proxy=\(proxyDesc), balances total=\(String(format: "%.12f", totalXMR)) XMR, unlocked=\(String(format: "%.12f", unlockedXMR)) XMR")
        } else {
            print("🔎 Sweep preview start: ring=\(ringLen), policy=\(policy), broadcast=\(endpoint), proxy=\(proxyDesc)")
        }

        let res: (amount: UInt64, fee: UInt64)
        do {
            res = try previewSweepOptionalSiblingFallback(
                walletId: walletId,
                nodeURL: endpoint,
                ringLen: ringLen,
                toAddress: toAddress
            )
        } catch {
            let coreMsg = WalletCoreFFIClient.lastErrorMessage() ?? "(none)"
            print("❌ Sweep preview failed: error=\(error.localizedDescription) walletcore_last_error=\(coreMsg)")
            throw error
        }

        let amountXMR = Double(res.amount) / 1_000_000_000_000.0
        let feeXMR = Double(res.fee) / 1_000_000_000_000.0
        print("📦 Sweep preview: amount=\(res.amount) piconero (\(String(format: "%.12f", amountXMR)) XMR), fee=\(res.fee) piconero (\(String(format: "%.12f", feeXMR)) XMR)")

        return res
    }

    /// Sweep ("Send Max") to a destination. Returns (txid, amount, fee).
    func sweep(toAddress: String, ringLen: UInt8 = 16) throws -> (txid: String, amount: UInt64, fee: UInt64) {
        try withSendLock {
            guard let walletId = currentWalletId else {
                throw WalletError.statusFailed("No wallet is currently open")
            }
            applyBroadcastProxy()

            let policy = MoneroConfig.networkPolicy
            let endpoint = MoneroConfig.broadcastNodeURL()
            let proxyDesc = MoneroConfig.i2pHTTPProxyAddress ?? "(none)"
            if let (total, unlocked) = try? getBalance() {
                let totalXMR = Double(total) / 1_000_000_000_000.0
                let unlockedXMR = Double(unlocked) / 1_000_000_000_000.0
                print("📤 Sweep start: ring=\(ringLen), policy=\(policy), broadcast=\(endpoint), proxy=\(proxyDesc), balances total=\(String(format: "%.12f", totalXMR)) XMR, unlocked=\(String(format: "%.12f", unlockedXMR)) XMR")
            } else {
                print("📤 Sweep start: ring=\(ringLen), policy=\(policy), broadcast=\(endpoint), proxy=\(proxyDesc)")
            }

            if let recovered = try completePendingPreparedSend(for: walletId, preferredNodeURL: endpoint) {
                return (txid: recovered.txid, amount: recovered.amount, fee: recovered.fee)
            }

            let prepared: WalletCoreFFIClient.PreparedSend
            let usedEndpoint: String
            do {
                (prepared, usedEndpoint) = try prepareSweepOptionalSiblingFallback(
                    walletId: walletId,
                    nodeURL: endpoint,
                    ringLen: ringLen,
                    toAddress: toAddress
                )
            } catch {
                let coreMsg = WalletCoreFFIClient.lastErrorMessage() ?? "(none)"
                print("❌ Prepare sweep failed: error=\(error.localizedDescription) walletcore_last_error=\(coreMsg)")
                throw error
            }

            let result = try persistAndRelayPrepared(
                walletId: walletId,
                usedEndpoint: usedEndpoint,
                prepared: prepared,
                logLabel: "sweep"
            )
            print("✅ Swept txid=\(result.txid), amount=\(result.amount) piconero, fee=\(result.fee) piconero via \(policy) endpoint \(usedEndpoint)")
            return result
        }
    }

    /// Send to a single destination honoring broadcast policy (clearnet, I2P, or hybrid).
    ///
    /// Exact / filtered / sweep sends all use prepare → durable persist → relay so a crash
    /// between signing and broadcast can be retried idempotently.
    func send(toAddress: String, amountPiconero: UInt64, ringLen: UInt8 = 16) throws -> (txid: String, fee: UInt64) {
        try withSendLock {
            guard let walletId = currentWalletId else {
                throw WalletError.statusFailed("No wallet is currently open")
            }
            applyBroadcastProxy()

            // Verbose logging: amount, policy, endpoint, proxy, balances
            let policy = MoneroConfig.networkPolicy
            let endpoint = MoneroConfig.broadcastNodeURL()
            let proxyDesc = MoneroConfig.i2pHTTPProxyAddress ?? "(none)"
            let amountXMR = Double(amountPiconero) / 1_000_000_000_000.0
            if let (total, unlocked) = try? getBalance() {
                let totalXMR = Double(total) / 1_000_000_000_000.0
                let unlockedXMR = Double(unlocked) / 1_000_000_000_000.0
                print("📤 Send start: amount=\(String(format: "%.12f", amountXMR)) XMR, ring=\(ringLen), policy=\(policy), broadcast=\(endpoint), proxy=\(proxyDesc), balances total=\(String(format: "%.12f", totalXMR)) XMR, unlocked=\(String(format: "%.12f", unlockedXMR)) XMR")
            } else {
                print("📤 Send start: amount=\(String(format: "%.12f", amountXMR)) XMR, ring=\(ringLen), policy=\(policy), broadcast=\(endpoint), proxy=\(proxyDesc)")
            }

            // Finish any prior prepared payload. Do not also construct a new tx in this tap.
            if let recovered = try completePendingPreparedSend(for: walletId, preferredNodeURL: endpoint) {
                return (txid: recovered.txid, fee: recovered.fee)
            }

            let prepared: WalletCoreFFIClient.PreparedSend
            let usedEndpoint: String
            do {
                (prepared, usedEndpoint) = try prepareOptionalSiblingFallback(
                    walletId: walletId,
                    nodeURL: endpoint,
                    ringLen: ringLen,
                    toAddress: toAddress,
                    amountPiconero: amountPiconero
                )
            } catch {
                let coreMsg = WalletCoreFFIClient.lastErrorMessage() ?? "(none)"
                print("❌ Prepare send failed: error=\(error.localizedDescription) walletcore_last_error=\(coreMsg)")
                throw error
            }

            try persistPendingPrepared(for: walletId, nodeURL: usedEndpoint, prepared: prepared)

            let relay: WalletCoreFFIClient.RelayResult
            do {
                relay = try WalletCoreFFIClient.relayPrepared(
                    walletId: walletId,
                    prepared: prepared,
                    nodeURL: usedEndpoint
                )
            } catch {
                let coreMsg = WalletCoreFFIClient.lastErrorMessage() ?? "(none)"
                print("❌ Relay prepared failed: error=\(error.localizedDescription) walletcore_last_error=\(coreMsg)")
                throw error
            }

            clearPendingPrepared(for: walletId)

            let feeXMR = Double(prepared.fee) / 1_000_000_000_000.0
            print("✅ Sent txid=\(relay.txid) status=\(relay.status), fee=\(prepared.fee) piconero (\(String(format: "%.12f", feeXMR)) XMR) via \(policy) endpoint \(usedEndpoint)")

            exportCacheAndPersist(for: walletId)
            print("🗂️ Cache export reason: send walletId=\(walletId)")

            return (txid: relay.txid, fee: prepared.fee)
        }
    }

    /// Persist a prepared payload, relay it, clear the durable file, and export cache.
    private func persistAndRelayPrepared(
        walletId: String,
        usedEndpoint: String,
        prepared: WalletCoreFFIClient.PreparedSend,
        logLabel: String
    ) throws -> (txid: String, amount: UInt64, fee: UInt64) {
        try persistPendingPrepared(for: walletId, nodeURL: usedEndpoint, prepared: prepared)
        let relay: WalletCoreFFIClient.RelayResult
        do {
            relay = try WalletCoreFFIClient.relayPrepared(
                walletId: walletId,
                prepared: prepared,
                nodeURL: usedEndpoint
            )
        } catch {
            let coreMsg = WalletCoreFFIClient.lastErrorMessage() ?? "(none)"
            print("❌ Relay prepared (\(logLabel)) failed: error=\(error.localizedDescription) walletcore_last_error=\(coreMsg)")
            throw error
        }
        clearPendingPrepared(for: walletId)
        print("✅ \(logLabel) relayed txid=\(relay.txid) status=\(relay.status) fee=\(prepared.fee)")
        exportCacheAndPersist(for: walletId)
        print("🗂️ Cache export reason: \(logLabel) walletId=\(walletId)")
        return (txid: relay.txid, amount: prepared.amount, fee: prepared.fee)
    }

    private func siblingMonerodURLIfNeeded(for endpoint: String) -> String? {
        SendSafety.siblingMonerodURLIfNeeded(for: endpoint)
    }

    private func isFeeRateFailure(_ text: String) -> Bool {
        SendSafety.isFeeRateFailure(text)
    }

    /// Errors that imply construction/broadcast may have progressed past fee estimation.
    private func looksLikePostBroadcastOrSpendFailure(_ text: String) -> Bool {
        SendSafety.looksLikePostBroadcastOrSpendFailure(text)
    }

    private func shouldRetryViaSiblingMonerod(error: Error, coreMessage: String, endpoint: String) -> String? {
        SendSafety.shouldRetryViaSiblingMonerod(
            errorText: error.localizedDescription,
            coreMessage: coreMessage,
            endpoint: endpoint
        )
    }

    /// Broadcast-path sibling retry: only when fee_rate failed before any spend/broadcast signal.
    private func shouldRetryBroadcastViaSiblingMonerod(error: Error, coreMessage: String, endpoint: String) -> String? {
        shouldRetryViaSiblingMonerod(error: error, coreMessage: coreMessage, endpoint: endpoint)
    }

    private func previewFeeWithOptionalSiblingFallback(
        walletId: String,
        nodeURL: String,
        ringLen: UInt8,
        destinations: [WalletCoreFFIClient.Destination]
    ) throws -> UInt64 {
        do {
            return try WalletCoreFFIClient.previewFee(
                walletId: walletId,
                destinations: destinations,
                ringLen: ringLen,
                nodeURL: nodeURL
            )
        } catch {
            let coreMsg = WalletCoreFFIClient.lastErrorMessage() ?? ""
            guard let fallbackURL = shouldRetryViaSiblingMonerod(error: error, coreMessage: coreMsg, endpoint: nodeURL) else {
                throw error
            }

            print("↩️ Preview fee retry: Fee RPC unavailable at \(nodeURL); retrying via sibling Monero RPC \(fallbackURL)")
            return try WalletCoreFFIClient.previewFee(
                walletId: walletId,
                destinations: destinations,
                ringLen: ringLen,
                nodeURL: fallbackURL
            )
        }
    }

    private func previewFeeWithFilterOptionalSiblingFallback(
        walletId: String,
        nodeURL: String,
        ringLen: UInt8,
        destinations: [WalletCoreFFIClient.Destination],
        filter: [String: Any]
    ) throws -> UInt64 {
        do {
            return try WalletCoreFFIClient.previewFeeWithFilter(
                walletId: walletId,
                destinations: destinations,
                filter: filter,
                ringLen: ringLen,
                nodeURL: nodeURL
            )
        } catch {
            let coreMsg = WalletCoreFFIClient.lastErrorMessage() ?? ""
            guard let fallbackURL = shouldRetryViaSiblingMonerod(error: error, coreMessage: coreMsg, endpoint: nodeURL) else {
                throw error
            }

            print("↩️ Preview fee (filtered) retry: Fee RPC unavailable at \(nodeURL); retrying via sibling Monero RPC \(fallbackURL)")
            return try WalletCoreFFIClient.previewFeeWithFilter(
                walletId: walletId,
                destinations: destinations,
                filter: filter,
                ringLen: ringLen,
                nodeURL: fallbackURL
            )
        }
    }

    private func previewSweepOptionalSiblingFallback(
        walletId: String,
        nodeURL: String,
        ringLen: UInt8,
        toAddress: String
    ) throws -> (amount: UInt64, fee: UInt64) {
        do {
            return try WalletCoreFFIClient.previewSweep(
                walletId: walletId,
                toAddress: toAddress,
                ringLen: ringLen,
                nodeURL: nodeURL
            )
        } catch {
            let coreMsg = WalletCoreFFIClient.lastErrorMessage() ?? ""
            guard let fallbackURL = shouldRetryViaSiblingMonerod(error: error, coreMessage: coreMsg, endpoint: nodeURL) else {
                throw error
            }

            print("↩️ Sweep preview retry: Fee RPC unavailable at \(nodeURL); retrying via sibling Monero RPC \(fallbackURL)")
            return try WalletCoreFFIClient.previewSweep(
                walletId: walletId,
                toAddress: toAddress,
                ringLen: ringLen,
                nodeURL: fallbackURL
            )
        }
    }

    private func previewSweepWithFilterOptionalSiblingFallback(
        walletId: String,
        nodeURL: String,
        ringLen: UInt8,
        toAddress: String,
        filter: [String: Any]
    ) throws -> (amount: UInt64, fee: UInt64) {
        do {
            return try WalletCoreFFIClient.previewSweepWithFilter(
                walletId: walletId,
                toAddress: toAddress,
                filter: filter,
                ringLen: ringLen,
                nodeURL: nodeURL
            )
        } catch {
            let coreMsg = WalletCoreFFIClient.lastErrorMessage() ?? ""
            guard let fallbackURL = shouldRetryViaSiblingMonerod(error: error, coreMessage: coreMsg, endpoint: nodeURL) else {
                throw error
            }

            print("↩️ Sweep preview (filtered) retry: Fee RPC unavailable at \(nodeURL); retrying via sibling Monero RPC \(fallbackURL)")
            return try WalletCoreFFIClient.previewSweepWithFilter(
                walletId: walletId,
                toAddress: toAddress,
                filter: filter,
                ringLen: ringLen,
                nodeURL: fallbackURL
            )
        }
    }

    private func prepareOptionalSiblingFallback(
        walletId: String,
        nodeURL: String,
        ringLen: UInt8,
        toAddress: String,
        amountPiconero: UInt64
    ) throws -> (WalletCoreFFIClient.PreparedSend, String) {
        do {
            let prepared = try WalletCoreFFIClient.prepareSend(
                walletId: walletId,
                toAddress: toAddress,
                amountPiconero: amountPiconero,
                ringLen: ringLen,
                nodeURL: nodeURL
            )
            return (prepared, nodeURL)
        } catch {
            let coreMsg = WalletCoreFFIClient.lastErrorMessage() ?? ""
            guard let fallbackURL = shouldRetryViaSiblingMonerod(error: error, coreMessage: coreMsg, endpoint: nodeURL) else {
                throw error
            }

            print("↩️ Prepare send retry: Fee RPC unavailable at \(nodeURL); retrying via sibling Monero RPC \(fallbackURL)")
            let prepared = try WalletCoreFFIClient.prepareSend(
                walletId: walletId,
                toAddress: toAddress,
                amountPiconero: amountPiconero,
                ringLen: ringLen,
                nodeURL: fallbackURL
            )
            return (prepared, fallbackURL)
        }
    }

    private func prepareSendWithFilterOptionalSiblingFallback(
        walletId: String,
        nodeURL: String,
        ringLen: UInt8,
        destinations: [WalletCoreFFIClient.Destination],
        filter: [String: Any]
    ) throws -> (WalletCoreFFIClient.PreparedSend, String) {
        do {
            let prepared = try WalletCoreFFIClient.prepareSendWithFilter(
                walletId: walletId,
                destinations: destinations,
                filter: filter,
                ringLen: ringLen,
                nodeURL: nodeURL
            )
            return (prepared, nodeURL)
        } catch {
            let coreMsg = WalletCoreFFIClient.lastErrorMessage() ?? ""
            guard let fallbackURL = shouldRetryViaSiblingMonerod(error: error, coreMessage: coreMsg, endpoint: nodeURL) else {
                throw error
            }

            print("↩️ Prepare send (filtered) retry: Fee RPC unavailable at \(nodeURL); retrying via sibling Monero RPC \(fallbackURL)")
            let prepared = try WalletCoreFFIClient.prepareSendWithFilter(
                walletId: walletId,
                destinations: destinations,
                filter: filter,
                ringLen: ringLen,
                nodeURL: fallbackURL
            )
            return (prepared, fallbackURL)
        }
    }

    private func prepareSweepOptionalSiblingFallback(
        walletId: String,
        nodeURL: String,
        ringLen: UInt8,
        toAddress: String
    ) throws -> (WalletCoreFFIClient.PreparedSend, String) {
        do {
            let prepared = try WalletCoreFFIClient.prepareSweep(
                walletId: walletId,
                toAddress: toAddress,
                ringLen: ringLen,
                nodeURL: nodeURL
            )
            return (prepared, nodeURL)
        } catch {
            let coreMsg = WalletCoreFFIClient.lastErrorMessage() ?? ""
            guard let fallbackURL = shouldRetryViaSiblingMonerod(error: error, coreMessage: coreMsg, endpoint: nodeURL) else {
                throw error
            }

            print("↩️ Prepare sweep retry: Fee RPC unavailable at \(nodeURL); retrying via sibling Monero RPC \(fallbackURL)")
            let prepared = try WalletCoreFFIClient.prepareSweep(
                walletId: walletId,
                toAddress: toAddress,
                ringLen: ringLen,
                nodeURL: fallbackURL
            )
            return (prepared, fallbackURL)
        }
    }

    private func prepareSweepWithFilterOptionalSiblingFallback(
        walletId: String,
        nodeURL: String,
        ringLen: UInt8,
        toAddress: String,
        filter: [String: Any]
    ) throws -> (WalletCoreFFIClient.PreparedSend, String) {
        do {
            let prepared = try WalletCoreFFIClient.prepareSweepWithFilter(
                walletId: walletId,
                toAddress: toAddress,
                filter: filter,
                ringLen: ringLen,
                nodeURL: nodeURL
            )
            return (prepared, nodeURL)
        } catch {
            let coreMsg = WalletCoreFFIClient.lastErrorMessage() ?? ""
            guard let fallbackURL = shouldRetryViaSiblingMonerod(error: error, coreMessage: coreMsg, endpoint: nodeURL) else {
                throw error
            }

            print("↩️ Prepare sweep (filtered) retry: Fee RPC unavailable at \(nodeURL); retrying via sibling Monero RPC \(fallbackURL)")
            let prepared = try WalletCoreFFIClient.prepareSweepWithFilter(
                walletId: walletId,
                toAddress: toAddress,
                filter: filter,
                ringLen: ringLen,
                nodeURL: fallbackURL
            )
            return (prepared, fallbackURL)
        }
    }
}
