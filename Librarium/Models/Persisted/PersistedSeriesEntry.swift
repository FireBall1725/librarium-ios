// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation
import SwiftData

/// On-device cache for series-volume membership. Populated on each
/// online visit to the series-detail screen — once visited, the series
/// renders the same offline. Keyed on the composite series+book id so
/// updates idempotently overwrite previous positions.
@Model
final class PersistedSeriesEntry {
    @Attribute(.unique) var id: String

    var serverAccountID: UUID
    var serverURL: String = ""
    var libraryId: String
    var seriesId: String
    var bookId: String

    var position: Double
    /// Arc id this entry belongs to, or nil for "no arc".
    var arcId: String?
    var updatedAt: Date

    init(
        id: String,
        serverAccountID: UUID,
        libraryId: String,
        seriesId: String,
        bookId: String,
        position: Double,
        arcId: String?,
        updatedAt: Date
    ) {
        self.id = id
        self.serverAccountID = serverAccountID
        let firstPipe = id.firstIndex(of: "|")
        self.serverURL = firstPipe.map { String(id[..<$0]) } ?? ""
        self.libraryId = libraryId
        self.seriesId = seriesId
        self.bookId = bookId
        self.position = position
        self.arcId = arcId
        self.updatedAt = updatedAt
    }

    static func compositeID(serverURL: String, libraryId: String, seriesId: String, bookId: String) -> String {
        "\(serverURL)|\(libraryId)|\(seriesId)|\(bookId)"
    }
}
