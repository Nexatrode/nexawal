# Node contact status

The sync card distinguishes wallet scan completion from contact with the configured
daemon. Failed checks and observations older than three minutes show a warning and
a connection retry, while retaining the last known balance and history. Successful
contact is an observation, not independent proof of the latest canonical chain.

The sync card reevaluates freshness every 15 seconds and whenever published state
changes. A completed refresh can provide contact evidence; a probe result from a
cancelled request, changed route, locked session, or replaced wallet is ignored.

Run `swift test --package-path Packages/NexaWalLogic` for the injected-time state
regressions. Interactive validation should cover a successful sync followed by an
unavailable daemon, retry and recovery, node changes, and background/foreground.
The wallet's scan progress, balance, and history must remain intact after a failed
probe. This does not independently validate whether a daemon reports an honest tip.

The new node-status strings use localization lookups with English source copy.
Locale review and final iOS 27.1/device validation remain part of the draft PR's QA.
