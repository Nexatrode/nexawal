//
//  L10n.swift
//  nexawal
//
//  Thin helpers for String Catalog lookups. Neon (classicUI env) uppercases the localized string.
//

import Foundation

enum L10n {
    static func t(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }

    /// Neon terminal chrome uses ALL CAPS of the localized label.
    static func neon(_ key: String.LocalizationValue, classicUI: Bool) -> String {
        let value = String(localized: key)
        return classicUI ? value.uppercased() : value
    }

    static func format(_ key: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        let format = String(localized: key)
        return String(format: format, locale: .current, arguments: arguments)
    }
}
