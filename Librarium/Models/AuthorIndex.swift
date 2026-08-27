// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation

/// The people behind the collection, across every library.
///
/// There was no authors surface on the phone at all. A contributor could be
/// reached only by opening a book they wrote, which answers "who wrote this"
/// and never "what else do I have of theirs".

struct AuthorIndexEntry: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let sortName: String
    let photoUrl: String?
    let bookCount: Int
    let readCount: Int
    let spines: [AuthorSpine]
    let libraries: [AuthorLibraryRef]

    enum CodingKeys: String, CodingKey {
        case id, name, sortName, photoUrl, bookCount, readCount, spines, libraries, letter
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        sortName = try c.decodeIfPresent(String.self, forKey: .sortName) ?? ""
        photoUrl = try c.decodeIfPresent(String.self, forKey: .photoUrl)
        bookCount = try c.decodeIfPresent(Int.self, forKey: .bookCount) ?? 0
        readCount = try c.decodeIfPresent(Int.self, forKey: .readCount) ?? 0
        spines = try c.decodeIfPresent([AuthorSpine].self, forKey: .spines) ?? []
        libraries = try c.decodeIfPresent([AuthorLibraryRef].self, forKey: .libraries) ?? []
    }
}

/// A book's cover, pre-addressed by the server so no client has to know how a
/// cover path is spelled.
struct AuthorSpine: Decodable, Identifiable, Hashable {
    let bookId: String
    let title: String
    let coverUrl: String?

    var id: String { bookId }

    enum CodingKeys: String, CodingKey { case bookId, title, coverUrl }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bookId = try c.decode(String.self, forKey: .bookId)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        coverUrl = try c.decodeIfPresent(String.self, forKey: .coverUrl)
    }
}

struct AuthorLibraryRef: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
}

/// How many people hold each role, so the control can offer the three this
/// collection uses rather than the seven the vocabulary defines.
struct ContributorRoleCount: Decodable, Identifiable, Hashable {
    let code: String
    let count: Int

    var id: String { code }

    init(code: String, count: Int) {
        self.code = code
        self.count = count
    }

    enum CodingKeys: String, CodingKey { case code, count }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decodeIfPresent(String.self, forKey: .code) ?? ""
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
    }

    /// Role codes are a fixed vocabulary sent raw, the same as ownership and
    /// read status.
    var label: String {
        switch code {
        case "author":      return "Author"
        case "illustrator": return "Illustrator"
        case "translator":  return "Translator"
        case "editor":      return "Editor"
        case "narrator":    return "Narrator"
        case "colorist":    return "Colourist"
        case "letterer":    return "Letterer"
        default:            return code.capitalized
        }
    }
}

struct AuthorIndexPage: Decodable {
    let items: [AuthorIndexEntry]
    let total: Int
    let roles: [ContributorRoleCount]

    enum CodingKeys: String, CodingKey { case items, total, roles }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([AuthorIndexEntry].self, forKey: .items) ?? []
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        roles = try c.decodeIfPresent([ContributorRoleCount].self, forKey: .roles) ?? []
    }
}
