# librarium-ios

Native iOS client for Librarium — a self-hosted personal library tracker. Built with Swift and SwiftUI.

## Requirements

| Tool | Minimum version |
|------|----------------|
| Xcode | 16.0 |
| iOS deployment target | 26.0 |
| macOS (for development) | 15.0 (Sequoia) |
| Apple Developer account | Required to run on a physical device |

## Features

- Browse and search your Librarium libraries across multiple servers
- View book details, editions, and series
- Track reading status, ratings, and notes per edition
- Manage loans and shelves
- Barcode scanner for quick ISBN lookup and library matching
- Multi-server / multi-account support
- Offline mode with per-library caching
- Dark mode

## TestFlight

The iOS app is in public beta on TestFlight. To try it without building from source:

1. Install **[TestFlight](https://apps.apple.com/app/testflight/id899247664)** from the App Store (if you don't already have it).
2. Open the invite link on your iPhone: **[testflight.apple.com/join/dA3sMnqR](https://testflight.apple.com/join/dA3sMnqR)**.
3. Tap **Accept**, then **Install** — the app appears on your home screen.

You'll still need a running [librarium-api](https://github.com/fireball1725/librarium-api) instance to point it at.

Beta builds expire 90 days after upload; TestFlight will prompt you to update when a newer build is available.

## Getting Started

### 1. Clone or download

```bash
git clone https://github.com/fireball1725/librarium-ios.git
cd librarium-ios
```

### 2. Open in Xcode

Open `Librarium.xcodeproj` in Xcode (at the repo root — no nested folders).

### 3. Select a scheme and destination

- Scheme: **Librarium**
- Destination: any iOS 26+ simulator or a connected device

### 4. Build and run

Press **⌘R** or choose **Product → Run**.

You will be prompted to enter a server URL on first launch. Point it at a running [librarium-api](https://github.com/fireball1725/librarium-api) instance.

## Project Structure

```
Librarium.xcodeproj     # Xcode project
Librarium/              # All app source
├── LibrariumApp.swift  # App entry point
├── AppState.swift      # Top-level observable state (accounts, auth)
├── ContentView.swift   # Root navigation view
├── Models/             # Codable structs mirroring API responses
├── Services/           # API client, auth, offline store, keychain
└── Views/
    ├── Admin/          # Admin and settings screens
    ├── Books/          # Book list, detail, barcode scanner, bulk edit
    ├── Components/     # Reusable UI components (TagPill, EmptyState…)
    ├── Loans/          # Loan management
    ├── Members/        # Library member views
    ├── Series/         # Series browsing and detail
    └── Shelves/        # Shelf views
```

## Versioning

Format: **`YY.MM.revision`** (e.g. `26.4.0`).

- `YY` — two-digit release year.
- `MM` — release month, *not* zero-padded (`26.4`, not `26.04`).
- `revision` — feature counter within the month, starting at `0`. Resets to `0` when the month rolls over.
- `-dev` suffix — local/Debug builds only. Release builds drop the suffix since the App Store requires strictly numeric `MARKETING_VERSION`.

Release history in [CHANGELOG.md](./CHANGELOG.md).

## Builds

### Local (Debug)

Run via Xcode. Debug builds use an orange app icon and display as **Librarium Dev** on the home screen so they're visually distinct from TestFlight builds. Debug `MARKETING_VERSION` carries the `-dev` suffix (e.g. `26.4.1-dev`); Release strips it (`26.4.0`) since the App Store rejects non-numeric version components.

### TestFlight (CI)

Pushes to `main` automatically trigger a GitHub Actions workflow that archives, signs, and uploads to TestFlight. The build number is set to the short git commit hash (e.g. `26.4.0 (a3f9c1)`), making every build traceable to an exact commit.

### Releasing

The `release` GitHub Actions workflow (`workflow_dispatch`) computes the next `YY.MM.revision` from the latest tag, updates `MARKETING_VERSION` for both Debug and Release configs, commits `release: <version>`, tags `v<version>`, then bumps Debug back to the next `-dev` revision. TestFlight upload is handled separately by the existing `testflight.yml` workflow.

Required repository secrets:

| Secret | Description |
|--------|-------------|
| `CERTIFICATE_BASE64` | Apple Distribution certificate exported as a base64-encoded `.p12` |
| `CERTIFICATE_PASSWORD` | Password for the `.p12` |
| `KEYCHAIN_PASSWORD` | Any string — used to lock the temporary CI keychain |
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | App Store Connect API issuer ID |
| `ASC_PRIVATE_KEY` | Contents of the `.p8` private key file |

### App Icon

To regenerate the app icons (production navy and debug orange):

```bash
bash generate-icon.sh
```

Outputs `AppIcon-1024.png`, `AppIcon-Debug-1024.png`, and `AppIcon-transparent.png` (for web/marketing use) into the repo root.

## Configuration

The app connects to a self-hosted [librarium-api](https://github.com/fireball1725/librarium-api) server. No cloud service is required. Server URLs and credentials are stored in the iOS Keychain. Multiple servers can be added and all their libraries are shown together.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). PRs must sign off on the [Developer Certificate of Origin](DCO) (`git commit -s`) — a CI check enforces this.

## License

AGPL-3.0-only. See [LICENSE](LICENSE) for the full text.
