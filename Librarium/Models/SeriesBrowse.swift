// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation

/// Browsing runs rather than one library's runs.
///
/// The list this replaces asked `/libraries/{id}/series` once per library, so a
/// reader with four libraries paid four requests to see one alphabetical list
/// and got no counts at all. `/me/series/index` answers with every run the
/// account can read, how many volumes are held, how many are missing, and the
/// nine dimensions the runs can be narrowed by.

// MARK: - Dimensions

/// The same four runs as the books rail, so moving between the two surfaces
/// does not mean relearning where a dimension lives. Ownership, lists and
/// locations are properties of books; status, arcs and reading are properties
/// of runs, and each slots into the group it belongs to.
enum SeriesFacet: String, CaseIterable, Identifiable, Hashable {
    // Where it is.
    case library
    // How you stand with it.
    case reading
    case rating
    case myRating = "my_rating"
    // What it is.
    case mediaType = "media_type"
    case status
    case arcs
    // Open vocabularies.
    case tag, genre

    var id: String { rawValue }

    var apiParam: String {
        switch self {
        case .library:   return "lib"
        case .reading:   return "reading"
        case .rating:    return "rating"
        case .myRating:  return "my_rating"
        case .mediaType: return "type"
        case .status:    return "status"
        case .arcs:      return "arcs"
        case .tag:       return "tag"
        case .genre:     return "genre"
        }
    }

    var title: String {
        switch self {
        case .library:   return "Library"
        case .reading:   return "Reading"
        case .rating:    return "Rating"
        case .myRating:  return "My rating"
        case .mediaType: return "Media type"
        case .status:    return "Status"
        case .arcs:      return "Arcs"
        case .tag:       return "Tag"
        case .genre:     return "Genre"
        }
    }

    var icon: String {
        switch self {
        case .library:   return "building.columns"
        case .reading:   return "book"
        case .rating:    return "star.leadinghalf.filled"
        case .myRating:  return "person.crop.circle.badge.checkmark"
        case .mediaType: return "rectangle.stack"
        case .status:    return "clock.arrow.circlepath"
        case .arcs:      return "arrow.triangle.branch"
        case .tag:       return "tag"
        case .genre:     return "theatermasks"
        }
    }
}

// MARK: - Counts

struct SeriesFacets: Decodable {
    var library: [FacetValue] = []
    var mediaType: [FacetValue] = []
    var genre: [FacetValue] = []
    var rating: [FacetValue] = []
    var myRating: [FacetValue] = []
    var status: [FacetValue] = []
    var arcs: [FacetValue] = []
    var reading: [FacetValue] = []
    var tag: [FacetValue] = []

    init() {}

    enum CodingKeys: String, CodingKey {
        case library, mediaType, genre, rating, myRating, status, arcs, reading, tag
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read(_ key: CodingKeys) -> [FacetValue] {
            ((try? c.decodeIfPresent([FacetValue].self, forKey: key)) ?? nil) ?? []
        }
        library = read(.library)
        mediaType = read(.mediaType)
        genre = read(.genre)
        rating = read(.rating)
        myRating = read(.myRating)
        status = read(.status)
        arcs = read(.arcs)
        reading = read(.reading)
        tag = read(.tag)
    }

    subscript(facet: SeriesFacet) -> [FacetValue] {
        switch facet {
        case .library:   return library
        case .reading:   return reading
        case .rating:    return rating
        case .myRating:  return myRating
        case .mediaType: return mediaType
        case .status:    return status
        case .arcs:      return arcs
        case .tag:       return tag
        case .genre:     return genre
        }
    }

    /// Sums a second account's counts in, matching `BookFacets.merged`.
    func merged(with other: SeriesFacets) -> SeriesFacets {
        var out = SeriesFacets()
        for facet in SeriesFacet.allCases {
            let combined = FacetMerge.sum(self[facet], other[facet])
            switch facet {
            case .library:   out.library = combined
            case .reading:   out.reading = combined
            case .rating:    out.rating = combined
            case .myRating:  out.myRating = combined
            case .mediaType: out.mediaType = combined
            case .status:    out.status = combined
            case .arcs:      out.arcs = combined
            case .tag:       out.tag = combined
            case .genre:     out.genre = combined
            }
        }
        return out
    }
}

// MARK: - Selection

struct SeriesSelection: Equatable {
    var values: [SeriesFacet: Set<String>] = [:]
    var query = ""

    subscript(facet: SeriesFacet) -> Set<String> {
        get { values[facet] ?? [] }
        set { values[facet] = newValue.isEmpty ? nil : newValue }
    }

    mutating func toggle(_ facet: SeriesFacet, _ value: String) {
        var current = self[facet]
        if current.contains(value) { current.remove(value) } else { current.insert(value) }
        self[facet] = current
    }

    /// Runs with volumes the reader does not have. Not a facet the server
    /// offers: it is derived from the counts already on every row, which is why
    /// it is filtered here and everything else is filtered there.
    var incompleteOnly = false

    var activeCount: Int {
        var n = SeriesFacet.allCases.reduce(0) { $0 + (self[$1].isEmpty ? 0 : 1) }
        if incompleteOnly { n += 1 }
        return n
    }

    mutating func clear() {
        values = [:]
        incompleteOnly = false
    }

    func queryItems() -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { items.append(URLQueryItem(name: "q", value: trimmed)) }
        for facet in SeriesFacet.allCases {
            let vals = self[facet]
            if vals.isEmpty { continue }
            items.append(URLQueryItem(name: facet.apiParam,
                                      value: vals.sorted().joined(separator: ",")))
        }
        return items
    }
}

// MARK: - Sorting

enum SeriesSortOption: String, CaseIterable, Identifiable {
    case name, volumes, missing, read, rating, recent

    var id: String { rawValue }
    var field: String { rawValue }

    var label: String {
        switch self {
        case .name:    return "Name"
        case .volumes: return "Volumes held"
        case .missing: return "Missing volumes"
        case .read:    return "Volumes read"
        case .rating:  return "Rating"
        case .recent:  return "Recently changed"
        }
    }
}

// MARK: - Wire shapes

/// What `/me/series/index` answers with.
struct SeriesIndexPage: Decodable {
    let items: [Series]
    let total: Int
    let facets: SeriesFacets

    enum CodingKeys: String, CodingKey { case items, total, facets }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([Series].self, forKey: .items) ?? []
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        facets = ((try? c.decodeIfPresent(SeriesFacets.self, forKey: .facets)) ?? nil) ?? SeriesFacets()
    }
}

// MARK: - Labels

enum SeriesFacetLabels {
    static func label(_ facet: SeriesFacet, _ value: FacetValue) -> String {
        switch facet {
        case .status:  return status(value.value)
        case .arcs:    return value.value == "with" ? "With arcs" : "No arcs"
        case .reading: return reading(value.value)
        case .rating, .myRating: return FacetLabels.stars(value.value)
        default: return value.label.isEmpty ? value.value : value.label
        }
    }

    static func status(_ value: String) -> String {
        switch value {
        case "ongoing":   return "Ongoing"
        case "completed": return "Complete"
        case "hiatus":    return "On hiatus"
        case "cancelled": return "Cancelled"
        default:          return value.capitalized
        }
    }

    static func reading(_ value: String) -> String {
        switch value {
        case "unread":   return "Unread"
        case "reading":  return "Reading"
        case "read_all": return "Read all"
        default:         return value.capitalized
        }
    }
}
