# Contributing to Notchling

Thanks for wanting to help. Bug reports, ideas and pull requests are all welcome.

## Reporting a bug or suggesting a feature

Open an [issue](https://github.com/jazlynn-choy/Notchling/issues/new/choose) and pick the matching template.
For a security problem, follow [SECURITY.md](SECURITY.md) instead of opening a public issue.

## Setting up

You need macOS 14 or later and a Swift 6 toolchain (Xcode 16+, or the Command Line Tools).

```bash
git clone https://github.com/jazlynn-choy/Notchling.git
cd Notchling
make run      # build build/Notchling.app and launch it
make test     # unit tests
make lint     # SwiftLint in strict mode (brew install swiftlint)
```

## Where things go

| Module | What belongs there |
| --- | --- |
| `NotchlingActivity` | Types shared by the app and the `notch` command. Foundation only. |
| `NotchlingCore` | Models, stores and services. No SwiftUI views. Everything here should be testable. |
| `NotchlingUI` | SwiftUI views. Keep logic out of them; put it in Core. |
| `Notchling` | The app itself: window, wiring and timers. |
| `notch` | The command-line tool. |

[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) explains the design decisions and the reasons behind them.

## Making a change

1. Create a branch from `main`. `main` is protected, so changes go in through pull requests.
2. Make the change. Add or update tests for anything in `NotchlingCore`.
3. Run `make test` and `make lint`. Both must pass; CI runs the same checks.
4. Add a line under **Unreleased** in [CHANGELOG.md](CHANGELOG.md) if users would notice the change.
5. Open a pull request and fill in the template.

## Style

- SwiftLint decides formatting. `make format` fixes what it can.
- Talk to the outside world (network, EventKit, AppleScript, the file system) through a protocol, so tests can use a fake.
- Log with `Log` from `NotchlingCore`. Never log tokens, prompts, file contents or the text of someone's notes and reminders.
- Give every icon-only button an `accessibilityLabel`.
- Write commit messages as a short imperative sentence, such as "Add a countdown widget".
