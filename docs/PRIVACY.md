# NexaWal privacy policy

Last updated: 4 August 2026

NexaWal is a local Monero wallet. This policy covers the iOS app published from [cacaosteve/nexawal](https://github.com/cacaosteve/nexawal).

## What stays on your device

- Your seed, spend/view keys, and wallet cache stay on the device.
- Optional Face ID / Touch ID is handled by the system; we do not receive biometric data.
- Settings (node URL, UI theme, scan lookahead, biometric lock preference) are stored locally.

We do not operate an account system, and we do not ship third-party analytics or crash reporters.

## Network

The app talks to the Monero daemon RPC you configure. Fresh installs default to `https://rpc.nexatrode.com`.

A remote node can typically see:

- your IP address
- when you sync and broadcast
- which outputs the wallet queries while scanning

It does not receive your seed. For stronger privacy, point the app at a node you run.

I2P / hybrid mode, when enabled, routes the configured traffic through your local I2P HTTP proxy instead of (or in addition to) clearnet.

## What we do not collect

The NexaWal authors do not collect names, emails, contacts, seed phrases, balances, or transaction history from the app.

If you open in-app links (privacy policy, source, a block explorer), those sites have their own policies.

## Changes

Material changes will be reflected in this file and in the app’s About section.
