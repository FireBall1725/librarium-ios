// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation
import SwiftData

/// One row per book holding the list of shelves the book belongs to.
/// Same pattern as PersistedBookEditions — list-shaped api response,
/// cached as a JSON blob for round-trip fidelity.
@Model
final class PersistedBookShelves {
    @Attribute(.unique) var id: String

    var serverAccountID: UUID
    var serverURL: String = ""
    var libraryId: String
    var bookId: String

    var updatedAt: Date
    var payload: Data

    init(id: String, serverAccountID: UUID, libraryId: String, bookId: String, updatedAt: Date, payload: Data) {
        self.id = id
        self.serverAccountID = serverAccountID
        let firstPipe = id.firstIndex(of: "|")
        self.serverURL = firstPipe.map { String(id[..<$0]) } ?? ""
        self.libraryId = libraryId
        self.bookId = bookId
        self.updatedAt = updatedAt
        self.payload = payload
    }

    static func compositeID(serverURL: String, libraryId: String, bookId: String) -> String {
        "\(serverURL)|\(libraryId)|\(bookId)"
    }
}
