# Translation review status

The October 12, 2026 audit checks every translatable catalog entry for locale
coverage, nonblank values and preserved printf argument positions/types. Numeric
formats, URLs and currency symbols are intentionally not translated. Computed
send/history labels must use `L10n`, not a runtime English `String`.

New recovery-word, send-max, history and unaudited-software/privacy translations
are drafts. They were machine-generated or reused from the other app catalogs,
and are marked `needs_review`. Automated checks do not establish fluent-language
quality. Review the drafts with fluent speakers, especially seed backup, sending,
authentication and privacy wording. Existing `translated` status is not evidence
of independent human review either.

Full bundled legal documents remain English; localized UI summaries are not
translations of the legal agreement. Diagnostic/native error details and
addresses, transaction IDs, ISO currency codes and protocol URLs stay verbatim.

Run `swift test` in `Packages/NexaWalLogic`. The GPUI repository also provides
`scripts/check-l10n.py --ios <ios-main> --android <android-main>` for a shared
offline structural check.
