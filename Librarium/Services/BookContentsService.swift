// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation

/// What a book contains, and what contains it.
///
/// An omnibus of volumes one to three is one book on the shelf and three
/// volumes of a run. Ownership resolves through the link, so holding the
/// container counts as holding what is inside it, and the phone had no way to
/// see the link at all: a reader with the three-in-one saw three missing
/// volumes and no explanation.
struct BookContentsService {
    let client: APIClient

    func contents(bookId: String) async throws -> [BookContentLink] {
        let page: BookContentsPage = try await client.get("/api/v1/books/\(bookId)/contents")
        return page.items
    }

    func containers(bookId: String) async throws -> [BookContentLink] {
        let page: BookContentsPage = try await client.get("/api/v1/books/\(bookId)/containers")
        return page.items
    }

    func add(containerId: String, containedId: String, position: Double) async throws {
        struct Body: Encodable { let containedId: String; let position: Double }
        try await client.postVoid("/api/v1/books/\(containerId)/contents",
                                  body: Body(containedId: containedId, position: position))
    }

    func remove(containerId: String, containedId: String) async throws {
        try await client.delete("/api/v1/books/\(containerId)/contents/\(containedId)")
    }
}

struct BookContentsPage: Decodable {
    let items: [BookContentLink]

    enum CodingKeys: String, CodingKey { case items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([BookContentLink].self, forKey: .items) ?? []
    }
}

/// One end of a containment link.
///
/// The list route fills only the far end: asking what a book contains gives
/// `contained_id` and the container is the book you asked about, and asking
/// what contains it gives `container_id` the same way. `otherID` is whichever
/// one is not the book in hand.
struct BookContentLink: Decodable, Identifiable, Hashable {
    let containerId: String
    let containedId: String
    let title: String
    let position: Double

    var id: String { containerId + "/" + containedId }

    enum CodingKeys: String, CodingKey { case containerId, containedId, title, position }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        containerId = try c.decodeIfPresent(String.self, forKey: .containerId) ?? ""
        containedId = try c.decodeIfPresent(String.self, forKey: .containedId) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        position = try c.decodeIfPresent(Double.self, forKey: .position) ?? 0
    }

    func otherID(from bookId: String) -> String {
        containerId == bookId ? containedId : containerId
    }

    /// 3 rather than 3.0, and 4.5 kept, matching every other position on the
    /// series page.
    var positionLabel: String {
        position == position.rounded() ? String(Int(position)) : String(format: "%.1f", position)
    }
}
