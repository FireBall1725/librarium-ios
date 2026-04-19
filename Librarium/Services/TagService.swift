import Foundation

struct TagService {
    let client: APIClient

    func list(libraryId: String) async throws -> [Tag] {
        try await client.get("/api/v1/libraries/\(libraryId)/tags")
    }

    func create(libraryId: String, name: String, color: String) async throws -> Tag {
        struct Body: Encodable { let name: String; let color: String }
        return try await client.post("/api/v1/libraries/\(libraryId)/tags",
                                     body: Body(name: name, color: color))
    }
}
