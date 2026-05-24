// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation
import SwiftData

/// One row per arc — the named sub-grouping a series volume belongs
/// to. Series detail's "Wano Country Saga" / "Skypiea Arc" labels read
/// from these rows when offline. Sorted by position when fetched.
@Model
final class PersistedSeriesArc {
    @Attribute(.unique) var id: String

    var serverAccountID: UUID
    var serverURL: String = ""
    var libraryId: String
    var seriesId: String
    var arcId: String

    var position: Double
    var updatedAt: Date
    /// Full SeriesArc payload as JSON for round-trip fidelity.
    var payload: Data

    init(id: String, serverAccountID: UUID, libraryId: String, seriesId: String, arcId: String, position: Double, updatedAt: Date, payload: Data) {
        self.id = id
        self.serverAccountID = serverAccountID
        let firstPipe = id.firstIndex(of: "|")
        self.serverURL = firstPipe.map { String(id[..<$0]) } ?? ""
        self.libraryId = libraryId
        self.seriesId = seriesId
        self.arcId = arcId
        self.position = position
        self.updatedAt = updatedAt
        self.payload = payload
    }

    static func compositeID(serverURL: String, libraryId: String, seriesId: String, arcId: String) -> String {
        "\(serverURL)|\(libraryId)|\(seriesId)|\(arcId)"
    }
}
