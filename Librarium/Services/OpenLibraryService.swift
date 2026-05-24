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
