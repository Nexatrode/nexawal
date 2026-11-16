#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/nexawal-daemon-probes.XXXXXX)"
fixture_pid=""
cleanup() {
    if [[ -n "$fixture_pid" ]]; then
        kill "$fixture_pid" 2>/dev/null || true
        wait "$fixture_pid" 2>/dev/null || true
    fi
    rm -rf "$test_dir"
}
trap cleanup EXIT
mkdir -p "$test_dir/Sources/DaemonProbeHarness" "$test_dir/Tests/DaemonProbeTests"
ln -s "$repo_dir/Tests/DaemonProbeTests/Package.swift" "$test_dir/Package.swift"
ln -s "$repo_dir/nexawal/Networking/MoneroDaemonClient.swift" "$test_dir/Sources/DaemonProbeHarness/MoneroDaemonClient.swift"
ln -s "$repo_dir/nexawal/WalletDiagnostics.swift" "$test_dir/Sources/DaemonProbeHarness/WalletDiagnostics.swift"
ln -s "$repo_dir/Tests/DaemonProbeTests/DaemonProbeTests.swift" "$test_dir/Tests/DaemonProbeTests/DaemonProbeTests.swift"
python3 "$repo_dir/Tests/DaemonProbeTests/fixture.py" "$test_dir/origin" &
fixture_pid=$!
for _ in {1..100}; do
    [[ -s "$test_dir/origin" ]] && break
    kill -0 "$fixture_pid" 2>/dev/null || { echo "Daemon fixture failed to start" >&2; exit 1; }
    sleep 0.05
done
[[ -s "$test_dir/origin" ]] || { echo "Daemon fixture startup timed out" >&2; exit 1; }
export NEXAWAL_TEST_ROOT="$repo_dir"
export NEXAWAL_PROBE_FIXTURE="$(cat "$test_dir/origin")"
swift test --disable-sandbox --package-path "$test_dir"
