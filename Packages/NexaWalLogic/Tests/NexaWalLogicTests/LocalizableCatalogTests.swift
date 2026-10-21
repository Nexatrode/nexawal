import XCTest

/// App string catalog lives next to NexaWalLogic in the nexawal repo.
/// CI runs `swift test` from Packages/NexaWalLogic, so this path is stable.
final class LocalizableCatalogTests: XCTestCase {
    func testPermissionDescriptionsMatchCatalogLocales() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let app = try catalogURL().deletingLastPathComponent()
        for locale in try locales(in: strings, key: "How to connect") where locale != "en" {
            let url = app.appendingPathComponent("\(locale).lproj/InfoPlist.strings")
            let data = try Data(contentsOf: url)
            let values = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
            for key in ["NSCameraUsageDescription", "NSFaceIDUsageDescription"] {
                XCTAssertFalse(values[key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true, "missing \(locale): \(key)")
            }
        }
    }

    func testAllTranslatableKeysHaveEveryLocaleAndPreserveArguments() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let reference = try locales(in: strings, key: "How to connect")
        for (key, rawEntry) in strings {
            let entry = try XCTUnwrap(rawEntry as? [String: Any])
            if entry["shouldTranslate"] as? Bool == false || key.isEmpty { continue }
            let locs = try locales(in: strings, key: key)
            XCTAssertEqual(locs, reference, "missing locale for \(key)")
            let expected = try arguments(in: key)
            for locale in locs {
                let value = try translatedValue(in: strings, key: key, locale: locale)
                XCTAssertFalse(value.isEmpty, "blank \(locale): \(key)")
                XCTAssertEqual(try arguments(in: value), expected, "format arguments changed in \(locale): \(key)")
            }
        }
    }

    func testArgumentCheckerAllowsReorderingButRejectsMissingValues() throws {
        XCTAssertEqual(try arguments(in: "%@ — %lld"), try arguments(in: "%2$lld — %1$@"))
        XCTAssertNotEqual(try arguments(in: "Fee %@%@"), try arguments(in: "Fee"))
        XCTAssertEqual(try arguments(in: "100%%"), [])
    }

    private func arguments(in text: String) throws -> [String] {
        let text = text.replacingOccurrences(of: "%%", with: "")
        let regex = try NSRegularExpression(pattern: #"%(?:(\d+)\$)?[-+0# ]*\d*(?:\.\d+)?(hh|ll|h|l|z|t|j)?([@diuoxXfFeEgGaAcCsSp])"#)
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).enumerated().map { index, match in
            let position = match.range(at: 1).location == NSNotFound ? String(index + 1) : ns.substring(with: match.range(at: 1))
            let length = match.range(at: 2).location == NSNotFound ? "" : ns.substring(with: match.range(at: 2))
            return position + ":" + length + ns.substring(with: match.range(at: 3))
        }.sorted()
    }

    private let requiredKeys = [
        "Show sync details",
        "Hide sync details",
        "Copy Explorer Link",
        "Clear",
        "Not available",
        "Selected",
        "Optional. When enabled, NexaWal requests an XMR rate for your selected currency from rates.nexawal.com over HTTPS. This request uses clearnet even when the wallet node uses I2P. Nexatrode can see your IP address and selected currency; wallet amounts, addresses, seeds, and transaction history are not sent. Estimates only — XMR is what you send and hold.",
    ]

    func testSyncDetailHintsExistInEveryCatalogLocale() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let reference = try locales(in: strings, key: "How to connect")
        XCTAssertFalse(reference.isEmpty)

        for key in requiredKeys {
            let locs = try locales(in: strings, key: key)
            XCTAssertEqual(
                locs,
                reference,
                "\(key) must have the same locales as the rest of the catalog"
            )
            for locale in locs.sorted() {
                let value = try translatedValue(in: strings, key: key, locale: locale)
                XCTAssertFalse(value.isEmpty, "blank \(locale) value for \(key)")
            }
        }
    }

    func testSpanishTotalAndPrivacyCopyAreAccurate() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])

        let total = try translatedValue(in: strings, key: "Total (amount + fee)", locale: "es")
        XCTAssertEqual(total, "Total (cantidad + comisión)")

        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."
        let privacy = try translatedValue(in: strings, key: privacyKey, locale: "es")
        XCTAssertTrue(privacy.contains("su dirección IP y las consultas de sincronización de su cartera"))
        XCTAssertTrue(privacy.contains("rates.nexawal.com"))
        XCTAssertFalse(privacy.contains("sincronización de IP"))

        let sendMaxKey = "Send maximum spendable after fee to %@.\nPreview amount: %@\nEstimated fee: %@\nFinal amount is recalculated at send time."
        let sendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "es")
        XCTAssertEqual(sendMax, "Envía el máximo que se puede gastar después de pagar la comisión a %@.\nImporte de la vista previa: %@\nComisión estimada: %@\nEl importe final se vuelve a calcular al enviar.")
        XCTAssertEqual(try arguments(in: sendMax), try arguments(in: sendMaxKey))
    }

    func testFrenchAndGermanCriticalCopyIsClear() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."
        let sendMaxKey = "Send maximum spendable after fee to %@.\nPreview amount: %@\nEstimated fee: %@\nFinal amount is recalculated at send time."

        XCTAssertEqual(try translatedValue(in: strings, key: "Total (amount + fee)", locale: "fr"), "Total (montant + frais)")
        XCTAssertEqual(try translatedValue(in: strings, key: "Total (amount + fee)", locale: "de"), "Gesamt (Betrag + Gebühr)")
        XCTAssertEqual(try translatedValue(in: strings, key: "Generate new seed", locale: "de"), "Neue Wiederherstellungsphrase erstellen")
        XCTAssertEqual(try translatedValue(in: strings, key: "I wrote down my recovery seed", locale: "de"), "Ich habe meine Wiederherstellungsphrase notiert")
        XCTAssertEqual(try translatedValue(in: strings, key: "Seed word", locale: "fr"), "Mot de la phrase de récupération")
        XCTAssertEqual(try translatedValue(in: strings, key: "Seed word", locale: "de"), "Wort der Wiederherstellungsphrase")

        let frenchPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "fr")
        XCTAssertTrue(frenchPrivacy.contains("adresse IP et les requêtes de synchronisation de votre portefeuille"))
        XCTAssertTrue(frenchPrivacy.contains("rates.nexawal.com"))
        XCTAssertFalse(frenchPrivacy.contains("synchronisation IP"))

        let germanPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "de")
        XCTAssertTrue(germanPrivacy.contains("IP-Adresse und die Synchronisierungsanfragen Ihrer Wallet"))
        XCTAssertTrue(germanPrivacy.contains("rates.nexawal.com"))
        XCTAssertFalse(germanPrivacy.contains("IP-Synchronisierungsanfragen"))

        for (locale, phrase) in [
            ("fr", "montant maximal disponible après déduction des frais"),
            ("de", "maximal verfügbaren Betrag nach Abzug der Gebühr"),
        ] {
            let sendMax = try translatedValue(in: strings, key: sendMaxKey, locale: locale)
            XCTAssertTrue(sendMax.contains(phrase), "unclear max-send fee wording in \(locale)")
            XCTAssertEqual(try arguments(in: sendMax), try arguments(in: sendMaxKey))
        }
    }

    func testAdditionalLocaleDisclosuresAvoidKnownMeaningErrors() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."
        let expectedPhrases = [
            "ar": "عنوان IP الخاص بك وطلبات مزامنة المحفظة",
            "pl": "Twój adres IP i zapytania synchronizacji portfela",
            "pt-BR": "seu endereço IP e as solicitações de sincronização da carteira",
            "ru": "ваш IP-адрес и запросы синхронизации кошелька",
            "vi": "địa chỉ IP và các yêu cầu đồng bộ hóa ví của bạn",
            "zh-Hans": "您的 IP 地址和钱包同步请求",
            "zh-Hant": "您的 IP 位址與錢包同步請求",
        ]

        for (locale, phrase) in expectedPhrases {
            let value = try translatedValue(in: strings, key: privacyKey, locale: locale)
            XCTAssertTrue(value.contains(phrase), "privacy disclosure is unclear in \(locale)")
            XCTAssertTrue(value.contains("rates.nexawal.com"), "rates source missing in \(locale)")
        }

        let forbiddenPhrases = [
            "ar": ["معهد ماساتشوستس"],
            "pl": ["zwrot środków"],
            "pt-BR": ["período de recuperação"],
            "ru": ["позвоните по номеру"],
            "vi": ["thời hạn khôi phục"],
            "zh-Hans": ["麻省理工学院"],
            "zh-Hant": ["麻省理工學院"],
        ]
        for (locale, phrases) in forbiddenPhrases {
            let value = try translatedValue(in: strings, key: privacyKey, locale: locale)
            for phrase in phrases {
                XCTAssertFalse(value.contains(phrase), "known mistranslation remains in \(locale): \(phrase)")
            }
        }
    }

    func testArabicAndPolishWalletCriticalCopyIsClear() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let custodyKey = "nexawal by Nexatrode LLC is a self-custodial interface for managing digital assets. You hold exclusive responsibility for your private keys and 25-word seed phrase."
        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."
        let sendMaxKey = "Send maximum spendable after fee to %@.\nPreview amount: %@\nEstimated fee: %@\nFinal amount is recalculated at send time."
        let recoveryKeys = [
            "Generate new seed",
            "I wrote down my recovery seed",
            "Mnemonic (paste):",
            "Mnemonic cannot be empty.",
            "Rescan failed: mnemonic is unavailable.",
            "Stored mnemonic could not be found.",
            "This will replace the existing wallet on this device.\n\nIf you continue, the currently stored mnemonic and scan state will be removed. Make sure you have your mnemonic backed up before proceeding.",
        ]
        let locales: [(String, String, String, String, String, [String])] = [
            ("ar", "عبارة الاسترداد", "رسوم الشبكة", "رسوم الشبكة", "المخصوم", ["بذرة", "العبارة التذكيرية"]),
            ("pl", "frazę odzyskiwania", "opłaty sieciowej", "opłatą sieciową", "obciążenie", ["seed", "mnemonic", "ziarno", "plik początkowy", "self-custodial"]),
        ]

        for (locale, recoveryTerm, feeTerm, feeHelpTerm, debitTerm, forbidden) in locales {
            let custody = try translatedValue(in: strings, key: custodyKey, locale: locale)
            XCTAssertTrue(custody.localizedCaseInsensitiveContains(recoveryTerm), "recovery wording missing in \(locale)")
            for term in forbidden {
                XCTAssertFalse(custody.localizedCaseInsensitiveContains(term), "technical or misleading term in \(locale): \(term)")
            }

            for key in recoveryKeys {
                let value = try translatedValue(in: strings, key: key, locale: locale).lowercased()
                for term in forbidden {
                    XCTAssertFalse(value.contains(term.lowercased()), "technical or misleading term in \(locale): \(key)")
                }
            }

            let sendMax = try translatedValue(in: strings, key: sendMaxKey, locale: locale)
            XCTAssertTrue(sendMax.localizedCaseInsensitiveContains(feeTerm), "Send Max must disclose fee deduction in \(locale)")
            XCTAssertEqual(try arguments(in: sendMax), try arguments(in: sendMaxKey))
            XCTAssertEqual(sendMax.components(separatedBy: "%@").count - 1, 3)
            for key in [
                "Send Max mode: Confirm will sweep all unlocked after fee.",
                "Max preview ready. Confirm Send Max will sweep all unlocked after fee.",
            ] {
                XCTAssertTrue(try translatedValue(in: strings, key: key, locale: locale).localizedCaseInsensitiveContains(feeTerm), "\(key) must disclose fee deduction in \(locale)")
            }

            XCTAssertTrue(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: locale).localizedCaseInsensitiveContains(debitTerm))
            XCTAssertTrue(try translatedValue(in: strings, key: "Amount is the total wallet debit, including the network fee.", locale: locale).localizedCaseInsensitiveContains(feeHelpTerm))
            XCTAssertEqual(
                try arguments(in: translatedValue(in: strings, key: "%llu confirmations", locale: locale)),
                try arguments(in: "%llu confirmations")
            )
            if locale == "ar" {
                let confirmations = try translatedValue(in: strings, key: "%llu confirmations", locale: locale)
                XCTAssertTrue(confirmations.contains("عدد التأكيدات"))
                XCTAssertTrue(confirmations.contains("%llu"))
            }

            let privacy = try translatedValue(in: strings, key: privacyKey, locale: locale)
            XCTAssertTrue(privacy.contains("rates.nexawal.com"))
            XCTAssertTrue(privacy.localizedCaseInsensitiveContains("IP"))
            XCTAssertFalse(privacy.localizedCaseInsensitiveContains("contact"))

            for key in ["Date range", "Filter", "Loading transactions…", "Mainnet", "Sync failed", "Unlocking…"] {
                XCTAssertNotEqual(try translatedValue(in: strings, key: key, locale: locale), key, "\(key) is untranslated in \(locale)")
            }
        }
    }

    func testBrazilianPortugueseAndRussianWalletCriticalCopyIsClear() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let custodyKey = "nexawal by Nexatrode LLC is a self-custodial interface for managing digital assets. You hold exclusive responsibility for your private keys and 25-word seed phrase."
        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."
        let ratePrivacyKey = "Optional. When enabled, NexaWal requests an XMR rate for your selected currency from rates.nexawal.com over HTTPS. This request uses clearnet even when the wallet node uses I2P. Nexatrode can see your IP address and selected currency; wallet amounts, addresses, seeds, and transaction history are not sent. Estimates only — XMR is what you send and hold."
        let sendMaxKey = "Send maximum spendable after fee to %@.\nPreview amount: %@\nEstimated fee: %@\nFinal amount is recalculated at send time."
        let recoveryKeys = [
            "Generate new seed", "I wrote down my recovery seed", "Mnemonic (paste):", "Mnemonic cannot be empty.",
            "Rescan failed: mnemonic is unavailable.", "Stored mnemonic could not be found.",
            "This will replace the existing wallet on this device.\n\nIf you continue, the currently stored mnemonic and scan state will be removed. Make sure you have your mnemonic backed up before proceeding.",
        ]
        let locales: [(String, String, String, String, String, [String])] = [
            ("pt-BR", "frase de recuperação", "taxa de rede", "taxa de rede", "Débito total", ["seed", "mnemônico", "mnemônica", "semente"]),
            ("ru", "фраз", "сетевой комиссии", "сетевую комиссию", "Полное списание", ["seed", "сид-фраз", "мнемонич"]),
        ]

        for (locale, recoveryTerm, feeTerm, feeHelpTerm, debitTerm, forbidden) in locales {
            let custody = try translatedValue(in: strings, key: custodyKey, locale: locale)
            XCTAssertTrue(custody.localizedCaseInsensitiveContains(recoveryTerm), "recovery wording missing in \(locale)")
            for term in forbidden {
                XCTAssertFalse(custody.localizedCaseInsensitiveContains(term), "technical or misleading custody wording in \(locale): \(term)")
            }
            for key in recoveryKeys {
                let value = try translatedValue(in: strings, key: key, locale: locale)
                XCTAssertTrue(value.localizedCaseInsensitiveContains(recoveryTerm), "recovery term missing in \(locale): \(key)")
                for term in forbidden {
                    XCTAssertFalse(value.localizedCaseInsensitiveContains(term), "technical or misleading term in \(locale): \(key)")
                }
            }

            let sendMax = try translatedValue(in: strings, key: sendMaxKey, locale: locale)
            XCTAssertTrue(sendMax.localizedCaseInsensitiveContains(feeTerm), "Send Max must state that the network fee is deducted in \(locale)")
            XCTAssertEqual(try arguments(in: sendMax), try arguments(in: sendMaxKey))
            for key in ["Send Max mode: Confirm will sweep all unlocked after fee.", "Max preview ready. Confirm Send Max will sweep all unlocked after fee."] {
                XCTAssertTrue(try translatedValue(in: strings, key: key, locale: locale).localizedCaseInsensitiveContains(feeTerm), "fee deduction missing in \(locale): \(key)")
            }
            XCTAssertTrue(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: locale).localizedCaseInsensitiveContains(debitTerm))
            XCTAssertTrue(try translatedValue(in: strings, key: "Amount is the total wallet debit, including the network fee.", locale: locale).localizedCaseInsensitiveContains(feeHelpTerm))

            let confirmations = try translatedValue(in: strings, key: "%llu confirmations", locale: locale)
            XCTAssertEqual(try arguments(in: confirmations), try arguments(in: "%llu confirmations"))
            XCTAssertTrue(confirmations.contains("%llu"))
            XCTAssertTrue(confirmations.localizedCaseInsensitiveContains(locale == "pt-BR" ? "Número de confirmações" : "Число подтверждений"))

            let hybridPolicy = try translatedValue(in: strings, key: "Both (scan clearnet, broadcast I2P)", locale: locale)
            if locale == "pt-BR" {
                XCTAssertTrue(hybridPolicy.localizedCaseInsensitiveContains("sincronizar"))
                XCTAssertTrue(hybridPolicy.localizedCaseInsensitiveContains("transmitir"))
                XCTAssertFalse(hybridPolicy.localizedCaseInsensitiveContains("varrer"))
                XCTAssertTrue(try translatedValue(in: strings, key: "Scan additional accounts or subaddresses", locale: locale).localizedCaseInsensitiveContains("escanear"))
            } else {
                XCTAssertTrue(hybridPolicy.localizedCaseInsensitiveContains("синхронизация"))
                XCTAssertTrue(hybridPolicy.localizedCaseInsensitiveContains("транзакций"))
                XCTAssertTrue(try translatedValue(in: strings, key: "Rescan from Height", locale: locale).localizedCaseInsensitiveContains("синхронизировать"))
            }
            let selectedSubaddressSend = try translatedValue(in: strings, key: "Swept max spendable from selected subaddress via %@.", locale: locale)
            XCTAssertTrue(selectedSubaddressSend.localizedCaseInsensitiveContains(locale == "pt-BR" ? "foi enviado" : "отправлен"))
            XCTAssertTrue(selectedSubaddressSend.contains("%@"))

            let privacy = try translatedValue(in: strings, key: privacyKey, locale: locale)
            XCTAssertTrue(privacy.contains("rates.nexawal.com"))
            XCTAssertTrue(privacy.localizedCaseInsensitiveContains("IP"))
            XCTAssertFalse(privacy.localizedCaseInsensitiveContains("contact"))
            let ratePrivacy = try translatedValue(in: strings, key: ratePrivacyKey, locale: locale)
            XCTAssertTrue(ratePrivacy.contains("I2P"))
            XCTAssertTrue(ratePrivacy.contains("rates.nexawal.com"))
            for key in ["Date range", "Filter", "Loading transactions…", "Mainnet", "Sync failed", "Unlocking…"] {
                XCTAssertNotEqual(try translatedValue(in: strings, key: key, locale: locale), key, "\(key) is untranslated in \(locale)")
            }
        }
    }

    func testItalianAndJapaneseWalletCriticalCopyIsConsistent() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."

        XCTAssertEqual(try translatedValue(in: strings, key: "Generate new seed", locale: "it"), "Genera una nuova frase di recupero")
        XCTAssertEqual(try translatedValue(in: strings, key: "Generate new seed", locale: "ja"), "新しい復元フレーズを生成")
        XCTAssertEqual(try translatedValue(in: strings, key: "Seed word", locale: "ja"), "復元フレーズの単語")

        let italianTerms = try translatedValue(
            in: strings,
            key: "nexawal by Nexatrode LLC is a self-custodial interface for managing digital assets. You hold exclusive responsibility for your private keys and 25-word seed phrase.",
            locale: "it"
        )
        XCTAssertTrue(italianTerms.contains("frase di recupero di 25 parole"))
        XCTAssertFalse(italianTerms.contains("frase seed"))

        let japaneseTerms = try translatedValue(
            in: strings,
            key: "nexawal by Nexatrode LLC is a self-custodial interface for managing digital assets. You hold exclusive responsibility for your private keys and 25-word seed phrase.",
            locale: "ja"
        )
        XCTAssertTrue(japaneseTerms.contains("25 語の復元フレーズ"))
        XCTAssertFalse(japaneseTerms.contains("シードフレーズ"))

        let italianPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "it")
        XCTAssertTrue(italianPrivacy.contains("indirizzo IP e le richieste di sincronizzazione"))
        XCTAssertTrue(italianPrivacy.contains("l'app recupera i tassi da rates.nexawal.com"))
        XCTAssertFalse(italianPrivacy.contains("non certificato"))

        let japanesePrivacy = try translatedValue(in: strings, key: privacyKey, locale: "ja")
        XCTAssertTrue(japanesePrivacy.contains("IPアドレスとウォレット同期のリクエスト"))
        XCTAssertTrue(japanesePrivacy.contains("rates.nexawal.com からレートを取得します"))
        XCTAssertFalse(japanesePrivacy.contains("お問い合わせください"))
    }

    func testDutchAndTurkishWalletCriticalCopyIsClear() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let recoveryKey = "nexawal by Nexatrode LLC is a self-custodial interface for managing digital assets. You hold exclusive responsibility for your private keys and 25-word seed phrase."
        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."
        let sendMaxKey = "Send maximum spendable after fee to %@.\nPreview amount: %@\nEstimated fee: %@\nFinal amount is recalculated at send time."

        let dutchRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "nl")
        XCTAssertTrue(dutchRecovery.contains("herstelzin van 25 woorden"))
        XCTAssertFalse(dutchRecovery.contains("seedzin"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "nl"), "Afschrijving uit wallet (bedrag + netwerkkosten)")
        XCTAssertEqual(try translatedValue(in: strings, key: "Total (amount + fee)", locale: "nl"), "Totaal (bedrag + netwerkkosten)")
        let dutchPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "nl")
        XCTAssertTrue(dutchPrivacy.contains("niet onafhankelijk op veiligheid gecontroleerd"))
        XCTAssertTrue(dutchPrivacy.contains("haalt de app koersen op bij rates.nexawal.com"))
        XCTAssertFalse(dutchPrivacy.contains("neem contact op met rates.nexawal.com"))
        let dutchSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "nl")
        XCTAssertTrue(dutchSendMax.contains("na aftrek van de netwerkkosten"))
        XCTAssertEqual(try arguments(in: dutchSendMax), try arguments(in: sendMaxKey))

        let turkishRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "tr")
        XCTAssertTrue(turkishRecovery.contains("25 kelimelik kurtarma ifadenizden"))
        XCTAssertFalse(turkishRecovery.contains("tohum ifadesi"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "tr"), "Cüzdandan düşülen tutar (tutar + ağ ücreti)")
        XCTAssertEqual(try translatedValue(in: strings, key: "Total (amount + fee)", locale: "tr"), "Toplam (tutar + ağ ücreti)")
        let turkishPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "tr")
        XCTAssertTrue(turkishPrivacy.contains("bağımsız bir güvenlik denetiminden geçmemiştir"))
        XCTAssertTrue(turkishPrivacy.contains("kurları rates.nexawal.com adresinden alır"))
        XCTAssertFalse(turkishPrivacy.contains("ile iletişime geçin"))
        let turkishSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "tr")
        XCTAssertTrue(turkishSendMax.localizedCaseInsensitiveContains("ağ ücreti düşüldükten sonra"))
        XCTAssertEqual(try arguments(in: turkishSendMax), try arguments(in: sendMaxKey))
    }

    func testAzerbaijaniAndBulgarianWalletCriticalCopyIsClear() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let recoveryKey = "nexawal by Nexatrode LLC is a self-custodial interface for managing digital assets. You hold exclusive responsibility for your private keys and 25-word seed phrase."
        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."
        let sendMaxKey = "Send maximum spendable after fee to %@.\nPreview amount: %@\nEstimated fee: %@\nFinal amount is recalculated at send time."

        let azeriRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "az")
        XCTAssertTrue(azeriRecovery.contains("25 sözdən ibarət bərpa ifadəniz"))
        XCTAssertFalse(azeriRecovery.contains("seed ifadəsi"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "az"), "Pul kisəsindən çıxılan məbləğ (məbləğ + komissiya)")
        let azeriPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "az")
        XCTAssertTrue(azeriPrivacy.contains("müstəqil təhlükəsizlik auditindən keçməmiş"))
        XCTAssertTrue(azeriPrivacy.contains("tətbiq məzənnələri rates.nexawal.com saytından alır"))
        XCTAssertFalse(azeriPrivacy.contains("əlaqə saxlayın"))
        let azeriSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "az")
        XCTAssertTrue(azeriSendMax.localizedCaseInsensitiveContains("komissiya çıxıldıqdan sonra"))
        XCTAssertEqual(try arguments(in: azeriSendMax), try arguments(in: sendMaxKey))

        let bulgarianRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "bg")
        XCTAssertTrue(bulgarianRecovery.contains("фразата си за възстановяване от 25 думи"))
        XCTAssertFalse(bulgarianRecovery.contains("seed фразата"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "bg"), "Общо дебитирано от портфейла (сума + такса)")
        let bulgarianPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "bg")
        XCTAssertTrue(bulgarianPrivacy.contains("не е преминал независим одит по сигурността"))
        XCTAssertTrue(bulgarianPrivacy.contains("приложението получава курсовете от rates.nexawal.com"))
        XCTAssertFalse(bulgarianPrivacy.contains("свържете се с rates.nexawal.com"))
        let bulgarianSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "bg")
        XCTAssertTrue(bulgarianSendMax.contains("след приспадане на мрежовата такса"))
        XCTAssertEqual(try arguments(in: bulgarianSendMax), try arguments(in: sendMaxKey))
    }

    func testBengaliAndCatalanWalletCriticalCopyIsClear() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let recoveryKey = "nexawal by Nexatrode LLC is a self-custodial interface for managing digital assets. You hold exclusive responsibility for your private keys and 25-word seed phrase."
        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."
        let ratesKey = "Optional. When enabled, NexaWal requests an XMR rate for your selected currency from rates.nexawal.com over HTTPS. This request uses clearnet even when the wallet node uses I2P. Nexatrode can see your IP address and selected currency; wallet amounts, addresses, seeds, and transaction history are not sent. Estimates only — XMR is what you send and hold."
        let sendMaxKey = "Send maximum spendable after fee to %@.\nPreview amount: %@\nEstimated fee: %@\nFinal amount is recalculated at send time."

        let bengaliRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "bn")
        XCTAssertTrue(bengaliRecovery.contains("২৫ শব্দের পুনরুদ্ধার বাক্যাংশ"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "bn"), "ওয়ালেট থেকে মোট কর্তন (পরিমাণ + ফি)")
        let bengaliPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "bn")
        XCTAssertTrue(bengaliPrivacy.contains("স্বাধীন নিরাপত্তা নিরীক্ষা হয়নি"))
        XCTAssertTrue(bengaliPrivacy.contains("অ্যাপ rates.nexawal.com থেকে বিনিময় হার সংগ্রহ করে"))
        XCTAssertFalse(bengaliPrivacy.contains("যোগাযোগ করুন"))
        let bengaliRates = try translatedValue(in: strings, key: ratesKey, locale: "bn")
        XCTAssertTrue(bengaliRates.contains("পুনরুদ্ধার বাক্যাংশ"))
        let bengaliSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "bn")
        XCTAssertTrue(bengaliSendMax.contains("ফি-র পরে"))
        XCTAssertEqual(try arguments(in: bengaliSendMax), try arguments(in: sendMaxKey))

        let catalanRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "ca")
        XCTAssertTrue(catalanRecovery.contains("frase de recuperació de 25 paraules"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "ca"), "Total descomptat de la cartera (import + comissió)")
        let catalanPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "ca")
        XCTAssertTrue(catalanPrivacy.contains("sense una auditoria de seguretat independent"))
        XCTAssertTrue(catalanPrivacy.contains("l’aplicació obté els tipus de canvi de rates.nexawal.com"))
        XCTAssertFalse(catalanPrivacy.contains("poseu-vos en contacte"))
        let catalanRates = try translatedValue(in: strings, key: ratesKey, locale: "ca")
        XCTAssertTrue(catalanRates.contains("Internet pública (Clearnet)"))
        let catalanSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "ca")
        XCTAssertTrue(catalanSendMax.contains("després de la tarifa"))
        XCTAssertEqual(try arguments(in: catalanSendMax), try arguments(in: sendMaxKey))
    }

    func testCzechAndDanishWalletCriticalCopyIsClear() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let recoveryKey = "nexawal by Nexatrode LLC is a self-custodial interface for managing digital assets. You hold exclusive responsibility for your private keys and 25-word seed phrase."
        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."
        let sendMaxKey = "Send maximum spendable after fee to %@.\nPreview amount: %@\nEstimated fee: %@\nFinal amount is recalculated at send time."

        let czechRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "cs")
        XCTAssertTrue(czechRecovery.contains("25slovnou frázi pro obnovení"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "cs"), "Celkem odečteno z peněženky (částka + poplatek)")
        let czechPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "cs")
        XCTAssertTrue(czechPrivacy.contains("nezávislým bezpečnostním auditem"))
        XCTAssertTrue(czechPrivacy.contains("aplikace načítá kurzy z rates.nexawal.com"))
        XCTAssertFalse(czechPrivacy.contains("kontaktujte rates.nexawal.com"))
        let czechSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "cs")
        XCTAssertTrue(czechSendMax.contains("po odečtení poplatku"))
        XCTAssertEqual(try arguments(in: czechSendMax), try arguments(in: sendMaxKey))

        let danishRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "da")
        XCTAssertTrue(danishRecovery.contains("gendannelsesfrase på 25 ord"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "da"), "Samlet trukket fra tegnebogen (beløb + gebyr)")
        let danishPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "da")
        XCTAssertTrue(danishPrivacy.contains("uafhængigt sikkerhedsrevideret"))
        XCTAssertTrue(danishPrivacy.contains("henter appen kurser fra rates.nexawal.com"))
        XCTAssertFalse(danishPrivacy.contains("kontakt rates.nexawal.com"))
        let danishSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "da")
        XCTAssertTrue(danishSendMax.contains("efter fradrag af gebyret"))
        XCTAssertEqual(try arguments(in: danishSendMax), try arguments(in: sendMaxKey))
    }

    func testGreekAndEsperantoWalletCriticalCopyIsClear() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let recoveryKey = "nexawal by Nexatrode LLC is a self-custodial interface for managing digital assets. You hold exclusive responsibility for your private keys and 25-word seed phrase."
        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."
        let sendMaxKey = "Send maximum spendable after fee to %@.\nPreview amount: %@\nEstimated fee: %@\nFinal amount is recalculated at send time."

        let greekRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "el")
        XCTAssertTrue(greekRecovery.contains("φράση ανάκτησης 25 λέξεων"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "el"), "Συνολικό ποσό που αφαιρείται από το πορτοφόλι (ποσό + χρέωση)")
        let greekPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "el")
        XCTAssertTrue(greekPrivacy.contains("ανεξάρτητο έλεγχο ασφαλείας"))
        XCTAssertTrue(greekPrivacy.contains("η εφαρμογή λαμβάνει ισοτιμίες από rates.nexawal.com"))
        XCTAssertFalse(greekPrivacy.contains("επικοινωνήστε με το rates.nexawal.com"))
        let greekSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "el")
        XCTAssertTrue(greekSendMax.contains("μετά την αφαίρεση της χρέωσης"))
        XCTAssertEqual(try arguments(in: greekSendMax), try arguments(in: sendMaxKey))

        let esperantoRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "eo")
        XCTAssertTrue(esperantoRecovery.contains("25-vorta reakira frazo"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "eo"), "Sumo entute deprenita de la monujo (sumo + kotizo)")
        let esperantoPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "eo")
        XCTAssertTrue(esperantoPrivacy.contains("ne estis sendepende kontrolita pri sekureco"))
        XCTAssertTrue(esperantoPrivacy.contains("la aplikaĵo ricevas kurzojn de rates.nexawal.com"))
        XCTAssertFalse(esperantoPrivacy.contains("kontaktu rates.nexawal.com"))
        let esperantoSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "eo")
        XCTAssertTrue(esperantoSendMax.contains("post depreno de la kotizo"))
        XCTAssertEqual(try arguments(in: esperantoSendMax), try arguments(in: sendMaxKey))
    }

    func testEstonianAndBasqueWalletCriticalCopyIsClear() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let recoveryKey = "nexawal by Nexatrode LLC is a self-custodial interface for managing digital assets. You hold exclusive responsibility for your private keys and 25-word seed phrase."
        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."
        let sendMaxKey = "Send maximum spendable after fee to %@.\nPreview amount: %@\nEstimated fee: %@\nFinal amount is recalculated at send time."

        let estonianRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "et")
        XCTAssertTrue(estonianRecovery.contains("25-sõnalise taastefraasi"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "et"), "Rahakotist maha arvestatud kogusumma (summa + tasu)")
        let estonianPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "et")
        XCTAssertTrue(estonianPrivacy.contains("pole sõltumatult turvalisuse suhtes auditeeritud"))
        XCTAssertTrue(estonianPrivacy.contains("hangib rakendus kursid aadressilt rates.nexawal.com"))
        XCTAssertFalse(estonianPrivacy.contains("võtke hindade saamiseks ühendust"))
        let estonianSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "et")
        XCTAssertTrue(estonianSendMax.contains("pärast tasu mahaarvamist"))
        XCTAssertEqual(try arguments(in: estonianSendMax), try arguments(in: sendMaxKey))

        let basqueRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "eu")
        XCTAssertTrue(basqueRecovery.contains("25 hitzeko berreskuratze-esaldi"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "eu"), "Zorroari guztira kendutako zenbatekoa (zenbatekoa + komisioa)")
        let basquePrivacy = try translatedValue(in: strings, key: privacyKey, locale: "eu")
        XCTAssertTrue(basquePrivacy.contains("ez du segurtasun-auditoria independentea gainditu"))
        XCTAssertTrue(basquePrivacy.contains("aplikazioak rates.nexawal.com-etik eskuratzen ditu truke-tasak"))
        XCTAssertFalse(basquePrivacy.contains("jarri harremanetan rates.nexawal.com"))
        let basqueSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "eu")
        XCTAssertTrue(basqueSendMax.contains("komisioa kendu ondoren"))
        XCTAssertEqual(try arguments(in: basqueSendMax), try arguments(in: sendMaxKey))
    }

    func testPersianAndFinnishWalletCriticalCopyIsClear() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let recoveryKey = "nexawal by Nexatrode LLC is a self-custodial interface for managing digital assets. You hold exclusive responsibility for your private keys and 25-word seed phrase."
        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."
        let sendMaxKey = "Send maximum spendable after fee to %@.\nPreview amount: %@\nEstimated fee: %@\nFinal amount is recalculated at send time."

        let finnishRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "fi")
        XCTAssertTrue(finnishRecovery.contains("25 sanan palautuslausekkeestasi"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "fi"), "Lompakosta veloitettava määrä (määrä + verkkomaksu)")
        XCTAssertEqual(try translatedValue(in: strings, key: "Fee", locale: "fi"), "Verkkomaksu")
        let finnishPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "fi")
        XCTAssertTrue(finnishPrivacy.contains("ei ole auditoitu riippumattomasti tietoturvan osalta"))
        XCTAssertTrue(finnishPrivacy.contains("sovellus noutaa valuuttakurssit palvelusta rates.nexawal.com"))
        XCTAssertFalse(finnishPrivacy.contains("ota yhteyttä rates.nexawal.com"))
        let finnishSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "fi")
        XCTAssertTrue(finnishSendMax.contains("verkkomaksun jälkeen käytettävissä oleva enimmäismäärä"))
        XCTAssertEqual(try arguments(in: finnishSendMax), try arguments(in: sendMaxKey))

        let persianRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "fa")
        XCTAssertTrue(persianRecovery.contains("عبارت بازیابی ۲۵ کلمه‌ای"))
        XCTAssertTrue(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "fa").contains("کارمزد"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Fee", locale: "fa"), "کارمزد شبکه")
        let persianPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "fa")
        XCTAssertTrue(persianPrivacy.contains("ممیزی امنیتی مستقل نشده است"))
        XCTAssertTrue(persianPrivacy.contains("برنامه نرخ‌ها را از rates.nexawal.com دریافت می‌کند"))
        XCTAssertFalse(persianPrivacy.contains("تماس بگیرید"))
        let persianSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "fa")
        XCTAssertTrue(persianSendMax.contains("پس از کسر کارمزد شبکه"))
        XCTAssertEqual(try arguments(in: persianSendMax), try arguments(in: sendMaxKey))
    }

    func testFilipinoAndIrishWalletCriticalCopyIsClear() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let recoveryKey = "nexawal by Nexatrode LLC is a self-custodial interface for managing digital assets. You hold exclusive responsibility for your private keys and 25-word seed phrase."
        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."
        let ratesKey = "Optional. When enabled, NexaWal requests an XMR rate for your selected currency from rates.nexawal.com over HTTPS. This request uses clearnet even when the wallet node uses I2P. Nexatrode can see your IP address and selected currency; wallet amounts, addresses, seeds, and transaction history are not sent. Estimates only — XMR is what you send and hold."
        let sendMaxKey = "Send maximum spendable after fee to %@.\nPreview amount: %@\nEstimated fee: %@\nFinal amount is recalculated at send time."

        let filipinoRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "fil")
        XCTAssertTrue(filipinoRecovery.contains("25-salitang parirala sa pagbawi"))
        XCTAssertFalse(filipinoRecovery.contains("seed phrase"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Fee", locale: "fil"), "Bayad sa network")
        XCTAssertEqual(try translatedValue(in: strings, key: "Send Max", locale: "fil"), "Ipadala ang pinakamalaking halaga")
        let filipinoPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "fil")
        XCTAssertTrue(filipinoPrivacy.contains("hindi pa dumaan sa independiyenteng audit sa seguridad"))
        XCTAssertTrue(filipinoPrivacy.contains("kinukuha ng app ang mga exchange rate mula sa rates.nexawal.com"))
        XCTAssertFalse(filipinoPrivacy.contains("makipag-ugnayan sa rates.nexawal.com"))
        let filipinoRates = try translatedValue(in: strings, key: ratesKey, locale: "fil")
        XCTAssertTrue(filipinoRates.contains("parirala sa pagbawi"))
        XCTAssertTrue(filipinoRates.contains("kasaysayan ng mga transaksyon"))
        let filipinoSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "fil")
        XCTAssertTrue(filipinoSendMax.contains("matapos ibawas ang bayad sa network"))
        XCTAssertEqual(try arguments(in: filipinoSendMax), try arguments(in: sendMaxKey))

        let irishRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "ga")
        XCTAssertTrue(irishRecovery.contains("athshlánaithe 25 focal"))
        XCTAssertFalse(irishRecovery.contains("frása síl"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Fee", locale: "ga"), "Táille líonra")
        XCTAssertEqual(try translatedValue(in: strings, key: "Send Max", locale: "ga"), "Seol an t-uasmhéid")
        let irishPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "ga")
        XCTAssertTrue(irishPrivacy.contains("nár ndearnadh iniúchadh slándála neamhspleách orthu"))
        XCTAssertTrue(irishPrivacy.contains("faigheann an aip rátaí malairte ó rates.nexawal.com"))
        XCTAssertFalse(irishPrivacy.contains("déan teagmháil le rates.nexawal.com"))
        let irishRates = try translatedValue(in: strings, key: ratesKey, locale: "ga")
        XCTAssertTrue(irishRates.contains("frása athshlánaithe"))
        let irishSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "ga")
        XCTAssertTrue(irishSendMax.contains("tar éis an táille líonra a asbhaint"))
        XCTAssertEqual(try arguments(in: irishSendMax), try arguments(in: sendMaxKey))
    }

    func testGalicianAndGuaraniWalletCriticalCopyIsClear() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let recoveryKey = "nexawal by Nexatrode LLC is a self-custodial interface for managing digital assets. You hold exclusive responsibility for your private keys and 25-word seed phrase."
        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."
        let ratesKey = "Optional. When enabled, NexaWal requests an XMR rate for your selected currency from rates.nexawal.com over HTTPS. This request uses clearnet even when the wallet node uses I2P. Nexatrode can see your IP address and selected currency; wallet amounts, addresses, seeds, and transaction history are not sent. Estimates only — XMR is what you send and hold."
        let sendMaxKey = "Send maximum spendable after fee to %@.\nPreview amount: %@\nEstimated fee: %@\nFinal amount is recalculated at send time."

        let galicianRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "gl")
        XCTAssertTrue(galicianRecovery.contains("frase de recuperación de 25 palabras"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "gl"), "Total debitado da carteira (cantidade + comisión)")
        XCTAssertEqual(try translatedValue(in: strings, key: "Fee", locale: "gl"), "Comisión")
        let galicianPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "gl")
        XCTAssertTrue(galicianPrivacy.contains("enderezo IP e as consultas de sincronización da carteira"))
        XCTAssertTrue(galicianPrivacy.contains("a aplicación obtén as taxas de rates.nexawal.com"))
        XCTAssertFalse(galicianPrivacy.contains("póñase en contacto con rates.nexawal.com"))
        let galicianRates = try translatedValue(in: strings, key: ratesKey, locale: "gl")
        XCTAssertTrue(galicianRates.contains("frases de recuperación"))
        let galicianSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "gl")
        XCTAssertTrue(galicianSendMax.contains("despois de descontar a comisión da rede"))
        XCTAssertEqual(try arguments(in: galicianSendMax), try arguments(in: sendMaxKey))

        let guaraniRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "gn")
        XCTAssertTrue(guaraniRecovery.contains("frase de recuperación 25 ñe'ẽ"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "gn"), "Viru oñeguenohẽva ñongatuha-gui (cantidad + comisión)")
        let guaraniPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "gn")
        XCTAssertTrue(guaraniPrivacy.contains("ne ñongatuha sincronización rehegua jerure"))
        XCTAssertTrue(guaraniPrivacy.contains("aplicación ogueru tasa de cambio rates.nexawal.com-gui"))
        XCTAssertFalse(guaraniPrivacy.contains("eñe’ẽ rates.nexawal.com ndive"))
        let guaraniRates = try translatedValue(in: strings, key: ratesKey, locale: "gn")
        XCTAssertTrue(guaraniRates.contains("frase de recuperación"))
        let guaraniSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "gn")
        XCTAssertTrue(guaraniSendMax.contains("ojeipe'a rire comisión de red"))
        XCTAssertEqual(try arguments(in: guaraniSendMax), try arguments(in: sendMaxKey))
    }

    func testHausaAndHebrewWalletCriticalCopyIsClear() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let recoveryKey = "nexawal by Nexatrode LLC is a self-custodial interface for managing digital assets. You hold exclusive responsibility for your private keys and 25-word seed phrase."
        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."
        let sendMaxKey = "Send maximum spendable after fee to %@.\nPreview amount: %@\nEstimated fee: %@\nFinal amount is recalculated at send time."

        let hausaRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "ha")
        XCTAssertTrue(hausaRecovery.contains("jumlar dawowa mai kalmomi 25"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "ha"), "Jimillar kuɗin da aka cire daga walat (adadi + kuɗin hanyar sadarwa)")
        let hausaPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "ha")
        XCTAssertTrue(hausaPrivacy.contains("adireshin IP ɗinka da buƙatun wallet ɗinka na daidaitawa"))
        XCTAssertTrue(hausaPrivacy.contains("manhajar tana neman ƙimar kuɗi daga rates.nexawal.com"))
        XCTAssertFalse(hausaPrivacy.contains("tuntuɓi rates.nexawal.com"))
        let hausaSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "ha")
        XCTAssertTrue(hausaSendMax.contains("bayan cire kuɗin hanyar sadarwa"))
        XCTAssertEqual(try arguments(in: hausaSendMax), try arguments(in: sendMaxKey))

        let hebrewRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "he")
        XCTAssertTrue(hebrewRecovery.contains("ביטוי השחזור בן 25 המילים"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "he"), "חיוב כולל בארנק (סכום + עמלת רשת)")
        let hebrewPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "he")
        XCTAssertTrue(hebrewPrivacy.contains("כתובת ה-IP שלך ואת שאילתות הארנק לצורך סנכרון"))
        XCTAssertTrue(hebrewPrivacy.contains("האפליקציה תבקש שערי חליפין מ-rates.nexawal.com"))
        XCTAssertFalse(hebrewPrivacy.contains("צור קשר עם rates.nexawal.com"))
        let hebrewSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "he")
        XCTAssertTrue(hebrewSendMax.contains("הסכום המרבי שניתן להוציא לאחר עמלת הרשת"))
        XCTAssertEqual(try arguments(in: hebrewSendMax), try arguments(in: sendMaxKey))
    }

    func testHindiAndCroatianWalletCriticalCopyIsClear() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let recoveryKey = "nexawal by Nexatrode LLC is a self-custodial interface for managing digital assets. You hold exclusive responsibility for your private keys and 25-word seed phrase."
        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."
        let sendMaxKey = "Send maximum spendable after fee to %@.\nPreview amount: %@\nEstimated fee: %@\nFinal amount is recalculated at send time."

        let hindiRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "hi")
        XCTAssertTrue(hindiRecovery.contains("25-शब्दीय पुनर्प्राप्ति वाक्यांश"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "hi"), "वॉलेट से कुल कटौती (राशि + नेटवर्क शुल्क)")
        let hindiPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "hi")
        XCTAssertTrue(hindiPrivacy.contains("डिफ़ॉल्ट रिमोट नोड आपका IP पता और वॉलेट सिंक अनुरोध देख सकता है"))
        XCTAssertTrue(hindiPrivacy.contains("ऐप rates.nexawal.com से विनिमय दर माँगता है"))
        XCTAssertFalse(hindiPrivacy.contains("contact rates.nexawal.com"))
        let hindiSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "hi")
        XCTAssertTrue(hindiSendMax.contains("नेटवर्क शुल्क घटाने के बाद"))
        XCTAssertEqual(try arguments(in: hindiSendMax), try arguments(in: sendMaxKey))

        let croatianRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "hr")
        XCTAssertTrue(croatianRecovery.contains("frazu za oporavak od 25 riječi"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "hr"), "Ukupno terećenje novčanika (iznos + mrežna naknada)")
        let croatianPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "hr")
        XCTAssertTrue(croatianPrivacy.contains("Zadani udaljeni čvor može vidjeti vašu IP adresu i upite novčanika za sinkronizaciju"))
        XCTAssertTrue(croatianPrivacy.contains("aplikacija dohvaća tečajeve s rates.nexawal.com"))
        XCTAssertFalse(croatianPrivacy.contains("kontaktirajte rates.nexawal.com"))
        let croatianSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "hr")
        XCTAssertTrue(croatianSendMax.contains("nakon odbitka mrežne naknade"))
        XCTAssertEqual(try arguments(in: croatianSendMax), try arguments(in: sendMaxKey))
    }

    func testHungarianAndArmenianWalletCriticalCopyIsClear() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let recoveryKey = "nexawal by Nexatrode LLC is a self-custodial interface for managing digital assets. You hold exclusive responsibility for your private keys and 25-word seed phrase."
        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."
        let sendMaxKey = "Send maximum spendable after fee to %@.\nPreview amount: %@\nEstimated fee: %@\nFinal amount is recalculated at send time."

        let hungarianRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "hu")
        XCTAssertTrue(hungarianRecovery.contains("25 szavas helyreállítási kifejezés"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "hu"), "A pénztárcából levont teljes összeg (összeg + hálózati díj)")
        let hungarianPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "hu")
        XCTAssertTrue(hungarianPrivacy.contains("Az alapértelmezett távoli csomópont láthatja az Ön IP-címét és a tárca szinkronizálási kéréseit"))
        XCTAssertTrue(hungarianPrivacy.contains("az alkalmazás a rates.nexawal.com oldalról kéri le az árfolyamokat"))
        XCTAssertFalse(hungarianPrivacy.contains("forduljon a rates.nexawal.com"))
        let hungarianSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "hu")
        XCTAssertTrue(hungarianSendMax.contains("hálózati díj levonása után"))
        XCTAssertEqual(try arguments(in: hungarianSendMax), try arguments(in: sendMaxKey))

        let armenianRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "hy")
        XCTAssertTrue(armenianRecovery.contains("25 բառից բաղկացած վերականգնման արտահայտության"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "hy"), "Դրամապանակից ընդհանուր գանձվող գումարը (գումար + ցանցի վճար)")
        let armenianPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "hy")
        XCTAssertTrue(armenianPrivacy.contains("Կանխադրված հեռավոր հանգույցը կարող է տեսնել ձեր IP հասցեն և դրամապանակի համաժամացման հարցումները"))
        XCTAssertTrue(armenianPrivacy.contains("հավելվածը փոխարժեքները հարցնում է rates.nexawal.com-ից"))
        XCTAssertFalse(armenianPrivacy.contains("կապվեք rates.nexawal.com"))
        let armenianSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "hy")
        XCTAssertTrue(armenianSendMax.contains("ցանցի վճարը հանելուց հետո"))
        XCTAssertEqual(try arguments(in: armenianSendMax), try arguments(in: sendMaxKey))

        for locale in ["hu", "hy"] {
            XCTAssertTrue(try translatedValue(in: strings, key: "Date range", locale: locale) != "Date range")
            XCTAssertTrue(try translatedValue(in: strings, key: "Filter", locale: locale) != "Filter")
            XCTAssertTrue(try translatedValue(in: strings, key: "Loading transactions…", locale: locale) != "Loading transactions…")
            XCTAssertTrue(try translatedValue(in: strings, key: "Sync failed", locale: locale) != "Sync failed")
        }
    }

    func testIndonesianAndKoreanWalletCriticalCopyIsClear() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let recoveryKey = "nexawal by Nexatrode LLC is a self-custodial interface for managing digital assets. You hold exclusive responsibility for your private keys and 25-word seed phrase."
        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."
        let sendMaxKey = "Send maximum spendable after fee to %@.\nPreview amount: %@\nEstimated fee: %@\nFinal amount is recalculated at send time."
        let sendMaxModeKey = "Send Max mode: Confirm will sweep all unlocked after fee."

        let indonesianRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "id")
        XCTAssertTrue(indonesianRecovery.contains("frasa pemulihan 25 kata"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "id"), "Total yang dipotong dari dompet (jumlah + biaya jaringan)")
        let indonesianPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "id")
        XCTAssertTrue(indonesianPrivacy.contains("Node jarak jauh bawaan dapat melihat alamat IP serta permintaan sinkronisasi dompet Anda"))
        XCTAssertTrue(indonesianPrivacy.contains("aplikasi mengambil kurs dari rates.nexawal.com"))
        XCTAssertFalse(indonesianPrivacy.contains("hubungi rates.nexawal.com"))
        let indonesianSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "id")
        XCTAssertTrue(indonesianSendMax.contains("setelah biaya jaringan dipotong"))
        XCTAssertEqual(try arguments(in: indonesianSendMax), try arguments(in: sendMaxKey))
        XCTAssertTrue(try translatedValue(in: strings, key: sendMaxModeKey, locale: "id").contains("setelah biaya jaringan dipotong"))

        let koreanRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "ko")
        XCTAssertTrue(koreanRecovery.contains("25단어 복구 문구"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "ko"), "지갑에서 차감되는 총액 (금액 + 네트워크 수수료)")
        let koreanPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "ko")
        XCTAssertTrue(koreanPrivacy.contains("기본 원격 노드는 IP 주소와 지갑 동기화 요청을 볼 수 있습니다"))
        XCTAssertTrue(koreanPrivacy.contains("앱이 rates.nexawal.com에서 환율을 가져옵니다"))
        XCTAssertFalse(koreanPrivacy.contains("rates.nexawal.com에 문의"))
        let koreanSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "ko")
        XCTAssertTrue(koreanSendMax.contains("네트워크 수수료를 뺀 최대 사용 가능 금액"))
        XCTAssertEqual(try arguments(in: koreanSendMax), try arguments(in: sendMaxKey))
        XCTAssertTrue(try translatedValue(in: strings, key: sendMaxModeKey, locale: "ko").contains("네트워크 수수료를 제외한"))

        for locale in ["id", "ko"] {
            XCTAssertTrue(try translatedValue(in: strings, key: "Date range", locale: locale) != "Date range")
            XCTAssertTrue(try translatedValue(in: strings, key: "Loading transactions…", locale: locale) != "Loading transactions…")
            XCTAssertTrue(try translatedValue(in: strings, key: "Sync failed", locale: locale) != "Sync failed")
        }
    }

    func testKyrgyzAndLithuanianWalletCriticalCopyIsClear() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let recoveryKey = "nexawal by Nexatrode LLC is a self-custodial interface for managing digital assets. You hold exclusive responsibility for your private keys and 25-word seed phrase."
        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."
        let sendMaxKey = "Send maximum spendable after fee to %@.\nPreview amount: %@\nEstimated fee: %@\nFinal amount is recalculated at send time."
        let sendMaxModeKey = "Send Max mode: Confirm will sweep all unlocked after fee."

        let kyrgyzRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "ky")
        XCTAssertTrue(kyrgyzRecovery.contains("25 сөздөн турган калыбына келтирүү фраза"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "ky"), "Капчыктан жалпы алынуучу сумма (сумма + тармактык комиссия)")
        let kyrgyzPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "ky")
        XCTAssertTrue(kyrgyzPrivacy.contains("Демейки алыскы түйүн IP дарегиңизди жана капчыкты синхрондоштуруу сурамдарын көрө алат"))
        XCTAssertTrue(kyrgyzPrivacy.contains("колдонмо курстарды rates.nexawal.com сайтынан алат"))
        XCTAssertFalse(kyrgyzPrivacy.contains("rates.nexawal.com менен байланышыңыз"))
        let kyrgyzSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "ky")
        XCTAssertTrue(kyrgyzSendMax.contains("тармактык комиссия алынгандан кийин"))
        XCTAssertEqual(try arguments(in: kyrgyzSendMax), try arguments(in: sendMaxKey))
        XCTAssertTrue(try translatedValue(in: strings, key: sendMaxModeKey, locale: "ky").contains("тармактык комиссия алынгандан кийин"))

        let lithuanianRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "lt")
        XCTAssertTrue(lithuanianRecovery.contains("25 žodžių atkūrimo frazę"))
        XCTAssertEqual(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "lt"), "Iš piniginės nurašoma suma (suma + tinklo mokestis)")
        let lithuanianPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "lt")
        XCTAssertTrue(lithuanianPrivacy.contains("Numatytasis nuotolinis mazgas gali matyti jūsų IP adresą ir piniginės sinchronizavimo užklausas"))
        XCTAssertTrue(lithuanianPrivacy.contains("programėlė kursus gauna iš rates.nexawal.com"))
        XCTAssertFalse(lithuanianPrivacy.contains("susisiekite su rates.nexawal.com"))
        let lithuanianSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "lt")
        XCTAssertTrue(lithuanianSendMax.contains("atskaičius tinklo mokestį"))
        XCTAssertEqual(try arguments(in: lithuanianSendMax), try arguments(in: sendMaxKey))

        for locale in ["ky", "lt"] {
            XCTAssertTrue(try translatedValue(in: strings, key: "Date range", locale: locale) != "Date range")
            XCTAssertTrue(try translatedValue(in: strings, key: "Loading transactions…", locale: locale) != "Loading transactions…")
            XCTAssertTrue(try translatedValue(in: strings, key: "Sync failed", locale: locale) != "Sync failed")
        }
    }

    func testLatvianAndMalayWalletCriticalCopyIsClear() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let recoveryKey = "nexawal by Nexatrode LLC is a self-custodial interface for managing digital assets. You hold exclusive responsibility for your private keys and 25-word seed phrase."
        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."
        let sendMaxKey = "Send maximum spendable after fee to %@.\nPreview amount: %@\nEstimated fee: %@\nFinal amount is recalculated at send time."
        let sendMaxModeKey = "Send Max mode: Confirm will sweep all unlocked after fee."
        let maxPreviewKey = "Max preview ready. Confirm Send Max will sweep all unlocked after fee."

        let latvianRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "lv")
        XCTAssertTrue(latvianRecovery.contains("25 vārdu atkopšanas frāzi"))
        XCTAssertTrue(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "lv").contains("summa + tīkla maksa"))
        let latvianPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "lv")
        XCTAssertTrue(latvianPrivacy.contains("lietotne iegūst kursus no rates.nexawal.com"))
        XCTAssertFalse(latvianPrivacy.contains("sazinieties ar rates.nexawal.com"))
        let latvianSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "lv")
        XCTAssertTrue(latvianSendMax.contains("pēc tīkla maksas atskaitīšanas"))
        XCTAssertEqual(try arguments(in: latvianSendMax), try arguments(in: sendMaxKey))
        XCTAssertTrue(try translatedValue(in: strings, key: sendMaxModeKey, locale: "lv").contains("pēc tīkla maksas atskaitīšanas"))
        XCTAssertTrue(try translatedValue(in: strings, key: maxPreviewKey, locale: "lv").contains("pēc tīkla maksas atskaitīšanas"))

        let malayRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "ms")
        XCTAssertTrue(malayRecovery.contains("frasa pemulihan 25 perkataan"))
        XCTAssertTrue(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "ms").contains("amaun + yuran rangkaian"))
        let malayPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "ms")
        XCTAssertTrue(malayPrivacy.contains("aplikasi mendapatkan kadar daripada rates.nexawal.com"))
        XCTAssertFalse(malayPrivacy.contains("hubungi rates.nexawal.com"))
        let malaySendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "ms")
        XCTAssertTrue(malaySendMax.contains("selepas yuran rangkaian ditolak"))
        XCTAssertEqual(try arguments(in: malaySendMax), try arguments(in: sendMaxKey))
        XCTAssertTrue(try translatedValue(in: strings, key: sendMaxModeKey, locale: "ms").contains("selepas yuran rangkaian ditolak"))
        XCTAssertTrue(try translatedValue(in: strings, key: maxPreviewKey, locale: "ms").contains("selepas yuran rangkaian ditolak"))

        for locale in ["lv", "ms"] {
            for key in ["Date range", "Filter", "Loading transactions…", "Mainnet", "Sync failed", "Unlocking…"] {
                XCTAssertNotEqual(try translatedValue(in: strings, key: key, locale: locale), key, "\(key) is untranslated in \(locale)")
            }
        }
        XCTAssertEqual(try translatedValue(in: strings, key: "%llu confirmations", locale: "lv"), "Apstiprinājumu skaits: %llu")
        XCTAssertEqual(try translatedValue(in: strings, key: "%llu confirmations", locale: "ms"), "Bilangan pengesahan: %llu")
        XCTAssertEqual(
            try arguments(in: translatedValue(in: strings, key: "%llu confirmations", locale: "lv")),
            try arguments(in: "%llu confirmations")
        )
        XCTAssertEqual(
            try arguments(in: translatedValue(in: strings, key: "%llu confirmations", locale: "ms")),
            try arguments(in: "%llu confirmations")
        )
    }

    func testBurmeseAndNorwegianWalletCriticalCopyIsClear() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let recoveryKey = "nexawal by Nexatrode LLC is a self-custodial interface for managing digital assets. You hold exclusive responsibility for your private keys and 25-word seed phrase."
        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."
        let sendMaxKey = "Send maximum spendable after fee to %@.\nPreview amount: %@\nEstimated fee: %@\nFinal amount is recalculated at send time."
        let sendMaxModeKey = "Send Max mode: Confirm will sweep all unlocked after fee."
        let maxPreviewKey = "Max preview ready. Confirm Send Max will sweep all unlocked after fee."
        let replaceKey = "This will replace the existing wallet on this device.\n\nIf you continue, the currently stored mnemonic and scan state will be removed. Make sure you have your mnemonic backed up before proceeding."
        let burmeseRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "my")
        XCTAssertTrue(burmeseRecovery.contains("စကားလုံး ၂၅ လုံးပါ ပြန်လည်ရယူရေး စကားစု"))
        let burmeseReplace = try translatedValue(in: strings, key: replaceKey, locale: "my")
        XCTAssertTrue(burmeseReplace.contains("ပြန်လည်ရယူရေး စကားစု"))
        XCTAssertFalse(burmeseReplace.contains("mnemonic"))
        XCTAssertEqual(burmeseReplace.filter { $0 == "\n" }.count, 2)
        XCTAssertFalse(try translatedValue(in: strings, key: "Mnemonic cannot be empty.", locale: "my").contains("mnemonic"))
        XCTAssertFalse(try translatedValue(in: strings, key: "Rescan failed: mnemonic is unavailable.", locale: "my").contains("mnemonic"))
        XCTAssertFalse(try translatedValue(in: strings, key: "Stored mnemonic could not be found.", locale: "my").contains("mnemonic"))
        XCTAssertTrue(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "my").contains("ပမာဏ + ကွန်ရက်အခကြေးငွေ"))
        let burmesePrivacy = try translatedValue(in: strings, key: privacyKey, locale: "my")
        XCTAssertTrue(burmesePrivacy.contains("အက်ပ်သည် rates.nexawal.com မှ ဈေးနှုန်းများကို ရယူသည်"))
        XCTAssertFalse(burmesePrivacy.contains("rates.nexawal.com သို့ ဆက်သွယ်ပါ"))
        let burmeseSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "my")
        XCTAssertTrue(burmeseSendMax.contains("ကွန်ရက်အခကြေးငွေ နုတ်ပြီးနောက်"))
        XCTAssertEqual(try arguments(in: burmeseSendMax), try arguments(in: sendMaxKey))
        XCTAssertTrue(try translatedValue(in: strings, key: sendMaxModeKey, locale: "my").contains("ကွန်ရက်အခကြေးငွေ နုတ်ပြီးနောက်"))
        XCTAssertTrue(try translatedValue(in: strings, key: maxPreviewKey, locale: "my").contains("ကွန်ရက်အခကြေးငွေ နုတ်ပြီးနောက်"))

        let norwegianRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "nb")
        XCTAssertTrue(norwegianRecovery.contains("gjenopprettingsfrasen på 25 ord"))
        let norwegianReplace = try translatedValue(in: strings, key: replaceKey, locale: "nb")
        XCTAssertTrue(norwegianReplace.contains("gjenopprettingsfrasen"))
        XCTAssertFalse(norwegianReplace.contains("mnemonic"))
        XCTAssertEqual(norwegianReplace.filter { $0 == "\n" }.count, 2)
        XCTAssertFalse(try translatedValue(in: strings, key: "Mnemonic cannot be empty.", locale: "nb").contains("mnemonic"))
        XCTAssertFalse(try translatedValue(in: strings, key: "Rescan failed: mnemonic is unavailable.", locale: "nb").contains("mnemonic"))
        XCTAssertFalse(try translatedValue(in: strings, key: "Stored mnemonic could not be found.", locale: "nb").contains("mnemonic"))
        XCTAssertTrue(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "nb").contains("beløp + nettverksgebyr"))
        let norwegianPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "nb")
        XCTAssertTrue(norwegianPrivacy.contains("henter appen kurs fra rates.nexawal.com"))
        XCTAssertFalse(norwegianPrivacy.contains("kontakt rates.nexawal.com"))
        let norwegianSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "nb")
        XCTAssertTrue(norwegianSendMax.contains("etter at nettverksgebyret er trukket fra"))
        XCTAssertEqual(try arguments(in: norwegianSendMax), try arguments(in: sendMaxKey))
        XCTAssertTrue(try translatedValue(in: strings, key: sendMaxModeKey, locale: "nb").contains("etter at nettverksgebyret er trukket fra"))
        XCTAssertTrue(try translatedValue(in: strings, key: maxPreviewKey, locale: "nb").contains("etter at nettverksgebyret er trukket fra"))

        for locale in ["my", "nb"] {
            for key in ["Date range", "Filter", "Loading transactions…", "Mainnet", "Sync failed", "Unlocking…"] {
                XCTAssertNotEqual(try translatedValue(in: strings, key: key, locale: locale), key, "\(key) is untranslated in \(locale)")
            }
        }
    }

    func testRomanianAndSlovakWalletCriticalCopyIsClear() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let recoveryKey = "nexawal by Nexatrode LLC is a self-custodial interface for managing digital assets. You hold exclusive responsibility for your private keys and 25-word seed phrase."
        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."
        let sendMaxKey = "Send maximum spendable after fee to %@.\nPreview amount: %@\nEstimated fee: %@\nFinal amount is recalculated at send time."
        let sendMaxModeKey = "Send Max mode: Confirm will sweep all unlocked after fee."
        let maxPreviewKey = "Max preview ready. Confirm Send Max will sweep all unlocked after fee."
        let replaceKey = "This will replace the existing wallet on this device.\n\nIf you continue, the currently stored mnemonic and scan state will be removed. Make sure you have your mnemonic backed up before proceeding."
        let seedBoxKey = "Click the seed box, paste with ⌘V, set restore height, then Open & sync."
        let lockedWalletKey = "Locked. Open the existing wallet from {}, or restore a different seed."
        let openExistingWalletKey = "Open the existing wallet from {}, or restore a different seed."
        let unlockRetryKey = "Use Open existing wallet to try again, or restore from seed."

        let romanianRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "ro")
        XCTAssertTrue(romanianRecovery.contains("fraza de recuperare de 25 de cuvinte"))
        let romanianReplace = try translatedValue(in: strings, key: replaceKey, locale: "ro")
        XCTAssertTrue(romanianReplace.contains("fraza de recuperare"))
        XCTAssertFalse(romanianReplace.contains("mnemonic"))
        XCTAssertTrue(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "ro").contains("sumă + comision"))
        XCTAssertTrue(try translatedValue(in: strings, key: "Amount is the total wallet debit, including the network fee.", locale: "ro").contains("comisionul de rețea"))
        let romanianPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "ro")
        XCTAssertTrue(romanianPrivacy.contains("adresa ta IP și cererile de sincronizare ale portofelului"))
        XCTAssertTrue(romanianPrivacy.contains("aplicația preia cursurile de la rates.nexawal.com"))
        XCTAssertFalse(romanianPrivacy.contains("contactați rates.nexawal.com"))
        let romanianSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "ro")
        XCTAssertTrue(romanianSendMax.contains("după deducerea comisionului de rețea"))
        XCTAssertEqual(try arguments(in: romanianSendMax), try arguments(in: sendMaxKey))
        XCTAssertTrue(try translatedValue(in: strings, key: sendMaxModeKey, locale: "ro").contains("după deducerea comisionului de rețea"))
        XCTAssertTrue(try translatedValue(in: strings, key: maxPreviewKey, locale: "ro").contains("după deducerea comisionului de rețea"))

        let slovakRecovery = try translatedValue(in: strings, key: recoveryKey, locale: "sk")
        XCTAssertTrue(slovakRecovery.contains("25-slovnú frázu na obnovenie"))
        let slovakReplace = try translatedValue(in: strings, key: replaceKey, locale: "sk")
        XCTAssertTrue(slovakReplace.contains("frázu na obnovenie"))
        XCTAssertFalse(slovakReplace.contains("mnemonic"))
        XCTAssertTrue(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "sk").contains("suma + poplatok"))
        XCTAssertTrue(try translatedValue(in: strings, key: "Amount is the total wallet debit, including the network fee.", locale: "sk").contains("sieťového poplatku"))
        let slovakPrivacy = try translatedValue(in: strings, key: privacyKey, locale: "sk")
        XCTAssertTrue(slovakPrivacy.contains("vašu IP adresu a požiadavky na synchronizáciu peňaženky"))
        XCTAssertTrue(slovakPrivacy.contains("aplikácia načítava kurzy zo servera rates.nexawal.com"))
        XCTAssertFalse(slovakPrivacy.contains("kontaktujte rates.nexawal.com"))
        let slovakSendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "sk")
        XCTAssertTrue(slovakSendMax.contains("po odpočítaní sieťového poplatku"))
        XCTAssertEqual(try arguments(in: slovakSendMax), try arguments(in: sendMaxKey))
        XCTAssertTrue(try translatedValue(in: strings, key: sendMaxModeKey, locale: "sk").contains("po odpočítaní sieťového poplatku"))
        XCTAssertTrue(try translatedValue(in: strings, key: maxPreviewKey, locale: "sk").contains("po odpočítaní sieťového poplatku"))
        for key in [seedBoxKey, lockedWalletKey, openExistingWalletKey, unlockRetryKey] {
            let romanianValue = try translatedValue(in: strings, key: key, locale: "ro")
            XCTAssertTrue(romanianValue.contains("recuperare"), "Recovery phrase wording missing from Romanian: \(key)")
            XCTAssertFalse(romanianValue.contains("seed"), "Technical seed term remains in Romanian: \(key)")
            let slovakValue = try translatedValue(in: strings, key: key, locale: "sk")
            XCTAssertTrue(slovakValue.contains("obnoven"), "Recovery phrase wording missing from Slovak: \(key)")
            XCTAssertFalse(slovakValue.contains("seed"), "Technical seed term remains in Slovak: \(key)")
        }

        XCTAssertTrue(try translatedValue(in: strings, key: "%llu confirmations", locale: "ro").contains("Număr de confirmări"))
        XCTAssertTrue(try translatedValue(in: strings, key: "%llu confirmations", locale: "sk").contains("Počet potvrdení"))
        for locale in ["ro", "sk"] {
            XCTAssertEqual(
                try arguments(in: translatedValue(in: strings, key: "%llu confirmations", locale: locale)),
                try arguments(in: "%llu confirmations")
            )
        }

        for locale in ["ro", "sk"] {
            for key in ["Date range", "Filter", "Loading transactions…", "Mainnet", "Sync failed", "Unlocking…"] {
                XCTAssertNotEqual(try translatedValue(in: strings, key: key, locale: locale), key, "\(key) is untranslated in \(locale)")
            }
        }
    }

    func testSlovenianAndAlbanianWalletCriticalCopyIsClear() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let recoveryKey = "nexawal by Nexatrode LLC is a self-custodial interface for managing digital assets. You hold exclusive responsibility for your private keys and 25-word seed phrase."
        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."
        let sendMaxKey = "Send maximum spendable after fee to %@.\nPreview amount: %@\nEstimated fee: %@\nFinal amount is recalculated at send time."
        let sendMaxModeKey = "Send Max mode: Confirm will sweep all unlocked after fee."
        let maxPreviewKey = "Max preview ready. Confirm Send Max will sweep all unlocked after fee."
        let debitKey = "Wallet debit (amount + fee)"
        let debitHelpKey = "Amount is the total wallet debit, including the network fee."
        let recoveryKeys = [
            recoveryKey,
            "This will replace the existing wallet on this device.\n\nIf you continue, the currently stored mnemonic and scan state will be removed. Make sure you have your mnemonic backed up before proceeding.",
            "Generate new seed",
            "I wrote down my recovery seed",
            "Mnemonic (paste):",
            "Mnemonic cannot be empty.",
            "Stored mnemonic could not be found.",
            "Rescan failed: mnemonic is unavailable.",
        ]

        for locale in ["sl", "sq"] {
            let recovery = try translatedValue(in: strings, key: recoveryKey, locale: locale)
            XCTAssertTrue(recovery.contains("obnovit" ) || recovery.contains("rikuperim"), "Recovery phrase wording missing in \(locale)")
            for key in recoveryKeys {
                let value = try translatedValue(in: strings, key: key, locale: locale).lowercased()
                XCTAssertFalse(value.contains("seed"), "Technical seed wording remains in \(locale): \(key)")
                XCTAssertFalse(value.contains("mnemonic"), "Technical mnemonic wording remains in \(locale): \(key)")
            }

            let privacy = try translatedValue(in: strings, key: privacyKey, locale: locale)
            XCTAssertTrue(privacy.contains("rates.nexawal.com"))
            XCTAssertTrue(privacy.contains("IP"))
            XCTAssertFalse(privacy.localizedCaseInsensitiveContains("contact"))
            XCTAssertFalse(privacy.localizedCaseInsensitiveContains("obrnite"))

            let sendMax = try translatedValue(in: strings, key: sendMaxKey, locale: locale)
            XCTAssertEqual(try arguments(in: sendMax), try arguments(in: sendMaxKey))
            XCTAssertEqual(sendMax.components(separatedBy: "%@").count - 1, 3)
            if locale == "sl" {
                XCTAssertTrue(try translatedValue(in: strings, key: sendMaxModeKey, locale: locale).contains("omrežnine"))
                XCTAssertTrue(try translatedValue(in: strings, key: maxPreviewKey, locale: locale).contains("omrežnine"))
            } else {
                XCTAssertTrue(try translatedValue(in: strings, key: sendMaxModeKey, locale: locale).contains("rrjetit"))
                XCTAssertTrue(try translatedValue(in: strings, key: maxPreviewKey, locale: locale).contains("rrjetit"))
            }

            let debit = try translatedValue(in: strings, key: debitKey, locale: locale)
            XCTAssertTrue(debit.contains("odpis") || debit.contains("Debiti total"))
            let debitHelp = try translatedValue(in: strings, key: debitHelpKey, locale: locale)
            XCTAssertTrue(debitHelp.contains("omrežnino") || debitHelp.contains("tarifën e rrjetit"))
            XCTAssertEqual(
                try arguments(in: translatedValue(in: strings, key: "%llu confirmations", locale: locale)),
                try arguments(in: "%llu confirmations")
            )
            for key in ["Date range", "Filter", "Loading transactions…", "Mainnet", "Sync failed", "Unlocking…"] {
                XCTAssertNotEqual(try translatedValue(in: strings, key: key, locale: locale), key, "\(key) is untranslated in \(locale)")
            }
        }
    }

    func testSwedishAndThaiWalletCriticalCopyIsClear() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let recoveryKey = "nexawal by Nexatrode LLC is a self-custodial interface for managing digital assets. You hold exclusive responsibility for your private keys and 25-word seed phrase."
        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."
        let rateKey = "Optional. When enabled, NexaWal requests an XMR rate for your selected currency from rates.nexawal.com over HTTPS. This request uses clearnet even when the wallet node uses I2P. Nexatrode can see your IP address and selected currency; wallet amounts, addresses, seeds, and transaction history are not sent. Estimates only — XMR is what you send and hold."
        let sendMaxKey = "Send maximum spendable after fee to %@.\nPreview amount: %@\nEstimated fee: %@\nFinal amount is recalculated at send time."
        let sendMaxModeKey = "Send Max mode: Confirm will sweep all unlocked after fee."
        let maxPreviewKey = "Max preview ready. Confirm Send Max will sweep all unlocked after fee."
        let recoveryKeys = [
            recoveryKey,
            "This will replace the existing wallet on this device.\n\nIf you continue, the currently stored mnemonic and scan state will be removed. Make sure you have your mnemonic backed up before proceeding.",
            "Generate new seed",
            "I wrote down my recovery seed",
            "Mnemonic (paste):",
            "Mnemonic cannot be empty.",
            "Stored mnemonic could not be found.",
            "Rescan failed: mnemonic is unavailable.",
            "Click the seed box, paste with ⌘V, set restore height, then Open & sync.",
            "Locked. Open the existing wallet from {}, or restore a different seed.",
            "Open the existing wallet from {}, or restore a different seed.",
            "Use Open existing wallet to try again, or restore from seed.",
        ]

        for locale in ["sv", "th"] {
            let recovery = try translatedValue(in: strings, key: recoveryKey, locale: locale)
            XCTAssertTrue(recovery.contains("återställningsfras") || recovery.contains("วลีกู้คืน"))
            for key in recoveryKeys {
                let value = try translatedValue(in: strings, key: key, locale: locale).lowercased()
                XCTAssertFalse(value.contains("seed"), "Technical seed wording remains in \(locale): \(key)")
                XCTAssertFalse(value.contains("mnemonic"), "Technical mnemonic wording remains in \(locale): \(key)")
                XCTAssertFalse(value.contains("frö"), "Technical seed wording remains in Swedish: \(key)")
                XCTAssertFalse(value.contains("ซีด") || value.contains("ช่วยจำ"), "Technical seed wording remains in Thai: \(key)")
            }

            let privacy = try translatedValue(in: strings, key: privacyKey, locale: locale)
            XCTAssertTrue(privacy.contains("rates.nexawal.com"))
            XCTAssertFalse(privacy.localizedCaseInsensitiveContains("contact"))
            XCTAssertFalse(privacy.localizedCaseInsensitiveContains("kontakta"))
            XCTAssertFalse(privacy.contains("ติดต่อ"))
            let rates = try translatedValue(in: strings, key: rateKey, locale: locale)
            XCTAssertTrue(rates.contains("I2P"))
            XCTAssertTrue(rates.contains("rates.nexawal.com"))

            let sendMax = try translatedValue(in: strings, key: sendMaxKey, locale: locale)
            XCTAssertEqual(try arguments(in: sendMax), try arguments(in: sendMaxKey))
            XCTAssertEqual(sendMax.components(separatedBy: "%@").count - 1, 3)
            let feePhrase = locale == "sv" ? "nätverksavgiften" : "ค่าธรรมเนียมเครือข่าย"
            XCTAssertTrue(try translatedValue(in: strings, key: sendMaxModeKey, locale: locale).contains(feePhrase))
            XCTAssertTrue(try translatedValue(in: strings, key: maxPreviewKey, locale: locale).contains(feePhrase))
            let debit = try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: locale)
            XCTAssertTrue(debit.contains("debiterat") || debit.contains("ยอดหัก"))
            XCTAssertEqual(
                try arguments(in: translatedValue(in: strings, key: "%llu confirmations", locale: locale)),
                try arguments(in: "%llu confirmations")
            )

            for key in ["Date range", "Filter", "Loading transactions…", "Mainnet", "Sync failed", "Unlocking…"] {
                XCTAssertNotEqual(try translatedValue(in: strings, key: key, locale: locale), key, "\(key) is untranslated in \(locale)")
            }
        }
    }

    func testUkrainianAndUrduWalletCriticalCopyIsClear() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let recoveryKey = "nexawal by Nexatrode LLC is a self-custodial interface for managing digital assets. You hold exclusive responsibility for your private keys and 25-word seed phrase."
        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."
        let sendMaxKey = "Send maximum spendable after fee to %@.\nPreview amount: %@\nEstimated fee: %@\nFinal amount is recalculated at send time."
        let sendMaxModeKey = "Send Max mode: Confirm will sweep all unlocked after fee."
        let maxPreviewKey = "Max preview ready. Confirm Send Max will sweep all unlocked after fee."
        let recoveryKeys = [
            recoveryKey,
            "This will replace the existing wallet on this device.\n\nIf you continue, the currently stored mnemonic and scan state will be removed. Make sure you have your mnemonic backed up before proceeding.",
            "Generate new seed",
            "I wrote down my recovery seed",
            "Mnemonic (paste):",
            "Mnemonic cannot be empty.",
            "Stored mnemonic could not be found.",
            "Rescan failed: mnemonic is unavailable.",
        ]

        for locale in ["uk", "ur"] {
            let recovery = try translatedValue(in: strings, key: recoveryKey, locale: locale)
            if locale == "uk" {
                XCTAssertTrue(recovery.contains("фразу відновлення"))
            } else {
                XCTAssertTrue(recovery.contains("بحالی") && recovery.contains("فقرے"))
            }
            for key in recoveryKeys {
                let value = try translatedValue(in: strings, key: key, locale: locale).lowercased()
                XCTAssertFalse(value.contains("seed"), "Technical seed wording remains in \(locale): \(key)")
                XCTAssertFalse(value.contains("mnemonic"), "Technical mnemonic wording remains in \(locale): \(key)")
                if locale == "uk" {
                    XCTAssertFalse(value.contains("мнемон"), "Technical mnemonic transliteration remains in Ukrainian: \(key)")
                } else {
                    XCTAssertFalse(value.contains("سیڈ") || value.contains("منیمونک"), "Technical seed/mnemonic transliteration remains in Urdu: \(key)")
                }
            }

            let privacy = try translatedValue(in: strings, key: privacyKey, locale: locale)
            XCTAssertTrue(privacy.contains("rates.nexawal.com"))
            XCTAssertTrue(privacy.contains("IP"))
            XCTAssertFalse(privacy.localizedCaseInsensitiveContains("contact"))
            XCTAssertFalse(privacy.contains("رابطہ"))

            let sendMax = try translatedValue(in: strings, key: sendMaxKey, locale: locale)
            XCTAssertEqual(try arguments(in: sendMax), try arguments(in: sendMaxKey))
            XCTAssertEqual(sendMax.components(separatedBy: "%@").count - 1, 3)
            let feeTerm = locale == "uk" ? "мережевої комісії" : "نیٹ ورک فیس"
            XCTAssertTrue(try translatedValue(in: strings, key: sendMaxModeKey, locale: locale).contains(feeTerm))
            XCTAssertTrue(try translatedValue(in: strings, key: maxPreviewKey, locale: locale).contains(feeTerm))

            let debit = try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: locale)
            XCTAssertTrue(debit.contains("списання") || debit.contains("کٹوتی"))
            let debitHelp = try translatedValue(in: strings, key: "Amount is the total wallet debit, including the network fee.", locale: locale)
            XCTAssertTrue(debitHelp.contains("мережевою комісією") || debitHelp.contains("نیٹ ورک فیس"))
            XCTAssertEqual(
                try arguments(in: translatedValue(in: strings, key: "%llu confirmations", locale: locale)),
                try arguments(in: "%llu confirmations")
            )

            for key in ["Date range", "Filter", "Loading transactions…", "Mainnet", "Sync failed", "Unlocking…"] {
                XCTAssertNotEqual(try translatedValue(in: strings, key: key, locale: locale), key, "\(key) is untranslated in \(locale)")
            }
        }
    }

    func testYorubaWalletCriticalCopyIsClear() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let recoveryKey = "nexawal by Nexatrode LLC is a self-custodial interface for managing digital assets. You hold exclusive responsibility for your private keys and 25-word seed phrase."
        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."
        let rateKey = "Optional. When enabled, NexaWal requests an XMR rate for your selected currency from rates.nexawal.com over HTTPS. This request uses clearnet even when the wallet node uses I2P. Nexatrode can see your IP address and selected currency; wallet amounts, addresses, seeds, and transaction history are not sent. Estimates only — XMR is what you send and hold."
        let sendMaxKey = "Send maximum spendable after fee to %@.\nPreview amount: %@\nEstimated fee: %@\nFinal amount is recalculated at send time."
        let sendMaxModeKey = "Send Max mode: Confirm will sweep all unlocked after fee."
        let maxPreviewKey = "Max preview ready. Confirm Send Max will sweep all unlocked after fee."
        let recoveryKeys = [
            recoveryKey,
            "This will replace the existing wallet on this device.\n\nIf you continue, the currently stored mnemonic and scan state will be removed. Make sure you have your mnemonic backed up before proceeding.",
            "Generate new seed",
            "I wrote down my recovery seed",
            "Write these words down in order and store them somewhere safe offline. You'll need them to restore the wallet if this phone is lost. NexaWal also keeps an encrypted copy on device for unlock — treat the backup like cash.",
            "Mnemonic (paste):",
            "Mnemonic cannot be empty.",
            "Stored mnemonic could not be found.",
            "Rescan failed: mnemonic is unavailable.",
            "Click the seed box, paste with ⌘V, set restore height, then Open & sync.",
            "Locked. Open the existing wallet from {}, or restore a different seed.",
            "Open the existing wallet from {}, or restore a different seed.",
            "Use Open existing wallet to try again, or restore from seed.",
        ]

        let recovery = try translatedValue(in: strings, key: recoveryKey, locale: "yo")
        XCTAssertTrue(recovery.contains("ọ̀rọ̀ ìpadàbọ̀"))
        for key in recoveryKeys {
            let value = try translatedValue(in: strings, key: key, locale: "yo").lowercased()
            XCTAssertFalse(value.contains("seed"), "Technical seed wording remains in Yoruba: \(key)")
            XCTAssertFalse(value.contains("mnemonic"), "Technical mnemonic wording remains in Yoruba: \(key)")
            XCTAssertFalse(value.contains("irugbin") || value.contains("ìrùgbìn"), "Literal seed wording remains in Yoruba: \(key)")
        }

        let privacy = try translatedValue(in: strings, key: privacyKey, locale: "yo")
        XCTAssertTrue(privacy.contains("rates.nexawal.com"))
        XCTAssertTrue(privacy.contains("IP"))
        XCTAssertFalse(privacy.localizedCaseInsensitiveContains("contact"))
        XCTAssertFalse(privacy.contains("kan si rates.nexawal.com"))
        let rates = try translatedValue(in: strings, key: rateKey, locale: "yo")
        XCTAssertTrue(rates.contains("I2P"))
        XCTAssertTrue(rates.contains("rates.nexawal.com"))
        XCTAssertTrue(rates.contains("a kì í fi"))

        let sendMax = try translatedValue(in: strings, key: sendMaxKey, locale: "yo")
        XCTAssertEqual(try arguments(in: sendMax), try arguments(in: sendMaxKey))
        XCTAssertEqual(sendMax.components(separatedBy: "%@").count - 1, 3)
        for key in [sendMaxModeKey, maxPreviewKey] {
            XCTAssertTrue(try translatedValue(in: strings, key: key, locale: "yo").contains("ọya nẹ́tíwọ́ọ̀kì"))
        }
        XCTAssertTrue(try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: "yo").contains("iye + ọya nẹ́tíwọ́ọ̀kì"))
        XCTAssertTrue(try translatedValue(in: strings, key: "Amount is the total wallet debit, including the network fee.", locale: "yo").contains("ọya nẹ́tíwọ́ọ̀kì"))
        XCTAssertEqual(
            try arguments(in: translatedValue(in: strings, key: "%llu confirmations", locale: "yo")),
            try arguments(in: "%llu confirmations")
        )
        for key in ["Date range", "Filter", "Loading transactions…", "Mainnet", "Sync failed", "Unlocking…"] {
            XCTAssertNotEqual(try translatedValue(in: strings, key: key, locale: "yo"), key, "\(key) is untranslated in Yoruba")
        }
        XCTAssertTrue(try translatedValue(in: strings, key: "This will replace the existing wallet on this device.\n\nIf you continue, the currently stored mnemonic and scan state will be removed. Make sure you have your mnemonic backed up before proceeding.", locale: "yo").contains("\n\n"))
    }

    func testVietnameseAndChineseWalletCriticalCopyIsClear() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let custodyKey = "nexawal by Nexatrode LLC is a self-custodial interface for managing digital assets. You hold exclusive responsibility for your private keys and 25-word seed phrase."
        let privacyKey = "MIT-licensed, unaudited software. You are responsible for your seed and funds. The default remote node can see your IP and wallet sync queries — run your own node for stronger privacy. Optional fiat estimates, if enabled, contact rates.nexawal.com for rates."
        let ratePrivacyKey = "Optional. When enabled, NexaWal requests an XMR rate for your selected currency from rates.nexawal.com over HTTPS. This request uses clearnet even when the wallet node uses I2P. Nexatrode can see your IP address and selected currency; wallet amounts, addresses, seeds, and transaction history are not sent. Estimates only — XMR is what you send and hold."
        let sendMaxKey = "Send maximum spendable after fee to %@.\nPreview amount: %@\nEstimated fee: %@\nFinal amount is recalculated at send time."
        let sendMaxModeKey = "Send Max mode: Confirm will sweep all unlocked after fee."
        let maxPreviewKey = "Max preview ready. Confirm Send Max will sweep all unlocked after fee."
        let recoveryKeys = [
            custodyKey,
            "This will replace the existing wallet on this device.\n\nIf you continue, the currently stored mnemonic and scan state will be removed. Make sure you have your mnemonic backed up before proceeding.",
            "Generate new seed", "I wrote down my recovery seed", "Seed word",
            "Couldn't generate a seed: %@", "Mnemonic (paste):", "Mnemonic cannot be empty.",
            "Rescan failed: mnemonic is unavailable.", "Stored mnemonic could not be found.",
            "Click the seed box, paste with ⌘V, set restore height, then Open & sync.",
            "Confirm you wrote it down: enter the requested words below.",
            "Write these words down in order and store them somewhere safe offline. You'll need them to restore the wallet if this phone is lost. NexaWal also keeps an encrypted copy on device for unlock — treat the backup like cash.",
            "Locked. Open the existing wallet from {}, or restore a different seed.",
            "Open the existing wallet from {}, or restore a different seed.",
            "Use Open existing wallet to try again, or restore from seed.",
        ]
        let locales: [(String, String, String, String, String, String, String)] = [
            ("vi", "cụm từ khôi phục", "phí mạng", "đồng bộ", "số tiền + phí", "số lần xác nhận", "Xác nhận"),
            ("zh-Hans", "恢复短语", "网络手续费", "同步", "金额 + 手续费", "确认次数", "确认次数"),
            ("zh-Hant", "復原詞組", "網路手續費", "同步", "金額 + 手續費", "確認次數", "確認次數"),
        ]

        for (locale, recoveryTerm, feeTerm, syncTerm, debitTerm, confirmationTerm, confirmationTitleTerm) in locales {
            let technicalRecoveryTerm = locale == "vi" ? "mnemonic" : (locale == "zh-Hans" ? "助记词" : "助記詞")
            let literalSeedTerm = locale == "vi" ? "hạt giống" : (locale == "zh-Hans" ? "种子" : "種子")
            for key in recoveryKeys {
                let value = try translatedValue(in: strings, key: key, locale: locale)
                XCTAssertTrue(value.localizedCaseInsensitiveContains(recoveryTerm), "recovery phrase missing in \(locale): \(key)")
                XCTAssertFalse(value.localizedCaseInsensitiveContains(technicalRecoveryTerm), "technical recovery wording in \(locale): \(key)")
                XCTAssertFalse(value.localizedCaseInsensitiveContains(literalSeedTerm), "literal seed wording in \(locale): \(key)")
            }

            let custody = try translatedValue(in: strings, key: custodyKey, locale: locale)
            let custodyTerm = locale == "vi" ? "bạn tự quản lý" : (locale == "zh-Hans" ? "自行管理私钥" : "自託管介面")
            XCTAssertTrue(custody.localizedCaseInsensitiveContains(custodyTerm))

            let sendMax = try translatedValue(in: strings, key: sendMaxKey, locale: locale)
            XCTAssertTrue(sendMax.localizedCaseInsensitiveContains(feeTerm), "Send Max must disclose the network fee in \(locale)")
            XCTAssertEqual(try arguments(in: sendMax), try arguments(in: sendMaxKey))
            for key in [sendMaxModeKey, maxPreviewKey] {
                XCTAssertTrue(try translatedValue(in: strings, key: key, locale: locale).localizedCaseInsensitiveContains(feeTerm), "fee deduction missing in \(locale): \(key)")
            }

            let debit = try translatedValue(in: strings, key: "Wallet debit (amount + fee)", locale: locale)
            XCTAssertTrue(debit.localizedCaseInsensitiveContains(debitTerm))
            XCTAssertTrue(try translatedValue(in: strings, key: "Confirmations", locale: locale).localizedCaseInsensitiveContains(confirmationTitleTerm))
            let confirmations = try translatedValue(in: strings, key: "%llu confirmations", locale: locale)
            XCTAssertTrue(confirmations.contains("%llu"))
            XCTAssertTrue(confirmations.localizedCaseInsensitiveContains(confirmationTerm))

            let hybrid = try translatedValue(in: strings, key: "Both (scan clearnet, broadcast I2P)", locale: locale)
            XCTAssertTrue(hybrid.localizedCaseInsensitiveContains("Clearnet"))
            XCTAssertTrue(hybrid.localizedCaseInsensitiveContains("I2P"))
            XCTAssertTrue(hybrid.localizedCaseInsensitiveContains(syncTerm))
            XCTAssertTrue(try translatedValue(in: strings, key: "Mainnet", locale: locale) != "Mainnet")

            let privacy = try translatedValue(in: strings, key: privacyKey, locale: locale)
            XCTAssertTrue(privacy.contains("rates.nexawal.com"))
            XCTAssertTrue(privacy.localizedCaseInsensitiveContains("IP"))
            XCTAssertFalse(privacy.localizedCaseInsensitiveContains("contact"))
            let ratePrivacy = try translatedValue(in: strings, key: ratePrivacyKey, locale: locale)
            XCTAssertTrue(ratePrivacy.localizedCaseInsensitiveContains(recoveryTerm))
            XCTAssertTrue(ratePrivacy.contains("rates.nexawal.com"))
            XCTAssertFalse(ratePrivacy.localizedCaseInsensitiveContains(technicalRecoveryTerm))
            XCTAssertFalse(ratePrivacy.localizedCaseInsensitiveContains(literalSeedTerm))
        }
    }

    private func loadCatalog() throws -> [String: Any] {
        let data = try Data(contentsOf: catalogURL())
        let json = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(json as? [String: Any])
    }

    private func catalogURL() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        var catalog: URL?
        for _ in 0..<8 {
            let candidate = dir.appendingPathComponent("nexawal/Localizable.xcstrings")
            if FileManager.default.fileExists(atPath: candidate.path) {
                catalog = candidate
                break
            }
            dir.deleteLastPathComponent()
        }
        return try XCTUnwrap(catalog, "Localizable.xcstrings not found from \(#filePath)")
    }

    private func locales(in strings: [String: Any], key: String) throws -> Set<String> {
        let entry = try XCTUnwrap(strings[key] as? [String: Any], "missing catalog key \(key)")
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
        return Set(localizations.keys)
    }

    private func translatedValue(in strings: [String: Any], key: String, locale: String) throws -> String {
        let entry = try XCTUnwrap(strings[key] as? [String: Any])
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
        let loc = try XCTUnwrap(localizations[locale] as? [String: Any], "missing \(locale) for \(key)")
        let unit = try XCTUnwrap(loc["stringUnit"] as? [String: Any])
        return try XCTUnwrap(unit["value"] as? String).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
