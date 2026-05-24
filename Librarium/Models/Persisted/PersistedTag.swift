// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation
import SwiftData

/// One row per library tag. Powers offline filter chips on BooksView.
@Model
final class PersistedTag {
    @Attribute(.unique) var id: String

    var serverAccountID: UUID
    var serverURL: String = ""
    var libraryId: String
    var tagId: String

    var name: String
    var sortName: String = ""
    var color: String
    var updatedAt: Date
    var payload: Data

    init(id: String, serverAccountID: UUID, libraryId: String, tagId: String, name: String, color: String, updatedAt: Date, payload: Data) {
        self.id = id
        self.serverAccountID = serverAccountID
        let firstPipe = id.firstIndex(of: "|")
        self.serverURL = firstPipe.map { String(id[..<$0]) } ?? ""
        self.libraryId = libraryId
        self.tagId = tagId
        self.name = name
        self.sortName = name.librariumSortKey()
        self.color = color
        self.updatedAt = updatedAt
        self.payload = payload
    }

    static func compositeID(serverURL: String, libraryId: String, tagId: String) -> String {
        "\(serverURL)|\(libraryId)|\(tagId)"
    }
}
