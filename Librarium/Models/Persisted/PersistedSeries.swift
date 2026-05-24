// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation
import SwiftData

/// SwiftData mirror of one Series row. Same pattern as PersistedBook —
/// the full Series payload lives as JSON for round-trip fidelity, with
/// a handful of denormalised columns for sorting and predicate scoping
/// without decoding every row.
@Model
final class PersistedSeries {
    @Attribute(.unique) var id: String

    var serverAccountID: UUID
    var serverURL: String = ""
    var libraryId: String
    var seriesId: String

    var name: String
    /// Natural-sort key (articles stripped, digits padded) so series sort
    /// the same offline as the api would. Defaults to "" so existing
    /// rows survive the lightweight migration; backfilled lazily on read.
    var sortName: String = ""
    var bookCount: Int

    var updatedAt: Date

    /// Full Series payload as JSON. The series list and series-detail
    /// views decode from this when they need fields beyond the columns.
    var payload: Data

    init(
        id: String,
        serverAccountID: UUID,
        libraryId: String,
        seriesId: String,
        name: String,
        bookCount: Int,
        updatedAt: Date,
        payload: Data
    ) {
        self.id = id
        self.serverAccountID = serverAccountID
        let firstPipe = id.firstIndex(of: "|")
        self.serverURL = firstPipe.map { String(id[..<$0]) } ?? ""
        self.libraryId = libraryId
        self.seriesId = seriesId
        self.name = name
        self.sortName = name.librariumSortKey()
        self.bookCount = bookCount
        self.updatedAt = updatedAt
        self.payload = payload
    }

    /// Composite key. Server URL is part of the identity for the same
    /// reason PersistedBook needs it — cloned databases on two servers.
    static func compositeID(serverURL: String, libraryId: String, seriesId: String) -> String {
        "\(serverURL)|\(libraryId)|\(seriesId)"
    }
}
