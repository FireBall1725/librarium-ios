import Foundation

struct LookupService {
    let client: APIClient

    func isbn(_ isbn: String) async throws -> [ISBNLookupResult] {
        try await client.get("/api/v1/lookup/isbn/\(isbn)")
    }

    /// Free-text search across the server's providers, for a book whose
    /// barcode is missing or unreadable. Same result shape as an ISBN
    /// lookup, so a chosen row can go straight into the scan result screen.
    func books(query: String) async throws -> [ISBNLookupResult] {
        guard let enc = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        return try await client.get("/api/v1/lookup/books?q=\(enc)")
    }

    func series(query: String) async throws -> [SeriesLookupResult] {
        guard let enc = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        return try await client.get("/api/v1/lookup/series?q=\(enc)")
    }
}
