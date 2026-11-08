# Notchling

A macOS menu-bar companion that turns the dead space around the MacBook camera notch into something useful.

- **Collapsed:** slim black "wings" extend the notch and show what's playing (or the date), your open reminders count, the time, and battery.
- **Hover the notch:** a panel drops down with music controls and your **Apple Reminders**, synced both ways: add or tick off a reminder here and it updates on your iPhone.
- **Everything is adjustable** in Settings: wing width (down to zero), panel size, what each side shows, which Reminders list, haptics, and open at login.

<!-- TODO: add a screenshot or GIF here — docs/demo.gif -->

## Requirements

- macOS 14 Sonoma or later. Best on a MacBook with a notch; other displays get a virtual one.
- Swift 6 toolchain (Xcode 16+, or the Command Line Tools)

## Build and run

```bash
make run      # release build → build/Notchling.app, then launch it
make test     # unit tests
make lint     # SwiftLint (needs `brew install swiftlint`)
```

On first use, macOS asks for permission to access Reminders and to control Music/Spotify.

## Project layout

```
Sources/
  NotchlingCore/   Models, layout math, state stores, and protocols over system services
    Models/        Todo, Track, NotchGeometry, due-date formatting
    Providers/     Protocols + EventKit, AppleScript, IOKit and SMAppService implementations
    Stores/        @MainActor ObservableObjects the UI binds to
  NotchlingUI/     SwiftUI views, one component per file
  Notchling/       App entry point, the floating panel, hover tracking, dependency wiring
Tests/
  NotchlingCoreTests/  Swift Testing suites with in-memory fakes
scripts/           bundle.sh (make the .app), test.sh
```

The architecture, and why it's built this way, is written up in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Testing

The core module is covered by 39 unit tests: layout geometry, date labels, sorting, AppleScript/IOKit parsing, settings persistence, and the reminders sync behaviour. The sync tests run against `FakeRemindersProvider`, so they need no permissions and touch none of your real data.

```bash
make test
```

## Roadmap

- [ ] Screenshot / demo GIF in this README
- [ ] Developer ID signing, notarization and a `.dmg` release in CI
- [ ] Auto-updates (Sparkle)
- [ ] Multiple displays: follow the active screen
- [ ] Hide automatically over full-screen video
- [ ] Snapshot tests for the SwiftUI views
