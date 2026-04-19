import Foundation

struct LibraryService {
    let client: APIClient

    func list() async throws -> [Library] {
        try await client.get("/api/v1/libraries")
    }

    func get(_ id: String) async throws -> Library {
        try await client.get("/api/v1/libraries/\(id)")
    }

    func create(name: String, description: String, isPublic: Bool) async throws -> Library {
        struct Body: Encodable { let name: String; let description: String; let isPublic: Bool }
        return try await client.post("/api/v1/libraries", body: Body(name: name, description: description, isPublic: isPublic))
    }

    func update(libraryId: String, name: String, description: String, isPublic: Bool) async throws -> Library {
        struct Body: Encodable { let name: String; let description: String; let isPublic: Bool }
        return try await client.put("/api/v1/libraries/\(libraryId)", body: Body(name: name, description: description, isPublic: isPublic))
    }
}
