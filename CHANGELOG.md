# Changelog

Notable changes to Notchling, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Logging through Apple's unified log, so problems can be diagnosed from Console.app or `log stream`.
- VoiceOver labels on the icon-only buttons and the wing widgets.
- `CONTRIBUTING.md`, `SECURITY.md`, this changelog, and issue and pull request templates.

## [0.1.1] - 2026-11-08

### Added

- A demo GIF and screenshot in the README, rendered from the real views (`make demo`).

### Fixed

- The approval card now shows the exact command or file Claude Code is asking about, not its description of it.
- The demo tool builds on Xcode 16.

## [0.1.0] - 2026-11-08

First public release.

### Added

- A panel that drops down from the MacBook notch, with widgets on either side of it.
- Widgets: now playing, reminders, calendar, weather, focus timer, world clock, countdown, notes, battery, date and time.
- A layout editor: choose which widgets show, drag them, stack them in columns, swap them and resize them.
- Spotify: sign in once (OAuth 2.0 with PKCE, token kept in the Keychain), search for songs, loop, and play whole albums.
- Claude Code: see what each session is doing, and answer permission prompts from the notch.
- The `notch` command, which shows the progress and result of terminal commands in the notch.
- Unit tests, SwiftLint in strict mode, CI, and a release workflow that publishes a zip and its checksum.

[Unreleased]: https://github.com/jazlynn-choy/Notchling/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/jazlynn-choy/Notchling/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/jazlynn-choy/Notchling/releases/tag/v0.1.0
