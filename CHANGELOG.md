# Changelog

All notable changes to **librarium-ios** are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Versioning

This project uses **`YY.MM.revision`** (e.g. `26.4.0`, `26.4.1`):

- `YY` — two-digit release year.
- `MM` — release month, *not* zero-padded.
- `revision` — feature counter within the month, starting at `0`. Resets to `0` when the month rolls over.
- `-dev` suffix marks local unshipped builds; never released.

Release notes before this file started are available in the [GitHub Releases](https://github.com/FireBall1725/librarium-ios/releases) page.

## [26.4.3] — Primary server

When more than one server is connected, the app no longer silently picks an arbitrary one for the welcome banner and quick-scan metadata lookups — the user now chooses.

### Added

- "Primary server" concept — one connected server marked as the home identity. Used for the splash "Welcome, {user}" banner and for ISBN quick-scan metadata lookups so the result doesn't drift based on which library happens to be open.
- Star indicator next to the primary server in **Manage Servers**.
- Leading swipe action on any non-primary row to mark it primary.
- "Make primary server" button on the server's detail screen (shows "Primary server" when already chosen).
- Automatic promotion: the first server added is set as primary. On upgrade, installs with existing servers get the current first entry promoted so behaviour is explicit from launch.

### Changed

- Splash welcome (`ContentView`) and quick-scan metadata client (`ISBNResultSheet`) now read from the primary server. Per-library ownership checks and library-scoped writes continue to use that library's own server.
