// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation

/// Books the reader wants but does not have.
///
/// The browse surface can already show wishlist entries, because ownership is
/// one of its dimensions. Until now nothing could put one there: the phone
/// could see a wishlist made on the web and had no way to add to it, which is
/// backwards for the client you have with you in a bookshop.
struct WishlistService {
    let client: APIClient

    func list() async throws -> [WishlistEntry] {
        let page: WishlistPage = try await client.get("/api/v1/me/wishlist")
        return page.items
    }

    /// Wanting a book the catalogue already knows about: a volume of a series
    /// nobody holds, or something someone else's library has.
    @discardableResult
    func add(bookId: String, notes: String = "") async throws -> WishlistEntry {
        struct Body: Encodable { let bookId: String; let notes: String }
        return try await client.post("/api/v1/me/wishlist", body: Body(bookId: bookId, notes: notes))
    }

    /// Wanting something the catalogue has never heard of, which is most of
    /// what anyone writes down in a shop.
    @discardableResult
    func add(title: String, authorName: String = "", notes: String = "") async throws -> WishlistEntry {
        struct Body: Encodable { let title: String; let authorName: String; let notes: String }
        return try await client.post(
            "/api/v1/me/wishlist",
            body: Body(title: title, authorName: authorName, notes: notes)
        )
    }

    func remove(entryId: String) async throws {
        try await client.delete("/api/v1/me/wishlist/\(entryId)")
    }
}

struct WishlistPage: Decodable {
    let items: [WishlistEntry]

    enum CodingKeys: String, CodingKey { case items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([WishlistEntry].self, forKey: .items) ?? []
    }
}

struct WishlistEntry: Decodable, Identifiable, Hashable {
    let id: String
    /// Null for a want typed by hand. A wish does not have to be a catalogue
    /// row, and refusing to record one that is not would rule out the case the
    /// feature exists for.
    let bookId: String?
    let title: String
    let authorName: String
    let notes: String
    let priority: Int

    enum CodingKeys: String, CodingKey {
        case id, bookId, title, authorName, notes, priority
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        bookId = try c.decodeIfPresent(String.self, forKey: .bookId)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        authorName = try c.decodeIfPresent(String.self, forKey: .authorName) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
    }
}
