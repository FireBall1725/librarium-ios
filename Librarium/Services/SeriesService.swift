import Foundation

struct SeriesService {
    let client: APIClient

    /// One library's runs, asked for through the person-scoped index.
    ///
    /// `/libraries/{id}/series` is a read path the tier API retires, so this
    /// narrows the index by `lib` instead (librarium-ios-011). `volumes=1` is
    /// the smallest strip the endpoint will build: the callers here cache the
    /// run or match its name, and neither draws a cover.
    func list(libraryId: String) async throws -> [Series] {
        do {
            let page: SeriesIndexPage =
                try await client.get("/api/v1/me/series/index?lib=\(libraryId)&volumes=1")
            return page.items
        } catch APIError.notFound {
            throw MeBrowseError.serverTooOld(server: client.baseURL)
        }
    }

    func get(libraryId: String, seriesId: String) async throws -> Series {
        try await client.get("/api/v1/libraries/\(libraryId)/series/\(seriesId)")
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

    func arcs(libraryId: String, seriesId: String) async throws -> [SeriesArc] {
        try await client.get("/api/v1/libraries/\(libraryId)/series/\(seriesId)/arcs")
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
