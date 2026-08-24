import Foundation
import XCTest
@testable import NexaWalLogic

final class WalletCacheFileIOTests: XCTestCase {
    func testAtomicReplacementPublishesTheCompleteNewCache() throws {
        try withTemporaryDirectory { directory in
            let cache = directory.appendingPathComponent("main_wallet.cache")
            try WalletCacheFileIO.writeAtomically(Data("first complete cache".utf8), to: cache)
            try WalletCacheFileIO.writeAtomically(Data("second complete cache".utf8), to: cache)

            XCTAssertEqual(try Data(contentsOf: cache), Data("second complete cache".utf8))
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .filter { $0.contains(".tmp") }
            XCTAssertTrue(leftovers.isEmpty)
        }
    }

    func testRejectedCachesLeaveTheActiveSlotAndNeverOverwriteEvidence() throws {
        try withTemporaryDirectory { directory in
            let cache = directory.appendingPathComponent("main_wallet.cache")
            try Data("rejected one".utf8).write(to: cache)
            let first = try XCTUnwrap(
                WalletCacheFileIO.quarantineRejectedFile(at: cache, timestampMilliseconds: 1234)
            )

            XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
            XCTAssertEqual(try Data(contentsOf: first), Data("rejected one".utf8))

            try Data("rejected two".utf8).write(to: cache)
            let second = try XCTUnwrap(
                WalletCacheFileIO.quarantineRejectedFile(at: cache, timestampMilliseconds: 1234)
            )
            XCTAssertNotEqual(first, second)
            XCTAssertEqual(try Data(contentsOf: second), Data("rejected two".utf8))
            XCTAssertNil(
                try WalletCacheFileIO.quarantineRejectedFile(at: cache, timestampMilliseconds: 1234)
            )
        }
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexawal-cache-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}
