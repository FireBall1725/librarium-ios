import Foundation

struct ShelfService {
    let client: APIClient

    func list(libraryId: String) async throws -> [Shelf] {
        try await client.get("/api/v1/libraries/\(libraryId)/shelves")
    }

    func create(libraryId: String, body: ShelfBody) async throws -> Shelf {
        try await client.post("/api/v1/libraries/\(libraryId)/shelves", body: body)
    }

    func update(libraryId: String, shelfId: String, body: ShelfBody) async throws -> Shelf {
        try await client.put("/api/v1/libraries/\(libraryId)/shelves/\(shelfId)", body: body)
    }

    func delete(libraryId: String, shelfId: String) async throws {
        try await client.delete("/api/v1/libraries/\(libraryId)/shelves/\(shelfId)")
    }

    func books(libraryId: String, shelfId: String) async throws -> [Book] {
        try await client.get("/api/v1/libraries/\(libraryId)/shelves/\(shelfId)/books")
    }

    func addBook(libraryId: String, shelfId: String, bookId: String) async throws {
        struct Body: Encodable { let bookId: String }
        try await client.postVoid("/api/v1/libraries/\(libraryId)/shelves/\(shelfId)/books",
                                  body: Body(bookId: bookId))
    }

    func removeBook(libraryId: String, shelfId: String, bookId: String) async throws {
        try await client.delete("/api/v1/libraries/\(libraryId)/shelves/\(shelfId)/books/\(bookId)")
    }
}

struct ShelfBody: Encodable {
    var name: String
    var description: String = ""
    var color: String = "#6B7280"
    var icon: String = "📚"
    var tagIds: [String] = []
}
