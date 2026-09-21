import Foundation

struct ContributorService {
    let client: APIClient

    func search(query: String) async throws -> [ContributorResult] {
        guard !query.isEmpty,
              let enc = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return [] }
        return try await client.get("/api/v1/contributors?q=\(enc)")
    }

    func create(name: String) async throws -> ContributorResult {
        struct Body: Encodable { let name: String }
        return try await client.post("/api/v1/contributors", body: Body(name: name))
    }
}
