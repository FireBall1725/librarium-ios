import Foundation

struct BookService {
    let client: APIClient

    // MARK: - Books

    func list(
        libraryId: String,
        query: String = "",
        page: Int = 1,
        perPage: Int = 25,
        tag: String = "",
        typeFilter: String = "",
        letter: String = "",
        sort: String = "",
        sortDir: String = ""
    ) async throws -> Paged<Book> {
        var path = "/api/v1/libraries/\(libraryId)/books?page=\(page)&per_page=\(perPage)"
        if !query.isEmpty, let enc = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&q=\(enc)"
        }
        if !tag.isEmpty, let enc = tag.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&tag=\(enc)"
        }
        if !typeFilter.isEmpty, let enc = typeFilter.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&type_filter=\(enc)"
        }
        if !letter.isEmpty, let enc = letter.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&letter=\(enc)"
        }
        if !sort.isEmpty { path += "&sort=\(sort)" }
        if !sortDir.isEmpty { path += "&sort_dir=\(sortDir)" }
        return try await client.get(path)
    }

    func get(libraryId: String, bookId: String) async throws -> Book {
        try await client.get("/api/v1/libraries/\(libraryId)/books/\(bookId)")
    }

    func letters(libraryId: String) async throws -> [String] {
        try await client.get("/api/v1/libraries/\(libraryId)/books/letters")
    }

    func fingerprint(libraryId: String) async throws -> BookFingerprint {
        try await client.get("/api/v1/libraries/\(libraryId)/books/fingerprint")
    }

    func byISBN(libraryId: String, isbn: String) async throws -> Book {
        try await client.get("/api/v1/libraries/\(libraryId)/book-by-isbn/\(isbn)")
    }

    func create(libraryId: String, body: CreateBookRequest) async throws -> Book {
        try await client.post("/api/v1/libraries/\(libraryId)/books", body: body)
    }

    func update(libraryId: String, bookId: String, body: CreateBookRequest) async throws -> Book {
        try await client.put("/api/v1/libraries/\(libraryId)/books/\(bookId)", body: body)
    }

    func delete(libraryId: String, bookId: String) async throws {
        try await client.delete("/api/v1/libraries/\(libraryId)/books/\(bookId)")
    }

    // MARK: - Cover

    func uploadCover(libraryId: String, bookId: String, jpegData: Data) async throws {
        try await client.uploadMultipart(
            "/api/v1/libraries/\(libraryId)/books/\(bookId)/cover",
            fieldName: "cover",
            fileData: jpegData,
            fileName: "cover.jpg",
            mimeType: "image/jpeg"
        )
    }

    func deleteCover(libraryId: String, bookId: String) async throws {
        try await client.delete("/api/v1/libraries/\(libraryId)/books/\(bookId)/cover")
    }

    // MARK: - Editions

    func editions(libraryId: String, bookId: String) async throws -> [BookEdition] {
        try await client.get("/api/v1/libraries/\(libraryId)/books/\(bookId)/editions")
    }

    func createEdition(libraryId: String, bookId: String, body: CreateEditionRequest) async throws -> BookEdition {
        try await client.post("/api/v1/libraries/\(libraryId)/books/\(bookId)/editions", body: body)
    }

    func updateEdition(libraryId: String, bookId: String, editionId: String, body: CreateEditionRequest) async throws -> BookEdition {
        try await client.put("/api/v1/libraries/\(libraryId)/books/\(bookId)/editions/\(editionId)", body: body)
    }

    // MARK: - Interaction (reading status)

    func interaction(libraryId: String, bookId: String, editionId: String) async throws -> UserBookInteraction {
        try await client.get("/api/v1/libraries/\(libraryId)/books/\(bookId)/editions/\(editionId)/my-interaction")
    }

    func updateInteraction(libraryId: String, bookId: String, editionId: String, body: UpdateInteractionRequest) async throws -> UserBookInteraction {
        try await client.put("/api/v1/libraries/\(libraryId)/books/\(bookId)/editions/\(editionId)/my-interaction", body: body)
    }

    // MARK: - Book shelves / series

    func shelves(libraryId: String, bookId: String) async throws -> [Shelf] {
        try await client.get("/api/v1/libraries/\(libraryId)/books/\(bookId)/shelves")
    }

    func seriesRefs(libraryId: String, bookId: String) async throws -> [BookSeriesRef] {
        try await client.get("/api/v1/libraries/\(libraryId)/books/\(bookId)/series")
    }
}

// MARK: - Book → request conversion (book-level fields only; no edition)

extension Book {
    func toUpdateRequest() -> CreateBookRequest {
        CreateBookRequest(
            title: title,
            subtitle: subtitle,
            mediaTypeId: mediaTypeId,
            description: description,
            contributors: contributors
                .sorted { $0.displayOrder < $1.displayOrder }
                .map { ContributorInput(contributorId: $0.contributorId, role: $0.role, displayOrder: $0.displayOrder) },
            tagIds: tags.map(\.id),
            genreIds: genres.map(\.id)
        )
    }
}

// MARK: - Request bodies

struct CreateBookRequest: Encodable {
    var title: String
    var subtitle: String = ""
    var mediaTypeId: String = ""
    var description: String = ""
    var contributors: [ContributorInput] = []
    var tagIds: [String] = []
    var genreIds: [String] = []
    /// Inline edition — included on create; omit (nil) when updating book-level fields only.
    var edition: CreateEditionRequest? = nil
}

struct ContributorInput: Encodable {
    let contributorId: String
    let role: String
    let displayOrder: Int
}

struct CreateEditionRequest: Encodable {
    var format: String = "physical"
    var language: String = ""
    var editionName: String = ""
    var narrator: String = ""
    var publisher: String = ""
    var publishDate: String? = nil
    var isbn10: String = ""
    var isbn13: String = ""
    var description: String = ""
    var pageCount: Int? = nil
    var copyCount: Int? = nil
    var isPrimary: Bool = true

    // isbn_10 / isbn_13 need explicit keys — convertToSnakeCase won't add underscore before digits.
    enum CodingKeys: String, CodingKey {
        case format, language
        case editionName  = "edition_name"
        case narrator, publisher
        case publishDate  = "publish_date"
        case isbn10       = "isbn_10"
        case isbn13       = "isbn_13"
        case description
        case pageCount    = "page_count"
        case copyCount    = "copy_count"
        case isPrimary    = "is_primary"
    }
}

struct UpdateInteractionRequest: Encodable {
    var readStatus: String
    var rating: Double?
    var notes: String
    var review: String
    var dateStarted: String?
    var dateFinished: String?
    var isFavorite: Bool
}
