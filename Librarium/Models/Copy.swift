// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation

/// One physical object on a shelf.
///
/// Not a count. A number could say you owned two and nothing else: which one is
/// signed, which is lent to a friend, which is in the office. Each object gets
/// a row, and everything true of the object rather than of the work or the
/// printing lives on it.
struct Copy: Codable, Identifiable, Hashable {
    let id: String
    let libraryId: String
    let bookId: String

    /// Nil when the printing was never recorded, which is a supported state
    /// rather than a gap: a book can be on a shelf without anyone having said
    /// which edition it is.
    let editionId: String?

    let condition: String
    let isSigned: Bool
    let notes: String

    let locationId: String?
    /// Filled by reads that join it, empty on a bare row.
    let locationName: String

    /// Names the borrower when this copy is out, empty otherwise.
    let onLoanTo: String

    var isLent: Bool { !onLoanTo.isEmpty }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(String.self, forKey: .id)
        libraryId    = try c.decodeIfPresent(String.self, forKey: .libraryId)    ?? ""
        bookId       = try c.decodeIfPresent(String.self, forKey: .bookId)       ?? ""
        editionId    = try c.decodeIfPresent(String.self, forKey: .editionId)
        condition    = try c.decodeIfPresent(String.self, forKey: .condition)    ?? ""
        isSigned     = try c.decodeIfPresent(Bool.self,   forKey: .isSigned)     ?? false
        notes        = try c.decodeIfPresent(String.self, forKey: .notes)        ?? ""
        locationId   = try c.decodeIfPresent(String.self, forKey: .locationId)
        locationName = try c.decodeIfPresent(String.self, forKey: .locationName) ?? ""
        onLoanTo     = try c.decodeIfPresent(String.self, forKey: .onLoanTo)     ?? ""
    }
}

/// A place in a library where copies physically live.
struct CopyLocation: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let parentId: String?
    let copyCount: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(String.self, forKey: .id)
        name      = try c.decodeIfPresent(String.self, forKey: .name)      ?? ""
        parentId  = try c.decodeIfPresent(String.self, forKey: .parentId)
        copyCount = try c.decodeIfPresent(Int.self,    forKey: .copyCount) ?? 0
    }
}

/// The words a condition code stands for.
///
/// The server sends codes and no labels on purpose: a name stored in the
/// database cannot be translated. An unrecognised code shows itself rather than
/// an empty cell, which is what a newly added condition does until this catches
/// up.
enum CopyCondition {
    static func label(_ code: String) -> String {
        switch code {
        case "new":        return "New"
        case "fine":       return "Fine"
        case "very_good":  return "Very good"
        case "good":       return "Good"
        case "fair":       return "Fair"
        case "poor":       return "Poor"
        case "ex_library": return "Ex-library"
        default:           return code
        }
    }
}
