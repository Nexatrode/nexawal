import Foundation
import XCTest
@testable import HistoryModelHarness

// This harness has its own preferences domain; it never opens an installed wallet.
@MainActor
final class WalletNodeConfigurationTests: XCTestCase {
    func testBuiltinRPCVariantsCanonicalizeWithoutTouchingCustomNodes() {
        let key = MoneroConfig.userDefaultsKey
        let previous = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }
        XCTAssertEqual(MoneroConfig.defaultAddress, "https://rpc.nexawal.com")
        for variant in ["https://rpc.nexawal.com", " HTTPS://RPC.NEXAWAL.COM/ ",
                        "https://rpc.nexawal.com:443/", "http://rpc.nexawal.com",
                        "http://rpc.nexawal.com:443", "rpc.nexawal.com"] {
            UserDefaults.standard.set(variant, forKey: key)
            XCTAssertEqual(MoneroConfig.daemonAddress, MoneroConfig.defaultAddress)
            XCTAssertNil(UserDefaults.standard.object(forKey: key))
        }
        for custom in ["https://monero.nexatrode.com", "http://127.0.0.1:18081",
                       "http://example.b32.i2p", "https://rpc.nexawal.com/custom",
                       "https://rpc.nexawal.com:18081"] {
            UserDefaults.standard.set(custom, forKey: key)
            XCTAssertEqual(MoneroConfig.daemonAddress, custom)
        }
    }
}
