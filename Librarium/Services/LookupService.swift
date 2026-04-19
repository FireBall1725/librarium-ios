import Foundation

struct LookupService {
    let client: APIClient

    func isbn(_ isbn: String) async throws -> [ISBNLookupResult] {
        try await client.get("/api/v1/lookup/isbn/\(isbn)")
    }

    func series(query: String) async throws -> [SeriesLookupResult] {
        guard let enc = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        return try await client.get("/api/v1/lookup/series?q=\(enc)")
    }
}
