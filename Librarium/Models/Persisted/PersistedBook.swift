// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation
import SwiftData

/// On-device cache row for a single Book payload. Holds enough denormalised
/// columns (title / author / cover / read status) to drive list rendering
/// without a JSON decode per row, plus the full Book payload as Data for
/// detail-view fallback when the server is unreachable.
///
/// We don't try to map every Book field into its own SwiftData column —
/// contributors are nested, editions live on a separate endpoint, and the
/// detail view already knows how to consume a `Book` struct. Storing the
/// payload verbatim lets us round-trip any field the detail view asks for
/// without schema churn the next time the api gains a property.
///
/// The composite identity is "<serverURL>|<libraryId>|<bookId>" so cloned
/// databases (two servers, same book ids) don't collapse into one row.
@Model
final class PersistedBook {
    @Attribute(.unique) var id: String

    /// `ServerAccount.id` that owns this row. Lets the sync layer scope
    /// fetches per account and drop everything on sign-out.
    var serverAccountID: UUID
    /// Server URL the book was fetched from — duplicates the prefix of
    /// `id` as a queryable column. SwiftData's `#Predicate` doesn't
    /// reliably support String prefix operations, so we predicate on
    /// `(serverURL, libraryId)` directly when scoping reads/purges.
    var serverURL: String = ""
    /// The library `id` field as returned by the api — not the `clientKey`.
    var libraryId: String
    var bookId: String

    /// Denormalised columns for the list rendering. Keeping these out of
    /// the payload blob means BooksView can render without decoding 100+
    /// JSON payloads on every visit.
    var title: String
    /// Normalised sort key matching the api's `natural_sort_key()` — strips
    /// leading articles ("The Bad Guys" → "bad guys") and zero-pads embedded
    /// digit sequences so "#2" sorts before "#10". Stored as a column so
    /// the SwiftData fetch can order on it without decoding rows.
    ///
    /// Defaults to "" so SwiftData's lightweight migration can fill the
    /// column on existing rows when this attribute is added; the next
    /// sync rewrites the column with the real key.
    var sortTitle: String = ""
    var subtitle: String
    var coverUrl: String?
    var primaryAuthor: String?
    var readStatus: String?
    var progressPct: Double?
    var rating: Int?
    var isFavorite: Bool
    var updatedAt: Date

    /// Full Book payload encoded as JSON. The detail view decodes from
    /// here when the api round-trip fails so contributors, descriptions,
    /// and any api-only fields stay available offline.
    var payload: Data

    init(
        id: String,
        serverAccountID: UUID,
        libraryId: String,
        bookId: String,
        title: String,
        subtitle: String,
        coverUrl: String?,
        primaryAuthor: String?,
        readStatus: String?,
        progressPct: Double?,
        rating: Int?,
        isFavorite: Bool,
        updatedAt: Date,
        payload: Data
    ) {
        self.id = id
        self.serverAccountID = serverAccountID
        // Recover serverURL from the composite id so existing call sites
        // don't have to plumb it separately.
        let firstPipe = id.firstIndex(of: "|")
        self.serverURL = firstPipe.map { String(id[..<$0]) } ?? ""
        self.libraryId = libraryId
        self.bookId = bookId
        self.title = title
        self.sortTitle = title.librariumSortKey()
        self.subtitle = subtitle
        self.coverUrl = coverUrl
        self.primaryAuthor = primaryAuthor
        self.readStatus = readStatus
        self.progressPct = progressPct
        self.rating = rating
        self.isFavorite = isFavorite
        self.updatedAt = updatedAt
        self.payload = payload
    }

    /// Composite key used as the SwiftData primary key. Server URL is
    /// part of the identity because two Librarium servers can legitimately
    /// expose the same book id (cloned databases).
    static func compositeID(serverURL: String, libraryId: String, bookId: String) -> String {
        "\(serverURL)|\(libraryId)|\(bookId)"
    }
}
