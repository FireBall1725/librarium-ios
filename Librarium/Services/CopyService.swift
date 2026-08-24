// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation

/// Reads and edits the physical objects a book exists as.
///
/// Behind a per-server capability check at the call site, like reading state
/// and lists: an instance without copies answers 404, and a screen that reads
/// that as "you own none" is worse than one that does not show the section.
struct CopyService {
    let client: APIClient

    private struct Envelope: Decodable { let items: [Copy] }

    /// Every copy of a work across the libraries the caller can reach.
    ///
    /// Not scoped to one library on purpose: a copy in a shared library is
    /// still a copy of this book, and hiding it would make the same book look
    /// unowned depending on which library page you arrived from.
    func copies(bookId: String) async throws -> [Copy] {
        let envelope: Envelope = try await client.get("/api/v1/books/\(bookId)/copies")
        return envelope.items
    }

    /// Writes one field. The endpoint is a partial update, so the body names
    /// only what changed and leaves the rest of the copy alone.
    @discardableResult
    func update(copyId: String, body: UpdateCopyRequest) async throws -> Copy {
        try await client.patch("/api/v1/copies/\(copyId)", body: body)
    }
}

/// A partial edit of a copy. Every field is optional: an omitted one is left
/// alone, which is what lets two devices change different things without
/// either losing.
struct UpdateCopyRequest: Encodable {
    var condition: String?
    var isSigned: Bool?
    var notes: String?
    var locationId: String?
}
