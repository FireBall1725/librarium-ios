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

    // MARK: - Library browser

    func listForLibrary(
        libraryId: String,
        query: String = "",
        letter: String = "",
        page: Int = 1,
        perPage: Int = 25
    ) async throws -> Paged<LibraryContributor> {
        var path = "/api/v1/libraries/\(libraryId)/contributors?page=\(page)&per_page=\(perPage)"
        if !query.isEmpty, let enc = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&q=\(enc)"
        }
        if !letter.isEmpty, let enc = letter.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&letter=\(enc)"
        }
        return try await client.get(path)
    }

    func get(libraryId: String, contributorId: String) async throws -> ContributorDetail {
        try await client.get("/api/v1/libraries/\(libraryId)/contributors/\(contributorId)")
    }
}
