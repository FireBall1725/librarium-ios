// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation

/// The browse endpoints that are scoped to a person rather than to a library.
///
/// One request covers every library an account can read, ranked together. The
/// per-library list this replaces had to be asked once per library, which meant
/// the request count grew with the collection, results came back grouped by
/// library instead of ranked, and a per-library page budget gave a shelf of
/// 1,400 books and a shelf of 1 the same allowance.
struct MeBrowseService {
    let client: APIClient

    // MARK: - Books

    func books(selection: BrowseSelection, sort: BookSortOption, page: Int, perPage: Int)
        async throws -> Paged<Book>
    {
        var items = selection.queryItems()
        items.append(URLQueryItem(name: "page", value: String(page)))
        items.append(URLQueryItem(name: "per_page", value: String(perPage)))
        items.append(URLQueryItem(name: "sort", value: sort.field))
        items.append(URLQueryItem(name: "sort_dir", value: sort.dir))
        return try await client.get(Self.path("/api/v1/me/books", items))
    }

    /// The counts for every dimension, from one request.
    ///
    /// Sent with the same selection as the list, because each dimension is
    /// counted with its own selection excluded: ticking Manga has to leave the
    /// other media types showing what they would return, or there is no way
    /// back out of the filter you just applied.
    func facets(selection: BrowseSelection) async throws -> BookFacets {
        // Wrapped twice. The handler builds its body as `{"data": facets}` and
        // the response writer wraps every body in `data` again, so unwrapping
        // once lands on an envelope rather than on the counts. Decoding
        // straight into `BookFacets` there finds none of its keys and yields a
        // filter sheet that is silently empty, which is the shape this bug
        // takes every time: no error, just nothing to tick.
        let wrapper: FacetsEnvelope =
            try await client.get(Self.path("/api/v1/me/books/facets", selection.queryItems()))
        return wrapper.data
    }

    private struct FacetsEnvelope: Decodable {
        let data: BookFacets
    }

    // MARK: - Series

    /// Every run the account can read, with its counts and the facets beside
    /// them. One request per account rather than one per library.
    func series(selection: SeriesSelection, sort: SeriesSortOption) async throws -> SeriesIndexPage {
        var items = selection.queryItems()
        if sort != .name {
            items.append(URLQueryItem(name: "sort", value: sort.field))
            // Descending for every sort but name. Nobody opens this asking for
            // the run with the fewest volumes missing.
            items.append(URLQueryItem(name: "dir", value: "desc"))
        }
        // The index builds a strip of up to sixty covers per run for the page
        // that draws them. The mosaic here draws four, and asking for the rest
        // is work nobody sees.
        items.append(URLQueryItem(name: "volumes", value: "4"))
        return try await client.get(Self.path("/api/v1/me/series/index", items))
    }

    // MARK: - Counts

    func counts() async throws -> CollectionCounts {
        try await client.get("/api/v1/me/counts")
    }

    // MARK: - Helpers

    /// `URLComponents` rather than string interpolation, so a tag with a slash
    /// or an ampersand in it narrows the list instead of corrupting the URL.
    private static func path(_ base: String, _ items: [URLQueryItem]) -> String {
        guard !items.isEmpty else { return base }
        var comps = URLComponents()
        comps.queryItems = items
        return base + "?" + (comps.percentEncodedQuery ?? "")
    }
}

// MARK: - Counts

/// The totals behind the navigation, so a surface can say how much is in it
/// before anyone opens it.
struct CollectionCounts: Decodable {
    var books = 0
    var series = 0
    var authors = 0
    var loans = 0
    var loansOverdue = 0
    var suggestions = 0

    enum CodingKeys: String, CodingKey {
        case books, series, authors, loans, loansOverdue, suggestions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read(_ key: CodingKeys) -> Int {
            ((try? c.decodeIfPresent(Int.self, forKey: key)) ?? nil) ?? 0
        }
        books = read(.books)
        series = read(.series)
        authors = read(.authors)
        loans = read(.loans)
        loansOverdue = read(.loansOverdue)
        suggestions = read(.suggestions)
    }
}
