# Contributing to librarium-ios

Thank you for your interest in contributing to the Librarium iOS client.

## License and commit sign-off (DCO)

The project is licensed under the **GNU Affero General Public License v3.0 only** ([LICENSE](LICENSE)). Contributions are accepted under the same license.

Every commit in a pull request must carry a `Signed-off-by:` trailer certifying the [Developer Certificate of Origin 1.1](DCO). Sign off by passing `-s` to `git commit`:

```bash
git commit -s -m "feat(books): sort by last-read date"
```

If you forget: `git commit --amend -s --no-edit` for one commit, or `git rebase --signoff main` for a whole branch. The [DCO GitHub App](https://github.com/apps/dco) runs on every PR and blocks the merge if any commit is missing a sign-off.

## Requirements

- Xcode 16.0 or later
- macOS 14.0 (Sonoma) or later
- An iOS 17+ simulator or physical device for testing
- An Apple Developer account if running on a physical device

## Setting Up

1. Fork the repository and clone your fork.
2. Open `Librarium/Librarium.xcodeproj` in Xcode.
3. Select the **Librarium** scheme and an iOS 17+ simulator.
4. Press **⌘R** to build and run.

### Signing for your own builds

The project has the maintainer's Apple Developer Team ID (`DEVELOPMENT_TEAM`) committed so the TestFlight CI pipeline works. If you want to build and run on a **physical device** from your fork, change `DEVELOPMENT_TEAM` in **Signing & Capabilities** → **Team** to your own team, or edit it in `Librarium.xcodeproj/project.pbxproj`. Don't commit that change back in a PR — leave it as a local-only edit. Simulator builds don't require a team and work unchanged.

You will need a running [librarium-api](https://github.com/fireball1725/librarium-api) instance to test against. The easiest way is to run the API locally via Docker:

```bash
# from the librarium-api directory
docker compose up
```

Then enter `http://localhost:8080` as the server URL in the app.

## Code Style

- Follow the [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/).
- Use SwiftUI for all new UI. UIKit wrappers are acceptable only when SwiftUI cannot do the job.
- Keep views focused — extract sub-views and view models when a file grows beyond ~200 lines.
- Use `@Observable` (Swift 5.9 macro) for view models, not `ObservableObject`.
- Avoid force unwraps (`!`). Use `guard`, `if let`, or `??` instead.
- All new Swift files should begin with the SPDX license header:

```swift
// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 fireball1725
```

## Project Structure

| Directory | Purpose |
|-----------|---------|
| `Models/` | Codable structs mirroring API JSON responses |
| `Services/` | API client, auth, and Keychain helpers |
| `Views/` | SwiftUI views, grouped by feature area |
| `Views/Components/` | Reusable, feature-agnostic UI components |

## Making Changes

1. Create a branch from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```
2. Keep commits focused. One logical change per commit.
3. Test on at least one simulator before opening a PR.
4. If your change touches the API client or models, verify against a live `librarium-api` instance.

## Pull Requests

- Fill out the pull request template completely.
- Link any related issues with `Closes #123` or `Fixes #123`.
- Screenshots or screen recordings are encouraged for UI changes.
- PRs that break the build or introduce force unwraps will be asked to revise.

The maintainer reviews PRs as time allows. Inclusion is not guaranteed.

## Reporting Bugs

Use the **Bug report** issue template on GitHub. Include:
- iOS version and device or simulator model
- Xcode version used to build
- Exact steps to reproduce
- What you expected vs. what happened
- Relevant console output or crash logs if available
