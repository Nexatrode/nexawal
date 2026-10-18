import Foundation
import XCTest
@testable import HistoryModelHarness

// This harness has its own preferences domain; it never opens an installed wallet.
@MainActor
final class WalletNodeConfigurationTests: XCTestCase {
    func testPreviousBuiltinRPCMigratesWithoutTouchingCustomNodes() {
        let key = MoneroConfig.userDefaultsKey
        let previous = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }
        XCTAssertEqual(MoneroConfig.defaultAddress, "https://rpc.nexawal.com")
        for old in ["https://rpc.nexatrode.com", " HTTPS://RPC.NEXATRODE.COM/ ",
                    "https://rpc.nexatrode.com:443/", "rpc.nexatrode.com"] {
            UserDefaults.standard.set(old, forKey: key)
            XCTAssertEqual(MoneroConfig.daemonAddress, MoneroConfig.defaultAddress)
            XCTAssertNil(UserDefaults.standard.object(forKey: key))
        }
        for custom in ["https://monero.nexatrode.com", "http://127.0.0.1:18081",
                       "http://example.b32.i2p", "https://rpc.nexatrode.com/custom",
                       "https://rpc.nexatrode.com:18081"] {
            UserDefaults.standard.set(custom, forKey: key)
            XCTAssertEqual(MoneroConfig.daemonAddress, custom)
        }
    }
}
