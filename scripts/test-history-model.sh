#!/bin/bash
set -euo pipefail
# Pass a local Swift package whose matching XCFramework contains the new history API.
core_package="${1:?Usage: test-history-model.sh /path/to/local/MoneroWalletCoreFFI}"
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/nexawal-history-model.XXXXXX)"
mkdir -p "$test_dir/Sources/HistoryModelHarness" "$test_dir/Tests/HistoryModelTests"
ln -s "$repo_dir/Tests/HistoryPagingTests/Package.swift" "$test_dir/Package.swift"
ln -s "$repo_dir/nexawal/TransactionsModel.swift" "$test_dir/Sources/HistoryModelHarness/TransactionsModel.swift"
ln -s "$repo_dir/Tests/HistoryPagingTests/TransactionsModelTests.swift" "$test_dir/Tests/HistoryModelTests/TransactionsModelTests.swift"
NEXAWAL_TEST_ROOT="$repo_dir" NEXAWAL_TEST_WALLETCORE_PACKAGE="$core_package" swift test --package-path "$test_dir"
