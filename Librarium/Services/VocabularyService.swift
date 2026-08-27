// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation

/// The controlled lists the server owns: edition formats, contributor roles,
/// copy conditions, identifier schemes.
///
/// Codes only, no display names. A label stored in the database cannot be
/// translated and cannot be corrected without a migration, so the server sends
/// what a thing *is* and the client decides what to call it.
struct VocabularyService {
    let client: APIClient

    func editionFormats() async throws -> [VocabularyTerm] {
        let page: VocabularyPage = try await client.get("/api/v1/edition-formats")
        return page.items.filter(\.isActive)
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
