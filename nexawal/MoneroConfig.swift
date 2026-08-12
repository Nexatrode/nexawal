import Foundation
import NexaWalLogic

// MoneroConfig — simplified to wallet2-like defaults.
// - Only keeps node address, gap limits, account lookahead, and basic network policy.
// - Scan/bulk tuning knobs remain as no-ops/stored prefs for UI compatibility but do not enforce behavior.
// - Logging is controlled by the caller; no automatic env churn here.
struct MoneroConfig {

    // MARK: - Constants / Defaults
    nonisolated static let defaultAddress = "https://rpc.nexatrode.com"
    nonisolated static let userDefaultsKey = "monero_daemon_address"

    // I2P keys (no shipped I2P node — user fills this in)
    nonisolated static let userDefaultsI2PModeKey = "monero_i2p_mode"
    nonisolated static let userDefaultsI2PRPCKey = "monero_i2p_rpc_address"
    nonisolated static let userDefaultsI2PProxyKey = "monero_i2p_http_proxy"

    // Gap limits
    nonisolated static let userDefaultsGapLimitKey = "monero_gap_limit"
    nonisolated static let defaultGapLimit: UInt32 = 50
    nonisolated static let userDefaultsAccountGapKey = "walletcore_account_gap"
    nonisolated static let defaultAccountGap: Int = 1

    // Network policy (kept minimal: clearnet / i2p / hybrid)
    nonisolated static let userDefaultsNetworkPolicyKey = "monero_network_policy"
    nonisolated static let defaultNetworkPolicyRaw = "clearnet"
    enum NetworkPolicy: String {
        case clearnet
        case i2p
        case hybrid
    }

    // Scan mode (UI compatibility; no behavior impact here)
    nonisolated static let userDefaultsScanModeKey = "monero_scan_mode"
    nonisolated static let defaultScanModeRaw = "auto"
    enum ScanMode: String {
        case auto
        case manual
    }

    // Scan tuning (UI compatibility; wallet2 baseline leaves these unused)
    nonisolated static let userDefaultsScanParKey = "walletcore_scan_par"
    nonisolated static let userDefaultsScanBatchKey = "walletcore_scan_batch"
    nonisolated static let defaultScanPar: Int = 0
    nonisolated static let defaultScanBatch: Int = 200

    // Bulk toggle (UI compatibility; core defaults take precedence)
    nonisolated static let userDefaultsBulkBinFetchKey = "walletcore_bulk_bin_fetch"
    nonisolated static let defaultBulkBinFetchEnabled: Bool = true

    // Wallet2 bulk lockout (kept as stubs to avoid crashes if called)
    nonisolated private static let userDefaultsWallet2LockoutsKey = "monero_wallet2_bulk_lockouts_v1"
    nonisolated private static let wallet2LockoutDefaultSeconds: TimeInterval = 60 * 30

    // Appearance: Techno Theme ON = neon terminal look; OFF (default) = standard look.
    nonisolated static let userDefaultsTechnoThemeKey = "ui_techno_theme"
    nonisolated static let userDefaultsClassicUIKeyLegacy = "ui_classic_mode"
    nonisolated static let defaultTechnoThemeEnabled: Bool = false

    nonisolated static let userDefaultsFiatEstimatesEnabledKey = "fiat_estimates_enabled"
    nonisolated static let userDefaultsFiatEstimatesEnabledAtKey = "fiat_estimates_enabled_at_ms"
    nonisolated static let userDefaultsFiatCurrencyKey = "fiat_currency"
    nonisolated static let userDefaultsFiatCurrencyInitializedKey = "fiat_currency_initialized"
    nonisolated static let userDefaultsFiatRateCurrencyKey = "fiat_rate_currency"
    nonisolated static let userDefaultsFiatRatePerXmrKey = "fiat_rate_per_xmr"
    nonisolated static let userDefaultsFiatRateFetchedAtKey = "fiat_rate_fetched_at_ms"
    nonisolated static let userDefaultsFiatRateSourceKey = "fiat_rate_source"

    // Terms acceptance (bump currentTermsVersion when summary or full ToS changes).
    nonisolated static let userDefaultsAcceptedTermsVersionKey = "nexawal_accepted_terms_version"
    nonisolated static let currentTermsVersion: Int = 1
    nonisolated static let termsURLString = "https://nexatrode.com/terms"

    enum WalletError: Error {
        case invalidAddress
        case invalidGapLimit
        case invalidRestoreHeight
    }

    // MARK: - Network policy
    nonisolated static var networkPolicy: NetworkPolicy {
        let raw = UserDefaults.standard.string(forKey: userDefaultsNetworkPolicyKey) ?? defaultNetworkPolicyRaw
        return NetworkPolicy(rawValue: raw) ?? .clearnet
    }

    @MainActor
    static func setNetworkPolicy(_ policy: NetworkPolicy) {
        UserDefaults.standard.set(policy.rawValue, forKey: userDefaultsNetworkPolicyKey)
    }

    // MARK: - Node address helpers
    /// Previous shipped defaults. Matching these (or the live default) means "no override".
    private nonisolated static let legacyDefaultAddresses: Set<String> = [
        "rpc.nexatrode.com",
        "http://rpc.nexatrode.com",
        "http://rpc.nexatrode.com:443",
        "https://rpc.nexatrode.com",
        "cuprate.nexatrode.com",
        "http://cuprate.nexatrode.com",
        "https://cuprate.nexatrode.com",
        "https://cuprate.nexatrode.com/",
        "monero.nexatrode.com",
        "http://monero.nexatrode.com",
        "https://monero.nexatrode.com",
        "https://monero.nexatrode.com/",
        "node.sethforprivacy.com:443",
        "https://node.sethforprivacy.com:443",
        "node.monerod.org:443",
        "https://node.monerod.org:443",
        "mini.nexatrode.com:18089",
        "http://mini.nexatrode.com:18089",
        "https://mini.nexatrode.com:18089",
        "mini.nexatrode.com:18092",
        "http://mini.nexatrode.com:18092",
        "https://mini.nexatrode.com:18092",
    ]

    nonisolated static func isShippedDefaultAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let folded = trimmed.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let live = defaultAddress.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if folded == live { return true }
        return legacyDefaultAddresses.contains(trimmed)
    }

    nonisolated static var daemonAddress: String {
        if let saved = UserDefaults.standard.string(forKey: userDefaultsKey), !saved.isEmpty {
            if isShippedDefaultAddress(saved) {
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
                return defaultAddress
            }
            return saved
        }
        return defaultAddress
    }

    @MainActor
    static func setDaemonAddress(_ address: String) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if isShippedDefaultAddress(trimmed) {
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: userDefaultsKey)
        }
    }

    private nonisolated static func urlFromAddress(_ address: String) -> String {
        NetworkRouting.normalizeURL(address)
    }

    nonisolated static func scanNodeAddress() -> String {
        NetworkRouting.scanNodeAddress(
            policy: NetworkRouting.Policy(rawValue: networkPolicy.rawValue) ?? .clearnet,
            clearnetNodeAddress: daemonAddress,
            i2pRPCAddress: i2pRPCAddress
        )
    }

    nonisolated static func broadcastNodeAddress() -> String {
        NetworkRouting.broadcastNodeAddress(
            policy: NetworkRouting.Policy(rawValue: networkPolicy.rawValue) ?? .clearnet,
            clearnetNodeAddress: daemonAddress,
            i2pRPCAddress: i2pRPCAddress
        )
    }

    nonisolated static func shouldUseI2PHTTPProxy(forBroadcast: Bool) -> Bool {
        NetworkRouting.shouldUseI2PHTTPProxy(
            policy: NetworkRouting.Policy(rawValue: networkPolicy.rawValue) ?? .clearnet,
            proxyConfigured: !(i2pHTTPProxyAddress ?? "").isEmpty,
            forBroadcast: forBroadcast
        )
    }

    nonisolated static func scanNodeURL() -> String {
        // Apply account lookahead for the core.
        setenv("WALLETCORE_ACCOUNT_GAP", "\(accountGap)", 1)
        return urlFromAddress(scanNodeAddress())
    }

    nonisolated static func broadcastNodeURL() -> String {
        urlFromAddress(broadcastNodeAddress())
    }

    // MARK: - I2P settings (UI compatibility)
    nonisolated static var useI2P: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsI2PModeKey)
    }

    @MainActor
    static func setUseI2P(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: userDefaultsI2PModeKey)
    }

    private nonisolated static let legacyDefaultI2PRPCAddresses: Set<String> = [
        "cvxtgqjorfif6i5x5fenys6fj7hzddbgavpyutps6gphywnlklqa.b32.i2p:18081",
    ]

    nonisolated static var i2pRPCAddress: String {
        let saved = UserDefaults.standard.string(forKey: userDefaultsI2PRPCKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if saved.isEmpty { return "" }
        if legacyDefaultI2PRPCAddresses.contains(saved.lowercased()) {
            UserDefaults.standard.removeObject(forKey: userDefaultsI2PRPCKey)
            return ""
        }
        return saved
    }

    @MainActor
    static func setI2PRPCAddress(_ address: String) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: userDefaultsI2PRPCKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: userDefaultsI2PRPCKey)
        }
    }

    nonisolated static var i2pHTTPProxyAddress: String? {
        if let saved = UserDefaults.standard.string(forKey: userDefaultsI2PProxyKey), !saved.isEmpty {
            return saved
        }
        return nil
    }

    @MainActor
    static func setI2PHTTPProxyAddress(_ address: String?) {
        if let addr = address, !addr.isEmpty {
            UserDefaults.standard.set(addr, forKey: userDefaultsI2PProxyKey)
        } else {
            UserDefaults.standard.removeObject(forKey: userDefaultsI2PProxyKey)
        }
    }

    // MARK: - Terms acceptance
    nonisolated static var acceptedTermsVersion: Int {
        UserDefaults.standard.integer(forKey: userDefaultsAcceptedTermsVersionKey)
    }

    nonisolated static var needsTermsAcceptance: Bool {
        acceptedTermsVersion < currentTermsVersion
    }

    nonisolated static func acceptCurrentTerms() {
        UserDefaults.standard.set(currentTermsVersion, forKey: userDefaultsAcceptedTermsVersionKey)
    }

    nonisolated static var termsURL: URL {
        URL(string: termsURLString)!
    }

    // MARK: - Appearance
    /// One-shot migration from legacy Classic UI (inverted) into Techno Theme.
    nonisolated static func migrateAppearancePreferenceIfNeeded() {
        guard UserDefaults.standard.object(forKey: userDefaultsTechnoThemeKey) == nil else { return }
        guard UserDefaults.standard.object(forKey: userDefaultsClassicUIKeyLegacy) != nil else { return }
        let techno = !UserDefaults.standard.bool(forKey: userDefaultsClassicUIKeyLegacy)
        UserDefaults.standard.set(techno, forKey: userDefaultsTechnoThemeKey)
        UserDefaults.standard.removeObject(forKey: userDefaultsClassicUIKeyLegacy)
    }

    nonisolated static var technoThemeEnabled: Bool {
        migrateAppearancePreferenceIfNeeded()
        if UserDefaults.standard.object(forKey: userDefaultsTechnoThemeKey) != nil {
            return UserDefaults.standard.bool(forKey: userDefaultsTechnoThemeKey)
        }
        return defaultTechnoThemeEnabled
    }

    @MainActor
    static func setTechnoThemeEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: userDefaultsTechnoThemeKey)
        UserDefaults.standard.removeObject(forKey: userDefaultsClassicUIKeyLegacy)
    }

    // MARK: - Fiat estimates
    nonisolated static var fiatEstimatesEnabled: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsFiatEstimatesEnabledKey)
    }

    nonisolated static var fiatCurrencyInitialized: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsFiatCurrencyInitializedKey)
    }

    nonisolated static var fiatCurrency: String {
        let raw = UserDefaults.standard.string(forKey: userDefaultsFiatCurrencyKey) ?? ""
        if FiatEstimate.isSupported(raw) { return raw.uppercased() }
        return FiatEstimate.hintedCurrency(localeCurrencyCode: Locale.current.currency?.identifier)
    }

    nonisolated static var routingPolicy: NetworkRouting.Policy {
        NetworkRouting.Policy.fromRaw(networkPolicy.rawValue)
    }

    @MainActor
    static func setFiatCurrency(_ code: String) {
        let normalized = FiatEstimate.isSupported(code) ? code.uppercased() : "USD"
        UserDefaults.standard.set(normalized, forKey: userDefaultsFiatCurrencyKey)
        UserDefaults.standard.set(true, forKey: userDefaultsFiatCurrencyInitializedKey)
    }

    nonisolated static var fiatEstimatesEnabledAtMs: Int64 {
        Int64(UserDefaults.standard.double(forKey: userDefaultsFiatEstimatesEnabledAtKey))
    }

    @MainActor
    static func setFiatEstimatesEnabled(_ enabled: Bool) {
        if enabled && !fiatCurrencyInitialized {
            setFiatCurrency(FiatEstimate.hintedCurrency(localeCurrencyCode: Locale.current.currency?.identifier))
        }
        if enabled && fiatEstimatesEnabledAtMs <= 0 {
            UserDefaults.standard.set(Date().timeIntervalSince1970 * 1000, forKey: userDefaultsFiatEstimatesEnabledAtKey)
        }
        UserDefaults.standard.set(enabled, forKey: userDefaultsFiatEstimatesEnabledKey)
    }

    @MainActor
    @discardableResult
    static func ensureFiatEstimatesEnabledAtMs() -> Int64 {
        let stored = fiatEstimatesEnabledAtMs
        if stored > 0 { return stored }
        guard fiatEstimatesEnabled else { return 0 }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        UserDefaults.standard.set(Double(now), forKey: userDefaultsFiatEstimatesEnabledAtKey)
        return now
    }

    nonisolated static func cachedFiatRate() -> FiatRate? {
        guard let currency = UserDefaults.standard.string(forKey: userDefaultsFiatRateCurrencyKey),
              FiatEstimate.isSupported(currency),
              let raw = UserDefaults.standard.string(forKey: userDefaultsFiatRatePerXmrKey),
              let perXmr = FiatEstimate.decimal(from: raw)
        else {
            return nil
        }
        let fetchedAt = Int64(UserDefaults.standard.double(forKey: userDefaultsFiatRateFetchedAtKey))
        let source = UserDefaults.standard.string(forKey: userDefaultsFiatRateSourceKey) ?? "kraken"
        return FiatRate(currency: currency, fiatPerXmr: perXmr, fetchedAtMs: fetchedAt, source: source)
    }

    @MainActor
    static func setCachedFiatRate(_ rate: FiatRate?) {
        if let rate {
            UserDefaults.standard.set(rate.currency, forKey: userDefaultsFiatRateCurrencyKey)
            UserDefaults.standard.set(FiatEstimate.decimalString(rate.fiatPerXmr), forKey: userDefaultsFiatRatePerXmrKey)
            UserDefaults.standard.set(Double(rate.fetchedAtMs), forKey: userDefaultsFiatRateFetchedAtKey)
            UserDefaults.standard.set(rate.source, forKey: userDefaultsFiatRateSourceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: userDefaultsFiatRateCurrencyKey)
            UserDefaults.standard.removeObject(forKey: userDefaultsFiatRatePerXmrKey)
            UserDefaults.standard.removeObject(forKey: userDefaultsFiatRateFetchedAtKey)
            UserDefaults.standard.removeObject(forKey: userDefaultsFiatRateSourceKey)
        }
    }

    // MARK: - Gap limits
    nonisolated static var gapLimit: UInt32 {
        let v = UserDefaults.standard.integer(forKey: userDefaultsGapLimitKey)
        let value = (v > 0 ? v : Int(defaultGapLimit))
        let clamped = max(1, min(value, 100_000))
        return UInt32(clamped)
    }

    @MainActor
    static func setGapLimit(_ limit: UInt32) {
        let clamped = min(max(limit, 1), 100_000)
        UserDefaults.standard.set(Int(clamped), forKey: userDefaultsGapLimitKey)
    }

    nonisolated static var accountGap: Int {
        let v = UserDefaults.standard.integer(forKey: userDefaultsAccountGapKey)
        let value = (v > 0 ? v : defaultAccountGap)
        return max(1, min(value, 1_000))
    }

    @MainActor
    static func setAccountGap(_ gap: Int) {
        let clamped = max(1, min(gap, 1_000))
        UserDefaults.standard.set(clamped, forKey: userDefaultsAccountGapKey)
    }

    // MARK: - Scan mode/tuning (UI compatibility; no-op defaults)
    nonisolated static var scanMode: ScanMode {
        let raw = UserDefaults.standard.string(forKey: userDefaultsScanModeKey) ?? defaultScanModeRaw
        return ScanMode(rawValue: raw) ?? .auto
    }

    @MainActor
    static func setScanMode(_ mode: ScanMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: userDefaultsScanModeKey)
    }

    nonisolated static var scanParallelism: Int {
        let v = UserDefaults.standard.integer(forKey: userDefaultsScanParKey)
        return max(0, min(v == 0 ? defaultScanPar : v, 64))
    }

    @MainActor
    static func setScanParallelism(_ par: Int) {
        let clamped = max(0, min(par, 64))
        UserDefaults.standard.set(clamped, forKey: userDefaultsScanParKey)
    }

    nonisolated static var scanBatchSize: Int {
        let v = UserDefaults.standard.integer(forKey: userDefaultsScanBatchKey)
        return max(50, min(v == 0 ? defaultScanBatch : v, 5000))
    }

    @MainActor
    static func setScanBatchSize(_ batch: Int) {
        let clamped = max(50, min(batch, 5000))
        UserDefaults.standard.set(clamped, forKey: userDefaultsScanBatchKey)
    }

    nonisolated static var bulkBinFetchEnabled: Bool {
        UserDefaults.standard.object(forKey: userDefaultsBulkBinFetchKey) as? Bool ?? defaultBulkBinFetchEnabled
    }

    @MainActor
    static func setBulkBinFetchEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: userDefaultsBulkBinFetchKey)
    }

    // Feather-like baseline: just return current par/batch values
    nonisolated static func chooseTuningForCurrentNode() -> (par: Int, batch: Int) {
        (scanParallelism, scanBatchSize)
    }

    // MARK: - Wallet2 bulk lockout (stubbed, kept for API compatibility)
    nonisolated private static func wallet2LockoutNodeKey() -> String {
        effectiveNodeAddress()
    }

    nonisolated private static func loadWallet2Lockouts() -> [String: TimeInterval] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsWallet2LockoutsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: TimeInterval].self, from: data)) ?? [:]
    }

    @MainActor
    private static func saveWallet2Lockouts(_ map: [String: TimeInterval]) {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: userDefaultsWallet2LockoutsKey)
        }
    }

    nonisolated static func isWallet2BulkLockedOutForCurrentNode(now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        let key = wallet2LockoutNodeKey()
        let until = loadWallet2Lockouts()[key] ?? 0
        return until > now
    }

    @MainActor
    static func lockOutWallet2BulkForCurrentNode(seconds: TimeInterval = wallet2LockoutDefaultSeconds) {
        let key = wallet2LockoutNodeKey()
        var map = loadWallet2Lockouts()
        let until = Date().addingTimeInterval(seconds).timeIntervalSince1970
        map[key] = until
        saveWallet2Lockouts(map)
    }

    @MainActor
    static func clearWallet2BulkLockoutForCurrentNode() {
        let key = wallet2LockoutNodeKey()
        var map = loadWallet2Lockouts()
        map.removeValue(forKey: key)
        saveWallet2Lockouts(map)
    }

    // MARK: - Utilities
    nonisolated static func effectiveNodeAddress() -> String {
        scanNodeAddress()
    }

    nonisolated static func isDeterministicWallet2DecodeFailure(_ message: String) -> Bool {
        let m = message.lowercased()
        return m.contains("getblocks.bin decode failed in field 'blocks'")
            || m.contains("typed-array elem_type empty appears packed/unsupported")
            || m.contains("marker does not match expected marker")
            || m.contains("data has object with more fields than the maximum allowed")
    }
}
