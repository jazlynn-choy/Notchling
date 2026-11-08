# Notchling

A macOS menu-bar companion that turns the dead space around the MacBook camera notch into something useful.

- **Collapsed:** slim black "wings" extend the notch and show what's playing (or the date), your open reminders count, the time, and battery.
- **Hover the notch:** a panel drops down with music controls and your **Apple Reminders**, synced both ways: add or tick off a reminder here and it updates on your iPhone.
- **Pick your widgets.** Choose what goes on the left of the notch, the right, and in the panel, and in what order:
  - **Beside the notch:** now playing, date, time, battery, open reminders, focus timer, next calendar event
  - **In the panel:** music, Reminders, focus timer, Calendar, a Today tile
- **Music:** play/pause/skip, **loop** (song or playlist), and **search your Music library** to play a song. Songs outside your library open in Spotify's search.
- **Focus timer:** 5/15/25/50-minute sessions with a progress ring, a chime when done, and the time left shown beside the notch.
- **Calendar:** your next event ("Standup 12m") beside the notch, and the rest of today in the panel.
- **Everything else is adjustable** in Settings: wing width (down to zero), panel size, which Reminders list, haptics, and open at login.

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

On first use, macOS asks for permission to access Reminders and Calendar and to control Music/Spotify.

### Keep permissions between builds

macOS remembers permissions per app *signature*. Without a certificate, each build gets a new throwaway signature, so macOS treats every rebuild as a new app and asks again. Create a local signing certificate once and `make run` will use it automatically:

1. Open **Keychain Access** → menu **Keychain Access → Certificate Assistant → Create a Certificate…**
2. Name: `Notchling Dev` · Identity Type: **Self Signed Root** · Certificate Type: **Code Signing** → **Create**
3. Run `make run` and grant permissions one last time. They'll stick from then on.

The certificate only lives in your keychain and is only good for apps on your own Mac.

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

The core module is covered by 78 unit tests: layout geometry, the widget layout and its migration, the focus timer, calendar labels, music search, date labels, sorting, AppleScript/IOKit parsing, settings persistence, and the reminders sync behaviour. The sync tests run against `FakeRemindersProvider`, so they need no permissions and touch none of your real data.

```bash
make test
```

## Roadmap

- [ ] Screenshot / demo GIF in this README
- [ ] Developer ID signing, notarization and a `.dmg` release in CI
- [ ] Auto-updates (Sparkle)
- [ ] Play any song (Apple Music catalog via MusicKit, or Spotify Web API with sign-in)
- [ ] Multiple displays: follow the active screen
- [ ] Hide automatically over full-screen video
- [ ] Snapshot tests for the SwiftUI views
