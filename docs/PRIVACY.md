# NexaWal privacy policy

Last updated: 5 August 2026

NexaWal is a local Monero wallet. This policy covers the iOS app published from [cacaosteve/nexawal](https://github.com/cacaosteve/nexawal).

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

Optional fiat estimates are off by default. If you turn them on, the app contacts `api.kraken.com` for an XMR price and, when needed, `api.frankfurter.dev` for ECB foreign-exchange rates. Those servers can see your IP address and that a price was requested. Wallet amounts, addresses, and transaction history are not sent. Fiat display is hidden if the rate is older than 30 minutes or the fetch fails. Price lookups use clearnet HTTPS even if the wallet node is set to I2P-only — node proxy settings do not apply to fiat estimates.

## What we do not collect

The NexaWal authors do not collect names, emails, contacts, seed phrases, balances, or transaction history from the app.

If you open in-app links (privacy policy, source, a block explorer), those sites have their own policies.

## Changes

Material changes will be reflected in this file and in the app’s About section.
