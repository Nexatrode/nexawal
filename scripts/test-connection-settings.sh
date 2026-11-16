#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/nexawal-connection-settings.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/Sources/ConnectionSettingsHarness" "$test_dir/Tests/ConnectionSettingsTests"
ln -s "$repo_dir/Tests/ConnectionSettingsTests/Package.swift" "$test_dir/Package.swift"
ln -s "$repo_dir/nexawal/MoneroConfig.swift" "$test_dir/Sources/ConnectionSettingsHarness/MoneroConfig.swift"
ln -s "$repo_dir/Tests/ConnectionSettingsTests/ConnectionSettingsTests.swift" "$test_dir/Tests/ConnectionSettingsTests/ConnectionSettingsTests.swift"
NEXAWAL_TEST_ROOT="$repo_dir" swift test --disable-sandbox --package-path "$test_dir"
