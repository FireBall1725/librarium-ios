# AGENTS.md

Guidance for AI coding agents working in `librarium-ios`. Humans should read
[CONTRIBUTING.md](./CONTRIBUTING.md) first; this file assumes you have and does
not repeat it.

## What this repo is

The iOS client for Librarium: a self-hosted, privacy-focused tracker for
physical book, manga, and comic collections. It ships in two shapes from one
codebase, self-hosted and Lite, and it is the only client with a barcode
scanner.

Librarium is five repos that ship independently:

| Repo | Role |
| --- | --- |
| [`librarium`](https://github.com/FireBall1725/librarium) | Marketing site at librarium.press |
| [`librarium-api`](https://github.com/FireBall1725/librarium-api) | Go backend, the contract this app consumes |
| [`librarium-web`](https://github.com/FireBall1725/librarium-web) | React client |
| **`librarium-ios`** | **This repo. Swift, SwiftUI, iOS 26+** |
| [`librarium-mcp`](https://github.com/FireBall1725/librarium-mcp) | MCP server |

## Product rules that shape design decisions

- **Two editions, one codebase, both free.** Self-hosted talks to a Librarium
  server. Lite keeps everything on device with SwiftData and iCloud sync, and
  can opt into server sync later. They share a data model on purpose, so a user
  can move between them. There is no paid tier.
- **The API owns the logic.** In self-hosted mode the server computes; the app
  renders. Do not reimplement server-side filtering or ranking in Swift.
- **Multi-server.** One install can hold several accounts across several
  Librarium instances, each with its own offline cache and re-auth state. One
  server is marked primary and drives global lookups such as an ISBN scan.
  Anything keyed on "the server" needs the account in the key.
- **Offline is a real state, not an error.** The app has a per-server cache and
  a pending-operation queue. A screen that only works online is unfinished.
- **Telemetry is opt-in and off by default.**

## Stack

Swift and SwiftUI, iOS 26 minimum, built with Xcode 26.4. SwiftData for local
persistence, Keychain for credentials, `xcodebuild` for CI. No third-party
dependency manager in the main app target.

## Layout

```
Librarium/
  LibrariumApp.swift        entry point
  AppState.swift            accounts, active server, session state
  ContentView.swift         root switch between shells
  Redesigned/               the current UI. Shell, home, books, detail, profile
  Views/                    older screens plus areas not yet redesigned:
                              Scan/       barcode scanning
                              Books/      book screens
                              Loans/      lending
                              Admin/      instance administration
                              Components/ shared views
  Models/                   API-facing types
    Persisted/              SwiftData models and the pending-sync queue
  Services/                 APIClient, per-domain services, caches, Keychain
  Resources/                assets and localisation
LibrariumTests/             XCTest targets
scripts/                    build and release helpers
```

`Redesigned/` is not an experiment; it is the shipping UI. New screens go there
unless you are fixing something in a view that still lives under `Views/`.

## Build and test

Open `Librarium.xcodeproj` and run the `Librarium` scheme, or from the command
line, matching CI:

```bash
xcodebuild \
  -project Librarium.xcodeproj \
  -scheme Librarium \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild test \
  -project Librarium.xcodeproj \
  -scheme Librarium \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest' \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO
```

CI runs on `macos-26` with Xcode 26.4 selected explicitly. It builds Debug for
the simulator and runs `LibrariumTests` on an iPhone 17 Pro Max.

Test coverage is thin and concentrated on logic that is painful to verify by
hand, such as URL normalisation and library ordering. Adding a test for the
behaviour you changed is welcome; wiring up a UI test harness is a bigger
conversation, so raise it in an issue first.

## Things that will bite you

- **Never hand-edit `MARKETING_VERSION` in `project.pbxproj`.** The release
  workflow rewrites it, commits, tags, then bumps Debug back. A version change
  in a feature diff will be asked out of the PR.
- **Never edit `CHANGELOG.md`.** Release notes are generated from PR titles.
- **`project.pbxproj` conflicts are ugly.** Adding files reorders it. Keep file
  additions in their own commit where you can, and rebase rather than merge.
- **A cover write path with no sheet writes nothing.** Flows that hand back a
  captured image need the presenting view to actually present something; this
  has silently dropped covers before.
- **Anything cached needs the server identity in its key.** A cache keyed on
  book id alone will show one account's data under another.
- **Do not put secrets in `UserDefaults`.** Tokens go in the Keychain through
  `KeychainService`.

## Conventions

- Every file starts with the SPDX header and copyright line already used
  throughout the repo. Copy the form from a neighbouring file.
- SwiftUI views stay declarative; work belongs in a service or a view model,
  not in `body`.
- Services are one responsibility each and are injected, not constructed inside
  a view.
- Comments explain why. Match the rationale-comment density of the file you are
  editing.
- Commit messages are short and imperative with a scope:
  `fix(scan): present the cover sheet after capture`.
- Every commit needs a DCO sign-off (`git commit -s`). The DCO check reports on
  this repo, so keep the trailer on every commit.
