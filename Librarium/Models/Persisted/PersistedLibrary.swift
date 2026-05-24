// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation
import SwiftData

/// Local-only library record for Lite-mode accounts. The server-backed flow
/// stores libraries on the api side and never touches SwiftData; Lite mode
/// uses this as the canonical store with no remote mirror.
///
/// The shape intentionally mirrors `Library` (the api DTO) so we can hand
/// the libraries-grid the same struct shape regardless of backing. When a
/// Lite library is promoted to a self-hosted server, we replay these rows
/// through `POST /libraries` and let the api assign canonical ids.
@Model
final class PersistedLibrary {
    @Attribute(.unique) var id: UUID
    /// `ServerAccount.id` of the local account that owns this library.
    var serverAccountID: UUID
    var name: String
    /// `description` collides with `CustomStringConvertible.description`, so
    /// the SwiftData field name is prefixed to avoid the silent override.
    var libraryDescription: String
    var isPublic: Bool
    var createdAt: Date
    var updatedAt: Date
    /// Soft-delete marker — keeps the row addressable for an eventual
    /// promotion replay even after the user removes the library locally.
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        serverAccountID: UUID,
        name: String,
        libraryDescription: String = "",
        isPublic: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.serverAccountID = serverAccountID
        self.name = name
        self.libraryDescription = libraryDescription
        self.isPublic = isPublic
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.deletedAt = nil
    }

    /// Convert to the `Library` DTO the rest of the iOS app already consumes.
    /// `serverURL` is the synthetic `local://<account-id>` so `clientKey`
    /// stays unique across mixed local + remote installs.
    func toLibrary(serverAccountID: UUID, accountName: String) -> Library {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return Library(
            id: id.uuidString,
            name: name,
            description: libraryDescription,
            slug: PersistedLibrary.slug(from: name),
            ownerId: "local",
            isPublic: isPublic,
            createdAt: iso.string(from: createdAt),
            updatedAt: iso.string(from: updatedAt),
            bookCount: 0,
            readingCount: 0,
            readCount: 0,
            serverURL: ServerAccount.localURL(for: serverAccountID),
            serverName: accountName
        )
    }

    private static func slug(from name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }
}
