// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// Hidden runtime feature flag that toggles between the legacy app and
/// the v1 redesign. Long-press the version footer in Profile to flip it.
///
/// Default `false` — the redesign stays opt-in until it ships end-to-end.
/// When the redesign is ready to be the default we'll flip the default
/// here and leave the toggle in place as an "opt out" for one or two
/// releases, then remove it entirely.
///
/// Storage is `@AppStorage("redesignEnabled")` so SwiftUI views observe
/// changes automatically; no NotificationCenter / publisher boilerplate.
///
/// **Usage at the call site:**
/// ```swift
/// @AppStorage(RedesignFlag.key) private var redesignEnabled = false
///
/// var body: some View {
///     if redesignEnabled {
///         NewBooksGrid(library: library)
///     } else {
///         BooksGridView(library: library)
///     }
/// }
/// ```
enum RedesignFlag {
    /// AppStorage key. Use this constant rather than the string literal
    /// so renames are caught by the compiler.
    static let key = "redesignEnabled"
}
