# Optional native explorer details

This feature is **off by default**, independently of fiat estimates. It does not affect wallet sync, balance, transaction history, fees, or sending.

1. In Settings, read the disclosure and enable **Explorer details**. Enabling alone does not contact the service.
2. Open a transaction from Recent Transactions or the full transaction list, then choose **Explorer details**.
3. The app requests that one transaction from `https://explorer.nexawal.com/api/v1/transactions/{txid}`. This is separate clearnet HTTPS, **even if wallet RPC uses I2P**. The operator/providers can see the connection IP, requested ID, and time.
4. The view reports public status, exact network fee when available, observed confirmations, block data, and observation time. These are an explorer node's observations, not wallet verification or a private payment amount.
5. Refresh is manual. Closing/backgrounding the view or disabling access invalidates/cancels the lookup. Returning from the background does not poll. You can still copy a website link without making an API request.

There is no account, API key, seed/view-key entry, full-history upload, persistent response cache, or automatic repair/rescan based on these results. Mainnet only for the current public service. Errors are shown separately; a missing result is never proof that a payment is lost.

## Phone / desktop smoke checklist

No new funded send or seed disclosure is needed. Use an existing transaction, or a disposable test wallet.

- Fresh/existing install: setting starts off; opening the disabled view makes no explorer request.
- Enabling alone, including while a disabled view is mounted, makes no request.
- Open/reopen while enabled: one lookup; pending/confirmed status, fee units, block hash and observation time make sense.
- Copy link: correct `/tx/<id>` URL; does not fetch it.
- Close/back/background/lock during a delayed response: no late data leaks into another view or wallet session.
- Resume: manual Refresh is required after backgrounding; no repeated polling.
- Disable: data is cleared; requests stop; rates preference is unchanged.
- Offline, HTTP errors, unsupported API, stale node: clear error/warning; wallet balance/history stay unchanged.
- Non-mainnet mobile wallet: public explorer lookup is blocked.
- Standard and Techno themes, small screen, large text, screen reader, and non-English locale: controls remain usable and disclosure/error copy is localized.

New feature copy covers all 54 existing app locales. Translations are drafts; human review of privacy/safety wording is recommended. Explorer website translations are separate.

