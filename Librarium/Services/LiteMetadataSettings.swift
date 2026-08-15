// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation

/// On/off state for each Lite metadata provider.
///
/// Only a boolean per provider lives here. Credentials stay in the
/// Keychain, so turning a source off never discards the key that took
/// effort to get.
enum LiteMetadataSettings {
    /// Open Library is on out of the box: it is keyless, anonymous, and
    /// without it a fresh Lite install has no way to fill in a book's
    /// details at all. Everything else is opt-in.
    private static let defaults: [String: Bool] = [
        "openlibrary": true,
        "hardcover": false
    ]

    private static func key(_ providerID: String) -> String {
        "lite.metadata.\(providerID).enabled"
    }

    static func isEnabled(providerID: String) -> Bool {
        // `object(forKey:)` rather than `bool(forKey:)`: an absent value
        // has to fall through to the per-provider default, and
        // `bool(forKey:)` reports a missing key as false.
        if let stored = UserDefaults.standard.object(forKey: key(providerID)) as? Bool {
            return stored
        }
        return defaults[providerID] ?? false
    }

    static func setEnabled(_ enabled: Bool, providerID: String) {
        UserDefaults.standard.set(enabled, forKey: key(providerID))
    }

    /// Every provider the app knows about, **in priority order**.
    ///
    /// Hardcover first: it is opt-in, so having it on is an explicit
    /// choice, and it carries descriptions, genres and series data that
    /// Open Library usually lacks. The merge takes the first non-empty
    /// value per field, so Hardcover wins any field it can answer and
    /// Open Library fills the rest. With Hardcover off or keyless it
    /// drops out of the list and Open Library answers everything.
    static var allProviders: [LiteMetadataProvider] {
        [HardcoverService(), OpenLibraryService()]
    }

    /// Providers that are switched on and have whatever credentials they
    /// need. Empty means a refresh has nowhere to look.
    static var activeProviders: [LiteMetadataProvider] {
        allProviders.filter(\.isConfigured)
    }

    static var hasActiveProvider: Bool { !activeProviders.isEmpty }
}
