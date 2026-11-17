# Security

Notchling stores a Spotify refresh token in the Keychain, edits `~/.claude/settings.json`, and can
approve Claude Code permission requests. Problems in those areas are taken seriously.

## Reporting a vulnerability

Please do not open a public issue. Report it privately through GitHub:
[Report a vulnerability](https://github.com/jazlynn-choy/Notchling/security/advisories/new).

Include what you found, how to reproduce it, and the Notchling and macOS versions. You should get a
reply within a week.

## Supported versions

Only the [latest release](https://github.com/jazlynn-choy/Notchling/releases/latest) gets fixes.

## What Notchling does with your data

- **Spotify:** the refresh token is kept in the macOS Keychain and sent only to Spotify. The sign-in
  callback listens on `127.0.0.1` only, and only while you are signing in.
- **Claude Code:** the hooks keep the event type, tool name, command or file path, and folder. Prompts
  and file contents are never saved. Approvals are answered only while Notchling is running and the
  option is switched on; otherwise Claude Code asks in the terminal as usual.
- **Calendar, Reminders and notes:** read on your Mac and never sent anywhere.
- **Weather:** your approximate location is sent to Open-Meteo to fetch the forecast.
- **Logs:** written to the macOS unified log on your Mac. They never contain tokens, prompts or the
  text of your notes and reminders.

Notchling has no analytics and no telemetry.
