//
//  L10n.swift
//  nexawal
//
//  Thin helpers for String Catalog lookups. Neon (classicUI env) uppercases the localized string.
//

import Foundation

/// Localization helpers must be nonisolated: default parameters and storage/errors
/// call these off the main actor (project default isolation is MainActor).
enum L10n {
    nonisolated static func t(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }

    /// Neon terminal chrome uses ALL CAPS of the localized label.
    nonisolated static func neon(_ key: String.LocalizationValue, classicUI: Bool) -> String {
        let value = String(localized: key)
        return classicUI ? value.uppercased() : value
    }

    nonisolated static func format(_ key: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        let format = String(localized: key)
        return String(format: format, locale: .current, arguments: arguments)
    }
}
