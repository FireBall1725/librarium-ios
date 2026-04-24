import Foundation

// MARK: - Genre

struct Genre: Codable, Identifiable, Hashable {
    let id: String
    let name: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id   = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    }
}

// MARK: - Book

struct Book: Codable, Identifiable, Hashable {
    let id: String
    /// Nullable since the m2m refactor: a book can live in zero or more
    /// libraries (floating books backing AI suggestions; books shared across
    /// multiple libraries). Server emits `library_id: null` for floating
    /// books and a representative id otherwise — but iOS shouldn't depend
    /// on it being present.
    let libraryId: String
    let title: String
    let subtitle: String
    let mediaTypeId: String
    let mediaType: String
    let description: String
    let addedBy: String?
    let createdAt: String
    let updatedAt: String
    let contributors: [BookContributor]
    let tags: [Tag]
    let genres: [Genre]
    let coverUrl: String?
    let hasCover: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(String.self,   forKey: .id)
        libraryId    = try c.decodeIfPresent(String.self, forKey: .libraryId) ?? ""
        title        = try c.decode(String.self,   forKey: .title)
        subtitle     = try c.decodeIfPresent(String.self, forKey: .subtitle)    ?? ""
        mediaTypeId  = try c.decodeIfPresent(String.self, forKey: .mediaTypeId) ?? ""
        mediaType    = try c.decodeIfPresent(String.self, forKey: .mediaType)   ?? ""
        description  = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        addedBy      = try c.decodeIfPresent(String.self, forKey: .addedBy)
        createdAt    = try c.decode(String.self,   forKey: .createdAt)
        updatedAt    = try c.decode(String.self,   forKey: .updatedAt)
        contributors = try c.decodeIfPresent([BookContributor].self, forKey: .contributors) ?? []
        tags         = try c.decodeIfPresent([Tag].self,             forKey: .tags)         ?? []
        genres       = try c.decodeIfPresent([Genre].self,           forKey: .genres)       ?? []
        coverUrl     = try c.decodeIfPresent(String.self, forKey: .coverUrl)
        hasCover     = try c.decodeIfPresent(Bool.self,   forKey: .hasCover)    ?? false
    }
}

// MARK: - BookContributor

struct BookContributor: Codable, Hashable {
    let contributorId: String
    let name: String
    let role: String
    let displayOrder: Int
}

// MARK: - BookEdition

struct BookEdition: Codable, Identifiable, Hashable {
    let id: String
    let bookId: String
    let format: String
    let language: String
    let editionName: String
    let narrator: String
    let publisher: String
    let publishDate: String?
    let isbn10: String
    let isbn13: String
    let copyCount: Int
    let description: String
    let durationSeconds: Int?
    let pageCount: Int?
    let isPrimary: Bool
    let createdAt: String
    let updatedAt: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(String.self,   forKey: .id)
        bookId          = try c.decode(String.self,   forKey: .bookId)
        format          = try c.decodeIfPresent(String.self, forKey: .format)          ?? "physical"
        language        = try c.decodeIfPresent(String.self, forKey: .language)        ?? ""
        editionName     = try c.decodeIfPresent(String.self, forKey: .editionName)     ?? ""
        narrator        = try c.decodeIfPresent(String.self, forKey: .narrator)        ?? ""
        publisher       = try c.decodeIfPresent(String.self, forKey: .publisher)       ?? ""
        publishDate     = try c.decodeIfPresent(String.self, forKey: .publishDate)
        isbn10          = try c.decodeIfPresent(String.self, forKey: .isbn10)          ?? ""
        isbn13          = try c.decodeIfPresent(String.self, forKey: .isbn13)          ?? ""
        copyCount       = try c.decodeIfPresent(Int.self,    forKey: .copyCount)       ?? 1
        description     = try c.decodeIfPresent(String.self, forKey: .description)     ?? ""
        durationSeconds = try c.decodeIfPresent(Int.self,    forKey: .durationSeconds)
        pageCount       = try c.decodeIfPresent(Int.self,    forKey: .pageCount)
        isPrimary       = try c.decodeIfPresent(Bool.self,   forKey: .isPrimary)       ?? false
        createdAt       = try c.decode(String.self,   forKey: .createdAt)
        updatedAt       = try c.decode(String.self,   forKey: .updatedAt)
    }

    // isbn_10 / isbn_13 use underscores before digits — not a camelCase boundary,
    // so convertFromSnakeCase alone doesn't produce the right key. Explicit mapping required.
    enum CodingKeys: String, CodingKey {
        case id, bookId, format, language, editionName, narrator, publisher, publishDate
        case isbn10 = "isbn_10"
        case isbn13 = "isbn_13"
        case copyCount, description, durationSeconds, pageCount, isPrimary, createdAt, updatedAt
    }
}

// MARK: - BookSeriesRef

struct BookSeriesRef: Codable, Hashable {
    let seriesId: String
    let seriesName: String
    let position: Double
}

// MARK: - UserBookInteraction

struct UserBookInteraction: Codable, Identifiable {
    let id: String
    let userId: String
    let bookEditionId: String
    let readStatus: String
    let rating: Double?
    let notes: String
    let review: String
    let dateStarted: String?
    let dateFinished: String?
    let isFavorite: Bool
    let rereadCount: Int
    let createdAt: String
    let updatedAt: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(String.self,   forKey: .id)
        userId        = try c.decode(String.self,   forKey: .userId)
        bookEditionId = try c.decode(String.self,   forKey: .bookEditionId)
        readStatus    = try c.decodeIfPresent(String.self, forKey: .readStatus)  ?? "unread"
        rating        = try c.decodeIfPresent(Double.self, forKey: .rating)
        notes         = try c.decodeIfPresent(String.self, forKey: .notes)       ?? ""
        review        = try c.decodeIfPresent(String.self, forKey: .review)      ?? ""
        dateStarted   = try c.decodeIfPresent(String.self, forKey: .dateStarted)
        dateFinished  = try c.decodeIfPresent(String.self, forKey: .dateFinished)
        isFavorite    = try c.decodeIfPresent(Bool.self,   forKey: .isFavorite)  ?? false
        rereadCount   = try c.decodeIfPresent(Int.self,    forKey: .rereadCount) ?? 0
        createdAt     = try c.decode(String.self,   forKey: .createdAt)
        updatedAt     = try c.decode(String.self,   forKey: .updatedAt)
    }
}
