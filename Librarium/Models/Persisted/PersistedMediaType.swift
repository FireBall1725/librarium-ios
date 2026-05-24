// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation
import SwiftData

/// Media types are server-wide (not per-library), so the composite id
/// is `serverURL|mediaTypeId`. Powers offline media-type filter chips
/// and offline book detail when it needs to resolve a book's
/// `mediaTypeId` to a display name.
@Model
final class PersistedMediaType {
    @Attribute(.unique) var id: String

    var serverAccountID: UUID
    var serverURL: String = ""
    var mediaTypeId: String

    var name: String
    var displayName: String
    var updatedAt: Date
    var payload: Data

    init(id: String, serverAccountID: UUID, mediaTypeId: String, name: String, displayName: String, updatedAt: Date, payload: Data) {
        self.id = id
        self.serverAccountID = serverAccountID
        let firstPipe = id.firstIndex(of: "|")
        self.serverURL = firstPipe.map { String(id[..<$0]) } ?? ""
        self.mediaTypeId = mediaTypeId
        self.name = name
        self.displayName = displayName
        self.updatedAt = updatedAt
        self.payload = payload
    }

    static func compositeID(serverURL: String, mediaTypeId: String) -> String {
        "\(serverURL)|\(mediaTypeId)"
    }
}
