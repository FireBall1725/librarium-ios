// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation

/// Reads the caller's lists.
///
/// Every call is behind a per-server capability check at the call site: one
/// install talks to several instances and they can be on different versions, so
/// a server without lists answers 404 and the caller falls back to shelves,
/// which every version still serves.
struct ListService {
    let client: APIClient

    private struct Envelope: Decodable { let items: [SavedList] }

    /// Every list the caller can see: their own, plus anything shared into a
    /// library they can reach.
    func myLists() async throws -> [SavedList] {
        let envelope: Envelope = try await client.get("/api/v1/me/lists")
        return envelope.items
    }

    /// The caller's saved views for one surface, in the order the server sends
    /// them.
    ///
    /// A view is a smart list: a filter with a name. The manual lists that
    /// share the type are sets of books picked by hand and belong on the book
    /// page, not in a filter control.
    func savedViews(surface: String) async throws -> [SavedList] {
        try await myLists().filter { $0.isSmart && $0.surface == surface }
    }

    /// Saves what is on screen as a view.
    ///
    /// The filter is stored as the same query string the requests carry, so
    /// saving and reopening cannot drift apart the way two spellings of one
    /// filter always eventually do.
    @discardableResult
    func saveView(name: String, surface: String, query: String) async throws -> SavedList {
        struct Body: Encodable {
            let name: String
            let kind = "smart"
            let surface: String
            let filter: SavedListFilter
            let visibility = "private"
        }
        return try await client.post(
            "/api/v1/me/lists",
            body: Body(name: name, surface: surface, filter: SavedListFilter(query: query))
        )
    }

    func deleteView(id: String) async throws {
        try await client.delete("/api/v1/me/lists/\(id)")
    }

    /// Which of the caller's lists hold a book.
    ///
    /// Manual lists only. A smart list's membership is whatever its filter
    /// matches right now, so answering for one would mean the server running
    /// every stored filter to draw a label.
    func listsHolding(bookId: String) async throws -> [SavedList] {
        let envelope: Envelope = try await client.get("/api/v1/books/\(bookId)/lists")
        return envelope.items
    }
}
