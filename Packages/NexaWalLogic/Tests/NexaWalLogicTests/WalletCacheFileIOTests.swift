import Foundation
import XCTest
@testable import NexaWalLogic

final class WalletCacheFileIOTests: XCTestCase {
    func testBoundedReadsAcceptExactLimitAndRejectOversize() throws {
        try withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("bounded.cache")
            try Data([1, 2, 3, 4]).write(to: file)
            XCTAssertEqual(try WalletCacheFileIO.readBounded(from: file, limit: 4).count, 4)
            XCTAssertThrowsError(try WalletCacheFileIO.readBounded(from: file, limit: 3))
            XCTAssertThrowsError(try WalletCacheFileIO.readBounded(from: directory, limit: 4))
        }
    }

    private struct Journal: Codable, Equatable {
        let signed: Bool
    }

    func testJSONLoadDistinguishesMissingValidAndMalformedFiles() throws {
        try withTemporaryDirectory { directory in
            let journal = directory.appendingPathComponent("pending.json")
            let missing = try WalletCacheFileIO.loadJSONIfPresent(Journal.self, from: journal)
            XCTAssertNil(missing)

            try Data(#"{"signed":true}"#.utf8).write(to: journal)
            XCTAssertEqual(
                try WalletCacheFileIO.loadJSONIfPresent(Journal.self, from: journal),
                Journal(signed: true)
            )

            try Data("not json".utf8).write(to: journal)
            XCTAssertThrowsError(
                try WalletCacheFileIO.loadJSONIfPresent(Journal.self, from: journal)
            )
        }
    }

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
