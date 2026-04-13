# librarium-ios

Native iOS client for Librarium — a self-hosted personal library tracker. Built with Swift and SwiftUI.

## Requirements

| Tool | Minimum version |
|------|----------------|
| Xcode | 16.0 |
| iOS deployment target | 17.0 |
| macOS (for development) | 14.0 (Sonoma) |
| Apple Developer account | Required to run on a physical device |

## Features

- Browse and search your Librarium libraries
- View book details, editions, and series
- Track reading status, ratings, and notes per edition
- Manage loans and shelves
- Barcode scanner for quick ISBN lookup
- Multi-server / multi-account support
- Dark mode

## Getting Started

### 1. Clone or download

```bash
git clone https://github.com/fireball1725/librarium-ios.git
cd librarium-ios
```

### 2. Open in Xcode

Open `Librarium/Librarium.xcodeproj` in Xcode.

> **Note:** This project uses a standard `.xcodeproj`. Do not regenerate it from the command line — use Xcode for all project configuration changes.

### 3. Select a scheme and destination

- Scheme: **Librarium**
- Destination: any iOS 17+ simulator or a connected device

### 4. Build and run

Press **⌘R** or choose **Product → Run**.

You will be prompted to enter a server URL on first launch. Point it at a running [librarium-api](https://github.com/fireball1725/librarium-api) instance.

## Project Structure

```
Librarium/Librarium/
├── LibrariumApp.swift      # App entry point and dependency injection
├── AppState.swift          # Top-level observable state
├── ContentView.swift       # Root navigation view
├── Models/                 # Codable structs mirroring API responses
├── Services/               # URLSession-based API client and auth
└── Views/
    ├── Admin/              # Admin and settings screens
    ├── Books/              # Book detail, edition cards, barcode scanner
    ├── Components/         # Reusable UI components
    ├── Loans/              # Loan management
    ├── Members/            # Library member views
    ├── Series/             # Series browsing and detail
    └── Shelves/            # Shelf views
```

## Configuration

The app connects to a self-hosted [librarium-api](https://github.com/fireball1725/librarium-api) server. No cloud service is required. Server URL and credentials are stored in the iOS Keychain.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines and the pull request process.

## License

AGPL-3.0-only. See [LICENSE](LICENSE) for the full terms, including the Contributor License Agreement.
