# nexawal privacy policy

Last updated: 2 October 2026

nexawal is a local Monero wallet. This policy covers the iOS app published from https://github.com/Nexatrode/nexawal.

This text is bundled in the app for offline reading. A copy may also be published at https://nexatrode.com/privacy/nexawal/.

## What stays on your device

- Your seed, spend/view keys, and wallet cache stay on the device.
- Optional Face ID / Touch ID is handled by the system; we do not receive biometric data.
- Settings (node URL, UI theme, scan lookahead, biometric lock preference, optional fiat estimates) are stored locally.

We do not operate an account system, and we do not ship third-party analytics or crash reporters.

## Network

The app talks to the Monero daemon RPC you configure. Fresh installs default to `https://rpc.nexatrode.com`.

A remote node can typically see:

- your IP address
- when you sync and broadcast
- which outputs the wallet queries while scanning

It does not receive your seed. For stronger privacy, point the app at a node you run.

I2P / hybrid mode, when enabled, routes the configured traffic through your local I2P HTTP proxy instead of (or in addition to) clearnet.

Optional fiat estimates are off by default. If you turn them on, the app requests an XMR rate for your selected currency from `rates.nexatrode.com` over HTTPS. Nexatrode can see your IP address, when a rate was requested, and the selected currency. The rate server retrieves market data separately; your device does not contact those providers for price lookups. Wallet amounts, addresses, seeds, and transaction history are not sent. Fiat display is hidden when the rate is older than 30 minutes or unavailable. In I2P-only mode the app does not request fiat rates.

## In-app legal documents

Terms of Use and this Privacy Policy are available offline inside the app. Opening those screens does not contact nexatrode.com. Store listings and the website may still publish the same documents over HTTPS for reviewers and users who are not in the app.

## What we do not collect

The nexawal authors do not collect names, emails, contacts, seed phrases, balances, or transaction history from the app.

If you open external links (for example source on GitHub, or a block explorer), those sites have their own policies.

## Changes

Material changes will be reflected in this bundled file and in the app’s About section.
