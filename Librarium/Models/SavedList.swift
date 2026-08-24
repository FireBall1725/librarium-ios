// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation

/// A named set of books, however that set is decided.
///
/// Shelves and saved views were two features that looked alike and differed
/// only in how membership is settled: enumerated by hand, or computed from a
/// filter. That is a kind, not a second concept.
///
/// This app never had saved views, so the change here is not a merge. It is
/// reach: a shelf is a list shared with a library, so `/me/shelves` returns
/// only those, and every private list a reader made on the web was invisible
/// here.
struct SavedList: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let color: String

    /// `manual` enumerates its books, `smart` computes them from a filter.
    let kind: String

    let visibility: String
    let sharedLibraryId: String?
    let bookCount: Int

    /// Non-empty when this is a list the product ships rather than one someone
    /// made. Keyed on a name rather than the row id, which is minted per
    /// install and would identify nothing on another server.
    let builtinKey: String

    var isSmart: Bool { kind == "smart" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(String.self, forKey: .id)
        name            = try c.decodeIfPresent(String.self, forKey: .name)            ?? ""
        description     = try c.decodeIfPresent(String.self, forKey: .description)     ?? ""
        icon            = try c.decodeIfPresent(String.self, forKey: .icon)            ?? ""
        color           = try c.decodeIfPresent(String.self, forKey: .color)           ?? ""
        kind            = try c.decodeIfPresent(String.self, forKey: .kind)            ?? "manual"
        visibility      = try c.decodeIfPresent(String.self, forKey: .visibility)      ?? "private"
        sharedLibraryId = try c.decodeIfPresent(String.self, forKey: .sharedLibraryId)
        bookCount       = try c.decodeIfPresent(Int.self,    forKey: .bookCount)       ?? 0
        builtinKey      = try c.decodeIfPresent(String.self, forKey: .builtinKey)      ?? ""
    }
}

extension Shelf {
    /// The list shape, for a server that does not have lists yet.
    ///
    /// A shelf is a manual list shared with a library, which is exactly what
    /// the migration turned every existing shelf into, so the older read can
    /// answer the same question with no second code path behind it.
    var asSavedList: SavedList {
        SavedList(
            id: id, name: name, description: description,
            icon: icon, color: color, kind: "manual",
            visibility: "library", sharedLibraryId: libraryId,
            bookCount: bookCount, builtinKey: ""
        )
    }
}

extension SavedList {
    /// Built by hand where a shelf is folded into this shape. Declaring
    /// `init(from:)` above removes the memberwise one Swift would synthesise.
    init(
        id: String, name: String, description: String, icon: String, color: String,
        kind: String, visibility: String, sharedLibraryId: String?,
        bookCount: Int, builtinKey: String
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.color = color
        self.kind = kind
        self.visibility = visibility
        self.sharedLibraryId = sharedLibraryId
        self.bookCount = bookCount
        self.builtinKey = builtinKey
    }
}
