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
