// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation

/// What the instance thinks the reader should read next.
///
/// Suggestions have been generated on the server for a while and the phone had
/// no way to see them. They are also one of the ownership states the browse
/// surface can filter by, so the shelf could say "30 suggested" with nothing
/// behind the number.
struct SuggestionService {
    let client: APIClient

    /// Undismissed suggestions, newest first. A bare array rather than an items
    /// envelope: this route predates the newer shape and still answers in the
    /// older one.
    func list() async throws -> [Suggestion] {
        try await client.get("/api/v1/me/suggestions")
    }

    /// `new`, `interested`, `dismissed`, or `added_to_library`.
    func setStatus(id: String, status: String) async throws {
        struct Body: Encodable { let status: String }
        let _: Suggestion = try await client.put(
            "/api/v1/me/suggestions/\(id)/status", body: Body(status: status))
    }

    /// Stops this book being suggested again, rather than only clearing it from
    /// the list. Dismissing says "not now"; blocking says "not ever", and
    /// without the second one the same book comes back every run.
    func block(id: String) async throws {
        try await client.postVoid("/api/v1/me/suggestions/\(id)/block")
    }
}

struct Suggestion: Decodable, Identifiable, Hashable {
    let id: String
    let type: String
    let bookId: String?
    let libraryId: String?
    let title: String
    let author: String
    let isbn: String
    let coverUrl: String?
    /// Why this one, in the instance's own words. The whole value of a
    /// suggestion is the sentence next to it; a list of titles with no reasons
    /// is a list anybody could have written.
    let reasoning: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, type, bookId, libraryId, title, author, isbn, coverUrl, reasoning, status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        bookId = try c.decodeIfPresent(String.self, forKey: .bookId)
        libraryId = try c.decodeIfPresent(String.self, forKey: .libraryId)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        isbn = try c.decodeIfPresent(String.self, forKey: .isbn) ?? ""
        coverUrl = try c.decodeIfPresent(String.self, forKey: .coverUrl)
        reasoning = try c.decodeIfPresent(String.self, forKey: .reasoning) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "new"
    }

    /// What the instance was answering when it picked this.
    var kindLabel: String {
        switch type {
        case "read_next":      return "Read next"
        case "buy_next":       return "Worth buying"
        case "similar":        return "Similar to what you have"
        case "complete_series": return "Completes a series"
        default:               return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
