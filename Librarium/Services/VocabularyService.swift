// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation

/// The controlled lists the server owns: edition formats, contributor roles,
/// copy conditions, identifier schemes, plus the open vocabularies of genres
/// and tags.
///
/// The closed lists are codes only, no display names. A label stored in the
/// database cannot be translated and cannot be corrected without a migration,
/// so the server sends what a thing *is* and the client decides what to call
/// it. Genres and tags are the other kind: rows somebody named, which come
/// back with their names.
struct VocabularyService {
    let client: APIClient

    func editionFormats() async throws -> [VocabularyTerm] {
        let page: VocabularyPage = try await client.get("/api/v1/edition-formats")
        return page.items.filter(\.isActive)
    }

    /// Every genre the instance knows, whether or not a book uses it.
    ///
    /// The facet list answers a different question — what is on the shelf —
    /// and filing a book under a genre nobody owns yet is exactly the case it
    /// cannot cover. Nothing on iOS called this, which is why a scanned book
    /// arrived with no genres however many the metadata sources knew
    /// (librarium-ios-033).
    func genres() async throws -> [Genre] {
        try await client.get("/api/v1/genres")
    }

    /// Tags across every library the caller can read, narrowed by `query`.
    /// A tag with the same name in two libraries comes back twice, marked
    /// ambiguous, because they are two tags.
    func tags(query: String = "") async throws -> [MeTag] {
        guard !query.isEmpty,
              let enc = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return try await client.get("/api/v1/me/tags") }
        return try await client.get("/api/v1/me/tags?q=\(enc)")
    }
}

/// A tag, with the library it belongs to.
struct MeTag: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let libraryId: String
    let libraryName: String
    /// True when another library has a tag by the same name, so a picker knows
    /// to say which library this one is from.
    let ambiguous: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, ambiguous
        case libraryId = "library_id"
        case libraryName = "library_name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        libraryId = try c.decodeIfPresent(String.self, forKey: .libraryId) ?? ""
        libraryName = try c.decodeIfPresent(String.self, forKey: .libraryName) ?? ""
        ambiguous = try c.decodeIfPresent(Bool.self, forKey: .ambiguous) ?? false
    }
}

struct VocabularyPage: Decodable {
    let items: [VocabularyTerm]

    enum CodingKeys: String, CodingKey { case items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([VocabularyTerm].self, forKey: .items) ?? []
    }
}

struct VocabularyTerm: Decodable, Identifiable, Hashable {
    let code: String
    let sortOrder: Int
    let isActive: Bool

    var id: String { code }

    enum CodingKeys: String, CodingKey { case code, sortOrder, isActive }

    init(code: String, sortOrder: Int = 0, isActive: Bool = true) {
        self.code = code
        self.sortOrder = sortOrder
        self.isActive = isActive
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decodeIfPresent(String.self, forKey: .code) ?? ""
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        // Absent means active. A server that does not send the flag is not
        // saying every format is retired.
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
    }
}

/// What a code is called, here.
enum EditionFormatLabels {
    static func label(_ code: String) -> String {
        switch code {
        case "paperback": return "Paperback"
        case "hardcover": return "Hardcover"
        case "ebook":     return "E-book"
        case "audiobook": return "Audiobook"
        case "comic":     return "Comic"
        case "box_set":   return "Box set"
        default:
            return code.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// What to offer before the server has answered, and for a Lite library
    /// that has no server to ask. The four every collection has; the rest
    /// arrive from the server when there is one.
    static let fallback: [VocabularyTerm] = [
        VocabularyTerm(code: "paperback", sortOrder: 10),
        VocabularyTerm(code: "hardcover", sortOrder: 20),
        VocabularyTerm(code: "ebook", sortOrder: 30),
        VocabularyTerm(code: "audiobook", sortOrder: 40),
    ]
}
