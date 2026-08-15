// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation

/// Hardcover.app metadata for Lite libraries.
///
/// Ported from the api's provider rather than reinvented: the GraphQL
/// documents below match `internal/providers/books/hardcover.go` so both
/// clients ask for the same fields and a book looks the same whether it
/// came from a server or from the device.
///
/// Unlike Open Library this needs a personal API key and therefore
/// identifies the user to a third party, so it stays opt-in and every
/// call is skipped when no key is stored. Free account, 60 requests a
/// minute.
struct HardcoverService: LiteMetadataProvider {
    let id = "hardcover"
    let displayName = "Hardcover"
    let isAuthenticated = true

    /// Keychain key. The token is a credential, so it never goes near
    /// UserDefaults.
    static let keychainKey = "lite.hardcover.apiKey"
    static let endpoint = URL(string: "https://api.hardcover.app/v1/graphql")!

    var apiKey: String? {
        let key = KeychainService.shared.get(Self.keychainKey).map(Self.normalize)
        return (key?.isEmpty ?? true) ? nil : key
    }

    var isConfigured: Bool { enabled && apiKey != nil }

    /// User-facing on/off, independent of whether a key is stored, so
    /// turning the source off does not throw the key away.
    var enabled: Bool { LiteMetadataSettings.isEnabled(providerID: "hardcover") }

    /// Hardcover's account page hands out a token that already starts
    /// with "Bearer ". Pasting it verbatim and prefixing again produces
    /// `Bearer Bearer eyJ…`, which the API rejects with "Malformed
    /// Authorization header". Strip any prefix the user pasted so both
    /// forms work.
    static func normalize(key: String) -> String {
        var trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.lowercased().hasPrefix("bearer ") {
            trimmed = String(trimmed.dropFirst("bearer ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    // MARK: - Queries

    /// Editions by ISBN-10 or ISBN-13, joined to the book for title,
    /// description, authors and genres.
    private static let isbnQuery = """
    query BookByISBN($isbn: String!) {
      editions(
        where: { _or: [{ isbn_13: { _eq: $isbn } }, { isbn_10: { _eq: $isbn } }] }
        limit: 1
      ) {
        isbn_13
        isbn_10
        pages
        release_date
        image { url }
        publisher { name }
        language { language }
        book {
          title
          description
          cached_tags
          contributions { author { name } }
        }
      }
    }
    """

    private static let searchQuery = """
    query SearchBooks($query: String!) {
      search(query: $query, query_type: "Book", per_page: 15) {
        results
      }
    }
    """

    // MARK: - LiteMetadataProvider

    func lookup(isbn: String) async throws -> [ISBNLookupResult] {
        let data = try await post(query: Self.isbnQuery, variables: ["isbn": isbn])
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let editions = payload["editions"] as? [[String: Any]],
              let edition = editions.first
        else { return [] }
        return [Self.decodeEdition(edition, fallbackISBN: isbn)].compactMap { $0 }
    }

    func search(query: String) async throws -> [ISBNLookupResult] {
        let data = try await post(query: Self.searchQuery, variables: ["query": query])
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let search = payload["search"] as? [String: Any]
        else { return [] }

        // `results` is opaque Typesense output shaped
        // {"found":N,"hits":[{"document":{...}}]}. It arrives as nested
        // JSON, not a string, so no second parse is needed.
        guard let results = search["results"] as? [String: Any],
              let hits = results["hits"] as? [[String: Any]]
        else { return [] }

        return hits.compactMap { hit in
            guard let doc = hit["document"] as? [String: Any] else { return nil }
            return Self.decodeSearchDoc(doc)
        }
    }

    // MARK: - Transport

    private func post(query: String, variables: [String: Any]) async throws -> Data {
        guard let apiKey else {
            throw LiteMetadataError.notConfigured(provider: displayName)
        }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["query": query, "variables": variables]
        )
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return data }
        switch http.statusCode {
        case 200:
            return data
        case 401, 403:
            throw LiteMetadataError.invalidKey(provider: displayName)
        case 429:
            throw LiteMetadataError.rateLimited(provider: displayName)
        default:
            // Throwing, not returning empty data. An empty body is
            // swallowed by the caller's `try?` and looks identical to
            // "no results", so a 500 from Hardcover told the user their
            // ISBN was unknown. The aggregator's allFailed flag exists
            // precisely to tell those apart, and it only works if a
            // failure actually throws.
            throw URLError(.badServerResponse)
        }
    }

    /// Validate a key without storing it, so the settings screen can tell
    /// the user it works before saving. Returns nil on success or a
    /// human-readable reason on failure.
    static func validate(key: String) async -> String? {
        let token = normalize(key: key)
        guard !token.isEmpty else { return "Enter a key first." }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["query": "query { me { username } }", "variables": [:]]
        )
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return "No response from Hardcover." }
            switch http.statusCode {
            case 200:
                // A 200 can still carry GraphQL errors, which is how a
                // malformed token comes back.
                if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errors = root["errors"] as? [[String: Any]],
                   let first = errors.first,
                   let message = first["message"] as? String {
                    return message
                }
                return nil
            case 401, 403:
                return "Hardcover rejected that key."
            case 429:
                return "Hardcover is rate limiting. Try again in a minute."
            default:
                return "Hardcover returned status \(http.statusCode)."
            }
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Decoding

    private static func decodeEdition(_ edition: [String: Any], fallbackISBN: String) -> ISBNLookupResult? {
        let book = edition["book"] as? [String: Any]
        let title = (book?["title"] as? String) ?? ""
        guard !title.isEmpty else { return nil }

        let authors = ((book?["contributions"] as? [[String: Any]]) ?? []).compactMap {
            ($0["author"] as? [String: Any])?["name"] as? String
        }
        let isbn13 = (edition["isbn_13"] as? String) ?? ""
        let isbn10 = (edition["isbn_10"] as? String) ?? ""

        return ISBNLookupResult(
            provider: "hardcover",
            providerDisplay: "Hardcover",
            title: title,
            subtitle: "",
            authors: authors,
            publisher: ((edition["publisher"] as? [String: Any])?["name"] as? String) ?? "",
            publishDate: (edition["release_date"] as? String) ?? "",
            isbn10: isbn10.isEmpty && fallbackISBN.count == 10 ? fallbackISBN : isbn10,
            isbn13: isbn13.isEmpty && fallbackISBN.count == 13 ? fallbackISBN : isbn13,
            description: (book?["description"] as? String) ?? "",
            coverUrl: ((edition["image"] as? [String: Any])?["url"] as? String) ?? "",
            language: ((edition["language"] as? [String: Any])?["language"] as? String) ?? "",
            pageCount: edition["pages"] as? Int,
            categories: decodeGenres(book?["cached_tags"])
        )
    }

    private static func decodeSearchDoc(_ doc: [String: Any]) -> ISBNLookupResult? {
        let title = (doc["title"] as? String) ?? ""
        guard !title.isEmpty else { return nil }

        // The image is flat on some documents and nested on others.
        let cover = (doc["image_url"] as? String)
            ?? ((doc["image"] as? [String: Any])?["url"] as? String)
            ?? ""

        let isbns = (doc["isbns"] as? [String]) ?? []
        let isbn13 = isbns.first(where: { $0.count == 13 }) ?? ""
        let isbn10 = isbns.first(where: { $0.count == 10 }) ?? ""

        return ISBNLookupResult(
            provider: "hardcover",
            providerDisplay: "Hardcover",
            title: title,
            subtitle: "",
            authors: (doc["author_names"] as? [String]) ?? [],
            publisher: "",
            publishDate: "",
            isbn10: isbn10,
            isbn13: isbn13,
            description: (doc["description"] as? String) ?? "",
            coverUrl: cover,
            language: "",
            pageCount: nil,
            categories: nil
        )
    }

    /// `cached_tags` is a loose blob. Genres live under a "Genre" key as
    /// objects carrying a `tag` name; anything else is ignored rather
    /// than guessed at.
    private static func decodeGenres(_ raw: Any?) -> [String]? {
        guard let tags = raw as? [String: Any],
              let genres = tags["Genre"] as? [[String: Any]]
        else { return nil }
        let names = genres.compactMap { $0["tag"] as? String }
        return names.isEmpty ? nil : names
    }
}
