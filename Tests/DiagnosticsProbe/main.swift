// Compile with WalletDiagnostics.swift, WITHOUT -D DEBUG, and run with
// NEXAWAL_DIAGNOSTICS=1. Release must not even evaluate sensitive log arguments.
var evaluated = false
func sensitiveMessage() -> String {
    evaluated = true
    return "test-only sensitive wallet information"
}
WalletDiagnostics.log(sensitiveMessage())
precondition(!evaluated, "release diagnostics evaluated sensitive data")
