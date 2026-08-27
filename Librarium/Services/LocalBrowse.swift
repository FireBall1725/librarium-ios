// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation
import SwiftData

/// Browsing a Lite collection, which has no server to ask.
///
/// The rule everywhere else is that the API owns the logic. Lite has no API, so
/// this is the exception the rule always implied: with no server there is
/// nothing to defer to, and the alternative is a Lite collection that cannot be
/// filtered at all.
///
/// It answers six of the eleven dimensions, and the ones it cannot are absent
/// rather than empty. Ownership, lists, shelf locations and missing volumes are
/// server concepts: a Lite library has no wishlist, no gap detection and no
/// series promotion, so offering those filters would be offering a control that
/// can only ever return nothing.
struct LocalBrowse {
    let modelContainer: ModelContainer
    let serverURL: String

    /// Everything in the collection, before filtering. Small enough to hold:
    /// a Lite library is one person's shelf, not an instance's catalogue.
    private func all() -> [Book] {
        BookCache(modelContainer: modelContainer).searchAllBooks(serverURL: serverURL, query: "")
    }

    func page(selection: BrowseSelection, sort: BookSortOption) -> (books: [Book], facets: BookFacets) {
        let everything = all()
        let matched = everything.filter { matches($0, selection) }
        return (sorted(matched, by: sort), facets(everything, selection))
    }

    // MARK: - Filtering

    private func matches(_ book: Book, _ selection: BrowseSelection) -> Bool {
        let q = selection.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            let inTitle = book.title.lowercased().contains(q)
            let inAuthor = book.contributors.contains { $0.name.lowercased().contains(q) }
            if !inTitle && !inAuthor { return false }
        }
        return BrowseFacet.allCases.allSatisfy { facet in
            let picked = selection[facet]
            if picked.isEmpty { return true }
            guard let values = Self.values(of: facet, in: book) else {
                // A dimension this collection has no answer for. Nothing can
                // match it, which is why the sheet never offers it.
                return false
            }
            return !picked.isDisjoint(with: values)
        }
    }

    /// What a book has for a dimension, or nil when the dimension does not
    /// exist locally.
    private static func values(of facet: BrowseFacet, in book: Book) -> Set<String>? {
        switch facet {
        case .mediaType:  return [book.mediaType.lowercased()]
        case .tag:        return Set(book.tags.map { $0.name })
        case .genre:      return Set(book.genres.map { $0.name })
        case .readStatus: return [book.userReadStatus?.isEmpty == false ? book.userReadStatus! : "unread"]
        case .myRating:   return book.userRating.map { [String($0)] } ?? []
        case .library:    return book.libraryId.isEmpty ? [] : [book.libraryId]
        case .ownership, .shelf, .location, .rating, .favourite:
            return nil
        }
    }

    /// Whether a dimension can be answered without a server. The filter sheet
    /// asks this so it can leave the others out entirely.
    static func answers(_ facet: BrowseFacet) -> Bool {
        values(of: facet, in: nil) != nil
    }

    private static func values(of facet: BrowseFacet, in book: Book?) -> Set<String>? {
        switch facet {
        case .mediaType, .tag, .genre, .readStatus, .myRating, .library:
            return book.flatMap { values(of: facet, in: $0) } ?? []
        case .ownership, .shelf, .location, .rating, .favourite:
            return nil
        }
    }

    // MARK: - Counts

    /// Counted the same way the server counts: each dimension over the set
    /// filtered by every *other* dimension, so ticking one value leaves the
    /// rest of its own dimension showing what they would return. Counting the
    /// fully filtered set instead leaves every unticked row at nought and no
    /// way back out of the filter just applied.
    private func facets(_ everything: [Book], _ selection: BrowseSelection) -> BookFacets {
        var out = BookFacets()
        for facet in BrowseFacet.allCases where Self.answers(facet) {
            var without = selection
            without[facet] = []
            let pool = everything.filter { matches($0, without) }

            var counts: [String: Int] = [:]
            var labels: [String: String] = [:]
            for book in pool {
                for value in Self.values(of: facet, in: book) ?? [] {
                    counts[value, default: 0] += 1
                    labels[value] = Self.label(of: facet, value: value, in: book)
                }
            }
            var values: [FacetValue] = []
            values.reserveCapacity(counts.count)
            for (value, count) in counts {
                values.append(FacetValue(value: value, label: labels[value] ?? value, count: count))
            }
            values.sort { a, b in
                a.count == b.count ? a.label < b.label : a.count > b.count
            }

            switch facet {
            case .mediaType:  out.mediaType = values
            case .tag:        out.tag = values
            case .genre:      out.genre = values
            case .readStatus: out.readStatus = values
            case .myRating:   out.myRating = values
            case .library:    out.library = values
            default:          break
            }
        }
        return out
    }

    private static func label(of facet: BrowseFacet, value: String, in book: Book) -> String {
        switch facet {
        // The display name rather than the slug, matching what the server sends
        // for the same facet.
        case .mediaType: return book.mediaType.isEmpty ? value : book.mediaType
        default:         return value
        }
    }

    // MARK: - Sorting

    private func sorted(_ books: [Book], by sort: BookSortOption) -> [Book] {
        let ascending = sort.dir == "asc"
        switch sort {
        case .titleAsc, .titleDesc:
            return books.sorted {
                ascending
                    ? $0.title.librariumSortKey() < $1.title.librariumSortKey()
                    : $0.title.librariumSortKey() > $1.title.librariumSortKey()
            }
        case .authorAsc, .authorDesc:
            func author(_ b: Book) -> String {
                (b.contributors.first?.name ?? "").librariumSortKey()
            }
            return books.sorted { ascending ? author($0) < author($1) : author($0) > author($1) }
        case .recentlyAdded, .oldestFirst:
            return books.sorted { ascending ? $0.createdAt < $1.createdAt : $0.createdAt > $1.createdAt }
        case .newestRelease, .oldestRelease:
            func year(_ b: Book) -> Int { b.publishYear ?? 0 }
            return books.sorted { ascending ? year($0) < year($1) : year($0) > year($1) }
        }
    }
}
