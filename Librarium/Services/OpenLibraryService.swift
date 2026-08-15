// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation

/// Public ISBN lookup against the Open Library API. Used by Lite-mode
/// installs that don't have a Librarium server to proxy metadata
/// lookups through. Endpoint family:
/// `https://openlibrary.org/api/books?bibkeys=ISBN:<isbn>&format=json&jscmd=data`
/// returns a single dict keyed by `"ISBN:<isbn>"` with title, authors,
/// publishers, publish_date, number_of_pages, cover URLs, etc.
///
/// Result shape mirrors `ISBNLookupResult` so the scan flow can consume
/// either Open Library or the server's own LookupService without
/// branching downstream.
struct OpenLibraryService {
    /// Fetch metadata for a single ISBN. Throws on network errors so
    /// callers can distinguish "couldn't reach Open Library" from
    /// "Open Library has no entry for this ISBN" (which returns []).
    ///
    /// Tries two endpoints in order:
    /// 1. `api/books?bibkeys=ISBN:<isbn>` — richer, includes covers +
    ///    publishers + authors fully expanded
    /// 2. `/isbn/<isbn>.json` — bare-bones, but covers more obscure
    ///    books that the books-api endpoint misses
    func isbn(_ isbn: String) async throws -> [ISBNLookupResult] {
        let trimmed = isbn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Try the scanned code as-is plus any derived forms
        // (ISBN-10 ↔ ISBN-13, UPC-A → ISBN-13 heuristic). Open Library
        // doesn't index UPC barcodes directly, but the derived ISBN-13
        // form catches mass-market paperbacks issued before EAN-13
        // became the standard.
        let candidates = Array(Set(ISBNCandidates.expand(trimmed)))
        var lastError: Error?
        var throwCount = 0
        for candidate in candidates {
            do {
                let rich = try await fetchBooksAPI(isbn: candidate)
                if let first = rich.first { return [first] }
                if let bare = try await fetchISBNEndpoint(isbn: candidate) {
                    return [bare]
                }
            } catch {
                lastError = error
                throwCount += 1
            }
        }
        // Every candidate threw a network error — propagate so the UI
        // shows "couldn't reach Open Library" rather than "no match".
        if throwCount == candidates.count, let lastError {
            throw lastError
        }
        return []
    }

    // MARK: - Endpoint 3: search.json

    /// Free-text search, for books added by hand that have no ISBN to
    /// look up. Returns several candidates because a title match is a
    /// guess; the caller picks one.
    func search(_ query: String) async throws -> [ISBNLookupResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents(string: "https://openlibrary.org/search.json")!
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "limit", value: "15"),
            // Ask for only what the result rows render. The default
            // response carries a large payload per document.
            URLQueryItem(
                name: "fields",
                value: "key,title,subtitle,author_name,first_publish_year,isbn,cover_i,number_of_pages_median,publisher,language"
            )
        ]
        guard let url = components.url else { return [] }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let docs = root["docs"] as? [[String: Any]]
        else { return [] }

        return docs.compactMap { Self.decodeSearchDoc($0) }
    }

    private static func decodeSearchDoc(_ doc: [String: Any]) -> ISBNLookupResult? {
        let title = (doc["title"] as? String) ?? ""
        guard !title.isEmpty else { return nil }

        let isbns = (doc["isbn"] as? [String]) ?? []
        let coverUrl = (doc["cover_i"] as? Int).map {
            "https://covers.openlibrary.org/b/id/\($0)-L.jpg"
        } ?? ""
        let year = (doc["first_publish_year"] as? Int).map(String.init) ?? ""

        return ISBNLookupResult(
            provider: "openlibrary",
            providerDisplay: "Open Library",
            title: title,
            subtitle: (doc["subtitle"] as? String) ?? "",
            authors: (doc["author_name"] as? [String]) ?? [],
            publisher: ((doc["publisher"] as? [String]) ?? []).first ?? "",
            publishDate: year,
            isbn10: isbns.first(where: { $0.count == 10 }) ?? "",
            isbn13: isbns.first(where: { $0.count == 13 }) ?? "",
            // search.json has no description field at all; the works
            // fetch below fills it once a candidate is chosen.
            description: "",
            coverUrl: coverUrl,
            language: ((doc["language"] as? [String]) ?? []).first ?? "",
            pageCount: doc["number_of_pages_median"] as? Int,
            categories: nil
        )
    }

    // MARK: - Works description

    /// Fetch a book's long description from `/works/{id}.json`.
    ///
    /// Neither `api/books` nor `search.json` returns one, which is why
    /// every Lite book added so far has a blank description. This is a
    /// second round-trip, so it runs only when the caller wants a full
    /// record rather than on every scan.
    ///
    /// The description field is polymorphic: older records store a plain
    /// string, newer ones an object with a `value` key.
    func worksDescription(isbn: String) async -> String {
        guard let editionURL = URL(string: "https://openlibrary.org/isbn/\(isbn).json"),
              let (editionData, editionResponse) = try? await URLSession.shared.data(from: editionURL),
              let editionHTTP = editionResponse as? HTTPURLResponse, editionHTTP.statusCode == 200,
              let edition = try? JSONSerialization.jsonObject(with: editionData) as? [String: Any],
              let works = edition["works"] as? [[String: Any]],
              let workKey = works.first?["key"] as? String
        else { return "" }

        guard let workURL = URL(string: "https://openlibrary.org\(workKey).json"),
              let (workData, workResponse) = try? await URLSession.shared.data(from: workURL),
              let workHTTP = workResponse as? HTTPURLResponse, workHTTP.statusCode == 200,
              let work = try? JSONSerialization.jsonObject(with: workData) as? [String: Any]
        else { return "" }

        if let text = work["description"] as? String { return text }
        if let wrapped = work["description"] as? [String: Any],
           let text = wrapped["value"] as? String { return text }
        return ""
    }

    // MARK: - Endpoint 1: api/books

    private func fetchBooksAPI(isbn: String) async throws -> [ISBNLookupResult] {
        var components = URLComponents(string: "https://openlibrary.org/api/books")!
        components.queryItems = [
            URLQueryItem(name: "bibkeys", value: "ISBN:\(isbn)"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "jscmd", value: "data"),
        ]
        guard let url = components.url else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let book = json["ISBN:\(isbn)"] as? [String: Any],
              let result = Self.decodeBooksAPI(book: book, isbn: isbn) else {
            return []
        }
        return [result]
    }

    // MARK: - Endpoint 2: /isbn/<isbn>.json

    private func fetchISBNEndpoint(isbn: String) async throws -> ISBNLookupResult? {
        guard let url = URL(string: "https://openlibrary.org/isbn/\(isbn).json") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return Self.decodeISBNEndpoint(record: json, isbn: isbn)
    }

    // MARK: - Decoder

    /// Parse Open Library's `api/books` response into an
    /// ISBNLookupResult. Open Library returns a deeply nested dict
    /// with optional fields everywhere; we extract what we can and
    /// fall back to empty strings so the caller doesn't have to
    /// special-case nils.
    private static func decodeBooksAPI(book: [String: Any], isbn: String) -> ISBNLookupResult? {
        let title = (book["title"] as? String) ?? ""
        guard !title.isEmpty else { return nil }
        let subtitle = (book["subtitle"] as? String) ?? ""
        let authors = (book["authors"] as? [[String: Any]] ?? [])
            .compactMap { $0["name"] as? String }
        let publishers = (book["publishers"] as? [[String: Any]] ?? [])
            .compactMap { $0["name"] as? String }
        let publisher = publishers.first ?? ""
        let publishDate = (book["publish_date"] as? String) ?? ""
        let pageCount = book["number_of_pages"] as? Int

        // Open Library returns identifiers under `identifiers.isbn_10`
        // / `isbn_13` arrays. The lookup ISBN we were given might not
        // match either (e.g. user typed an isbn-10, OL returned 13),
        // so capture both shapes.
        let identifiers = book["identifiers"] as? [String: Any] ?? [:]
        let isbn10 = (identifiers["isbn_10"] as? [String])?.first
            ?? (isbn.count == 10 ? isbn : "")
        let isbn13 = (identifiers["isbn_13"] as? [String])?.first
            ?? (isbn.count == 13 ? isbn : "")

        let coverUrl: String
        if let cover = book["cover"] as? [String: Any] {
            // Prefer largest available
            coverUrl = (cover["large"] as? String)
                ?? (cover["medium"] as? String)
                ?? (cover["small"] as? String)
                ?? ""
        } else {
            coverUrl = ""
        }

        let subjects = (book["subjects"] as? [[String: Any]] ?? [])
            .compactMap { $0["name"] as? String }

        // Open Library's `api/books` endpoint doesn't include the long
        // description for most books — it lives on /works/{id}.json
        // which is a second round-trip. Leave empty for now; users can
        // edit the description after add.
        return ISBNLookupResult(
            provider: "openlibrary",
            providerDisplay: "Open Library",
            title: title,
            subtitle: subtitle,
            authors: authors,
            publisher: publisher,
            publishDate: publishDate,
            isbn10: isbn10,
            isbn13: isbn13,
            description: "",
            coverUrl: coverUrl,
            language: "",
            pageCount: pageCount,
            categories: subjects.isEmpty ? nil : subjects
        )
    }

    /// Decoder for the `/isbn/<isbn>.json` shape. Fields are flatter
    /// than the books-api response: `title`, `publishers` (as string
    /// array), `publish_date`, `number_of_pages`, `covers` (array of
    /// cover ids that resolve to image URLs). Authors live as
    /// `[{"key": "/authors/OL123A"}]` refs and would need a second
    /// round-trip to resolve names — for now we skip them; the user
    /// can edit after add.
    private static func decodeISBNEndpoint(record: [String: Any], isbn: String) -> ISBNLookupResult? {
        let title = (record["title"] as? String) ?? ""
        guard !title.isEmpty else { return nil }
        let subtitle = (record["subtitle"] as? String) ?? ""
        let publishers = record["publishers"] as? [String] ?? []
        let publisher = publishers.first ?? ""
        let publishDate = (record["publish_date"] as? String) ?? ""
        let pageCount = record["number_of_pages"] as? Int

        let isbn10List = record["isbn_10"] as? [String] ?? []
        let isbn13List = record["isbn_13"] as? [String] ?? []
        let isbn10 = isbn10List.first ?? (isbn.count == 10 ? isbn : "")
        let isbn13 = isbn13List.first ?? (isbn.count == 13 ? isbn : "")

        let coverIds = record["covers"] as? [Int] ?? []
        let coverUrl = coverIds.first.map { "https://covers.openlibrary.org/b/id/\($0)-L.jpg" } ?? ""

        return ISBNLookupResult(
            provider: "openlibrary",
            providerDisplay: "Open Library",
            title: title,
            subtitle: subtitle,
            authors: [],
            publisher: publisher,
            publishDate: publishDate,
            isbn10: isbn10,
            isbn13: isbn13,
            description: "",
            coverUrl: coverUrl,
            language: "",
            pageCount: pageCount,
            categories: nil
        )
    }
}

// MARK: - LiteMetadataProvider

extension OpenLibraryService: LiteMetadataProvider {
    var id: String { "openlibrary" }
    var displayName: String { "Open Library" }
    /// Keyless and anonymous, so it is always available and never
    /// identifies the user to anyone.
    /// Needs no credentials, so "configured" is purely the user's
    /// on/off switch. On by default.
    var isConfigured: Bool { LiteMetadataSettings.isEnabled(providerID: "openlibrary") }
    var isAuthenticated: Bool { false }

    /// The protocol's ISBN path folds in the works description, which
    /// the scan flow deliberately skips to keep the scan fast. A refresh
    /// is a user-initiated action where a second round-trip is fine.
    func lookup(isbn: String) async throws -> [ISBNLookupResult] {
        let results = try await self.isbn(isbn)
        guard let first = results.first, first.description.isEmpty else { return results }

        let lookupISBN = first.isbn13.isEmpty ? (first.isbn10.isEmpty ? isbn : first.isbn10) : first.isbn13
        let description = await worksDescription(isbn: lookupISBN)
        guard !description.isEmpty else { return results }

        return [ISBNLookupResult(
            provider: first.provider,
            providerDisplay: first.providerDisplay,
            title: first.title,
            subtitle: first.subtitle,
            authors: first.authors,
            publisher: first.publisher,
            publishDate: first.publishDate,
            isbn10: first.isbn10,
            isbn13: first.isbn13,
            description: description,
            coverUrl: first.coverUrl,
            language: first.language,
            pageCount: first.pageCount,
            categories: first.categories
        )]
    }

    func search(query: String) async throws -> [ISBNLookupResult] {
        try await self.search(query)
    }
}
