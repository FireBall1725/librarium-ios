// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// The collection tab: books, runs and people behind one segmented control.
///
/// Three rows of the web client's rail, which a phone has no room for. They
/// were a tab, a tab and an overflow item here, so the two the reader uses
/// most were a tab bar apart and the third was three taps down
/// (librarium-ios-001).
///
/// Each surface keeps its own tree alive behind an opacity, the way the shell
/// keeps its tabs: switching segments should return you to the shelf you left,
/// scrolled where you left it, not reload it.
struct RedesignedCollectionView: View {
    /// Set by the shell when the scanner finds a book already on a shelf and
    /// the reader asks to open it.
    var openBookID: Binding<String?> = .constant(nil)
    /// Whether this tab is the one on screen.
    var isActive = true

    @State private var surface: CollectionSurface = .books

    var body: some View {
        ZStack {
            RedesignedBrowseView(
                openBookID: openBookID,
                surface: $surface,
                // The grid loads when the reader can actually see it: on this
                // tab, on this segment. Four tabs' worth of requests at launch
                // was the reason the flag exists.
                isActive: isActive && surface == .books
            )
            .opacity(surface == .books ? 1 : 0)
            .allowsHitTesting(surface == .books)

            RedesignedSeriesListView(surface: $surface, isActive: isActive && surface == .series)
                .opacity(surface == .series ? 1 : 0)
                .allowsHitTesting(surface == .series)

            RedesignedAuthorsView(surface: $surface, isActive: isActive && surface == .authors)
                .opacity(surface == .authors ? 1 : 0)
                .allowsHitTesting(surface == .authors)
        }
    }
}
