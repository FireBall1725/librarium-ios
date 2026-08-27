// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation

/// Resolving a cover path without a `Library` to hand.
///
/// The cross-library grid has a book and the server it came from, not the
/// library object, because a book can sit in several libraries and the grid
/// never had to pick one. The rule is the same either way, so it lives here and
/// `Library` calls it rather than keeping a second copy.
enum CoverURL {
    static func resolve(_ path: String?, serverURL: String) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        return URL(string: serverURL + path)
    }
}

extension Library {
    /// Resolve a book cover's stored `coverUrl` against this library.
    /// Server-emitted covers are relative paths like `/uploads/abc.jpg`
    /// that need joining with `serverURL`; Lite books store absolute
    /// URLs (e.g. Open Library `https://covers.openlibrary.org/...`)
    /// and should pass through unchanged. Returns nil for an empty
    /// path so callers can fall back to the generated jacket.
    func coverURL(for path: String?) -> URL? {
        CoverURL.resolve(path, serverURL: serverURL)
    }
}
