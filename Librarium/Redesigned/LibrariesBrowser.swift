// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// The per-library screens, one level down from the collection.
///
/// Library stopped being the way in and became one filter among eleven, but the
/// per-library grid is still where a library is synced for offline reading,
/// where Lite libraries live, and where a book is added. Those are things you
/// do *to* a library rather than questions you ask about a collection, so they
/// keep their own screen rather than being folded into the browse surface.
struct LibrariesBrowser: View {
    @State private var picked: Library?

    var body: some View {
        RedesignedLibrariesView { picked = $0 }
            .navigationDestination(item: $picked) { library in
                RedesignedBooksView(library: library)
                    .environment(\.libraryBack, { picked = nil })
                    // The per-library grid keeps its own state, so a second
                    // library opened after a first would otherwise inherit the
                    // first one's books and a `.task` that never runs again.
                    .id(library.clientKey)
            }
    }
}
