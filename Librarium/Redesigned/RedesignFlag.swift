// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// Hidden runtime feature flag that toggles between the legacy app and
/// the v1 redesign. Long-press the version footer in Profile to flip it.
///
/// Default `true` — the redesign is now the shipping experience. The
/// toggle stays in place as an opt-out for one or two releases so a
/// user who hits a regression can fall back to the legacy app. After
/// that the flag and the legacy code paths come out entirely.
///
/// Storage is `@AppStorage("redesignEnabled")` so SwiftUI views observe
/// changes automatically; no NotificationCenter / publisher boilerplate.
///
/// **Usage at the call site:**
/// ```swift
/// @AppStorage(RedesignFlag.key) private var redesignEnabled = true
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
