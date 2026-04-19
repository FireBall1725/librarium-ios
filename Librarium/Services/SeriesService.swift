import Foundation

struct SeriesService {
    let client: APIClient

    func list(libraryId: String) async throws -> [Series] {
        try await client.get("/api/v1/libraries/\(libraryId)/series")
    }

    func create(libraryId: String, body: SeriesBody) async throws -> Series {
        try await client.post("/api/v1/libraries/\(libraryId)/series", body: body)
    }

    func update(libraryId: String, seriesId: String, body: SeriesBody) async throws -> Series {
        try await client.put("/api/v1/libraries/\(libraryId)/series/\(seriesId)", body: body)
    }

    func delete(libraryId: String, seriesId: String) async throws {
        try await client.delete("/api/v1/libraries/\(libraryId)/series/\(seriesId)")
    }

    func books(libraryId: String, seriesId: String) async throws -> [SeriesEntry] {
        try await client.get("/api/v1/libraries/\(libraryId)/series/\(seriesId)/books")
    }

    func volumes(libraryId: String, seriesId: String) async throws -> [SeriesVolume] {
        try await client.get("/api/v1/libraries/\(libraryId)/series/\(seriesId)/volumes")
    }

    func addBook(libraryId: String, seriesId: String, bookId: String, position: Double) async throws {
        struct Body: Encodable { let bookId: String; let position: Double }
        try await client.postVoid("/api/v1/libraries/\(libraryId)/series/\(seriesId)/books",
                                  body: Body(bookId: bookId, position: position))
    }

    func removeBook(libraryId: String, seriesId: String, bookId: String) async throws {
        try await client.delete("/api/v1/libraries/\(libraryId)/series/\(seriesId)/books/\(bookId)")
    }
}

struct SeriesBody: Encodable {
    var name: String
    var description: String = ""
    var totalCount: Int? = nil
    var isComplete: Bool = false
    var status: String = ""
    var originalLanguage: String = ""
    var publicationYear: Int? = nil
    var demographic: String = ""
    var genres: [String] = []
    var url: String = ""
    var externalId: String = ""
    var externalSource: String = ""
    var tagIds: [String] = []
}
