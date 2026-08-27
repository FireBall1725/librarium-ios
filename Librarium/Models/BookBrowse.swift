// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation

/// Browsing a collection rather than a library.
///
/// The per-library list this replaces could filter on three things: tag, media
/// type, and first letter. `/me/books` takes eleven dimensions and returns a
/// count for each value, so a filter that would return nothing can be seen
/// before it is tapped. The counts and the list take the same parameters on
/// purpose: a filter panel that says "Reading 29" over a list that ignores the
/// tick is the failure that shape prevents.

// MARK: - Dimensions

/// The facets `/me/books` answers with, in the order they are shown.
///
/// The order is the web client's and is not alphabetical or arbitrary: where a
/// book is, then how you stand with it, then what it is, and the open
/// vocabularies last because they never stop growing. Tag and genre would
/// otherwise push everything with a fixed vocabulary off the bottom as the
/// shelf fills.
enum BrowseFacet: String, CaseIterable, Identifiable, Hashable {
    // Where it is.
    case ownership, library, shelf, location
    // How you stand with it.
    case readStatus = "read_status"
    case favourite
    case rating
    case myRating = "my_rating"
    // What it is.
    case mediaType = "media_type"
    // Open vocabularies.
    case tag, genre

    var id: String { rawValue }

    /// The query parameter the API reads this dimension from.
    var apiParam: String {
        switch self {
        case .ownership:  return "own"
        case .library:    return "lib"
        case .shelf:      return "shelf"
        case .location:   return "location"
        case .readStatus: return "status"
        case .favourite:  return "fav"
        case .rating:     return "rating"
        case .myRating:   return "my_rating"
        case .mediaType:  return "type"
        case .tag:        return "tag"
        case .genre:      return "genre"
        }
    }

    var title: String {
        switch self {
        case .ownership:  return "Ownership"
        case .library:    return "Library"
        // Not "Shelf". A shelf is where a physical copy sits now, so the
        // hand-picked set of books took the word the reader already uses for
        // it. The API still calls the facet `shelf`, which is why the case is
        // named for the wire and labelled for the person.
        case .shelf:      return "List"
        case .location:   return "Shelf"
        case .readStatus: return "Status"
        case .favourite:  return "Favourite"
        case .rating:     return "Rating"
        case .myRating:   return "My rating"
        case .mediaType:  return "Media type"
        case .tag:        return "Tag"
        case .genre:      return "Genre"
        }
    }

    /// SF Symbol for the section header, so a long sheet can be scanned by
    /// shape rather than read line by line.
    var icon: String {
        switch self {
        case .ownership:  return "shippingbox"
        case .library:    return "building.columns"
        case .shelf:      return "list.bullet"
        case .location:   return "square.grid.3x3"
        case .readStatus: return "book"
        case .favourite:  return "star"
        case .rating:     return "star.leadinghalf.filled"
        case .myRating:   return "person.crop.circle.badge.checkmark"
        case .mediaType:  return "rectangle.stack"
        case .tag:        return "tag"
        case .genre:      return "theatermasks"
        }
    }
}

// MARK: - Counts

struct FacetValue: Decodable, Hashable, Identifiable {
    let value: String
    let label: String
    let count: Int

    var id: String { value }

    init(value: String, label: String, count: Int) {
        self.value = value
        self.label = label
        self.count = count
    }

    enum CodingKeys: String, CodingKey {
        case value, label, count
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
    }
}

/// Every dimension's counts, from one request.
struct BookFacets: Decodable {
    var ownership: [FacetValue] = []
    var library: [FacetValue] = []
    var readStatus: [FacetValue] = []
    var mediaType: [FacetValue] = []
    var genre: [FacetValue] = []
    var tag: [FacetValue] = []
    var shelf: [FacetValue] = []
    var location: [FacetValue] = []
    var rating: [FacetValue] = []
    var myRating: [FacetValue] = []
    var favourite: [FacetValue] = []

    init() {}

    /// Spelled out rather than synthesized. Writing `init(from:)` by hand turns
    /// synthesis off for the whole conformance, `CodingKeys` included, so the
    /// keys only exist because they are named here.
    enum CodingKeys: String, CodingKey {
        case ownership, library, readStatus, mediaType, genre, tag
        case shelf, location, rating, myRating, favourite
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read(_ key: CodingKeys) -> [FacetValue] {
            ((try? c.decodeIfPresent([FacetValue].self, forKey: key)) ?? nil) ?? []
        }
        ownership  = read(.ownership)
        library    = read(.library)
        readStatus = read(.readStatus)
        mediaType  = read(.mediaType)
        genre      = read(.genre)
        tag        = read(.tag)
        shelf      = read(.shelf)
        location   = read(.location)
        rating     = read(.rating)
        myRating   = read(.myRating)
        favourite  = read(.favourite)
    }

    subscript(facet: BrowseFacet) -> [FacetValue] {
        switch facet {
        case .ownership:  return ownership
        case .library:    return library
        case .shelf:      return shelf
        case .location:   return location
        case .readStatus: return readStatus
        case .favourite:  return favourite
        case .rating:     return rating
        case .myRating:   return myRating
        case .mediaType:  return mediaType
        case .tag:        return tag
        case .genre:      return genre
        }
    }

    /// Sums another server's counts into this one.
    ///
    /// One install can hold several accounts, and there is no server that can
    /// count across them. Values match by their raw value, which is a name for
    /// tags and genres and a UUID for libraries and lists, so two servers'
    /// libraries stay separate rows while a genre they share becomes one row
    /// with the totals added.
    func merged(with other: BookFacets) -> BookFacets {
        var out = BookFacets()
        for facet in BrowseFacet.allCases {
            let combined = Self.sum(self[facet], other[facet])
            switch facet {
            case .ownership:  out.ownership = combined
            case .library:    out.library = combined
            case .shelf:      out.shelf = combined
            case .location:   out.location = combined
            case .readStatus: out.readStatus = combined
            case .favourite:  out.favourite = combined
            case .rating:     out.rating = combined
            case .myRating:   out.myRating = combined
            case .mediaType:  out.mediaType = combined
            case .tag:        out.tag = combined
            case .genre:      out.genre = combined
            }
        }
        return out
    }

    private static func sum(_ a: [FacetValue], _ b: [FacetValue]) -> [FacetValue] {
        FacetMerge.sum(a, b)
    }
}

/// Adding two accounts' counts together.
///
/// Shared by both surfaces because the rule is the same, and having it twice is
/// how the two would drift. Values match on their raw value, which is a name
/// for tags and genres and a UUID for libraries and lists, so two servers'
/// libraries stay separate rows while a genre they share becomes one.
enum FacetMerge {
    static func sum(_ a: [FacetValue], _ b: [FacetValue]) -> [FacetValue] {
        guard !b.isEmpty else { return a }
        guard !a.isEmpty else { return b }
        var order: [String] = []
        var byValue: [String: FacetValue] = [:]
        for v in a + b {
            if let existing = byValue[v.value] {
                byValue[v.value] = FacetValue(value: v.value, label: existing.label,
                                              count: existing.count + v.count)
            } else {
                order.append(v.value)
                byValue[v.value] = v
            }
        }
        return order.compactMap { byValue[$0] }
    }
}

// MARK: - Selection

/// What the reader has ticked, in a form both the list and the counts accept.
struct BrowseSelection: Equatable {
    /// Ownership defaults to the shelf. Without it the first thing anyone sees
    /// is their own wishlist and a machine's suggestions mixed into the books
    /// they actually have, and "do I own this?" stops having an answer.
    static let defaultOwnership: Set<String> = ["shelf"]

    var values: [BrowseFacet: Set<String>] = [.ownership: defaultOwnership]
    var query = ""

    /// Contributor ids. Not a facet: the server takes the parameter but sends
    /// no counts for it, because a collection has hundreds of people and a
    /// list of them is a page rather than a section in a sheet. It arrives from
    /// the authors surface and leaves the same way.
    var contributors: Set<String> = []

    subscript(facet: BrowseFacet) -> Set<String> {
        get { values[facet] ?? [] }
        set { values[facet] = newValue.isEmpty ? nil : newValue }
    }

    mutating func toggle(_ facet: BrowseFacet, _ value: String) {
        var current = self[facet]
        if current.contains(value) { current.remove(value) } else { current.insert(value) }
        self[facet] = current
    }

    /// Ownership left empty means every state, which the API expresses by
    /// receiving no ownership filter at all. Clearing it is a real choice, so
    /// it cannot silently snap back to the shelf.
    var isDefault: Bool {
        query.isEmpty
            && values.count == 1
            && values[.ownership] == Self.defaultOwnership
    }

    /// How many filters are on, for the badge on the filter button. Ownership
    /// only counts when it is something other than the default, or a reader
    /// who has touched nothing is told they have a filter applied.
    var activeCount: Int {
        var n = contributors.isEmpty ? 0 : 1
        for facet in BrowseFacet.allCases {
            let vals = self[facet]
            if vals.isEmpty { continue }
            if facet == .ownership && vals == Self.defaultOwnership { continue }
            n += 1
        }
        return n
    }

    mutating func clear() {
        values = [.ownership: Self.defaultOwnership]
        contributors = []
    }

    func queryItems() -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { items.append(URLQueryItem(name: "q", value: trimmed)) }
        for facet in BrowseFacet.allCases {
            let vals = self[facet]
            if vals.isEmpty { continue }
            // Sorted so the same selection always produces the same URL. Set
            // iteration order is not stable, and an unstable URL defeats every
            // cache between here and the database.
            items.append(URLQueryItem(name: facet.apiParam, value: vals.sorted().joined(separator: ",")))
        }
        if !contributors.isEmpty {
            items.append(URLQueryItem(name: "contributor",
                                      value: contributors.sorted().joined(separator: ",")))
        }
        return items
    }
}

// MARK: - Labels

/// What a facet value is called, when the server sends the raw value.
///
/// Most dimensions come back with a real label: a library's name, a tag, a
/// media type's display name. Five do not, because their vocabulary is fixed
/// and belongs to whoever is reading it: ownership, read status, favourite, and
/// the two ratings, which arrive as bare numbers.
enum FacetLabels {
    static func label(_ facet: BrowseFacet, _ value: FacetValue) -> String {
        switch facet {
        case .ownership:  return ownership(value.value)
        case .readStatus: return readStatus(value.value)
        case .favourite:  return value.value == "true" ? "Favourited" : "Not favourited"
        case .rating, .myRating: return stars(value.value)
        default:          return value.label.isEmpty ? value.value : value.label
        }
    }

    static func ownership(_ value: String) -> String {
        switch value {
        case "shelf":     return "On the shelf"
        case "wishlist":  return "Wishlist"
        case "suggested": return "Suggested"
        // A volume of a series the collection holds part of, that nobody has.
        // The word people use for it is not "gap".
        case "gap":       return "Missing volume"
        default:          return value.capitalized
        }
    }

    static func readStatus(_ value: String) -> String {
        switch value {
        case "read":           return "Read"
        case "reading":        return "Reading"
        case "unread":         return "Unread"
        case "did_not_finish": return "Did not finish"
        case "want_to_read":   return "Want to read"
        default:               return value.capitalized
        }
    }

    /// Ratings are stored in whole points where two points are one star, so an
    /// 8 is four stars and a 7 is three and a half.
    static func stars(_ value: String) -> String {
        guard let points = Int(value) else { return value }
        let whole = points / 2
        let half = points % 2 == 1
        if half { return "\(whole)½ stars" }
        return whole == 1 ? "1 star" : "\(whole) stars"
    }
}
