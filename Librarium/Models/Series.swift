import Foundation

struct Series: Codable, Identifiable, Hashable {
    let id: String
    let libraryId: String
    let name: String
    let description: String
    let totalCount: Int?
    let isComplete: Bool
    let status: String
    let originalLanguage: String
    let publicationYear: Int?
    let demographic: String
    let genres: [String]
    let url: String
    let externalId: String
    let externalSource: String
    let lastReleaseDate: String?
    let nextReleaseDate: String?
    let bookCount: Int
    let tags: [Tag]
    let createdAt: String
    let updatedAt: String

    // Custom decoder: Go nil slices serialize as null, and optional string fields
    // may be absent entirely (omitempty) or null (pointer types). Fall back to
    // sensible defaults so a single missing field doesn't kill the whole response.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(String.self,  forKey: .id)
        libraryId       = try c.decode(String.self,  forKey: .libraryId)
        name            = try c.decode(String.self,  forKey: .name)
        isComplete      = try c.decodeIfPresent(Bool.self,   forKey: .isComplete)      ?? false
        bookCount       = try c.decodeIfPresent(Int.self,    forKey: .bookCount)        ?? 0
        createdAt       = try c.decode(String.self,  forKey: .createdAt)
        updatedAt       = try c.decode(String.self,  forKey: .updatedAt)
        description     = try c.decodeIfPresent(String.self, forKey: .description)     ?? ""
        status          = try c.decodeIfPresent(String.self, forKey: .status)          ?? ""
        originalLanguage = try c.decodeIfPresent(String.self, forKey: .originalLanguage) ?? ""
        demographic     = try c.decodeIfPresent(String.self, forKey: .demographic)     ?? ""
        url             = try c.decodeIfPresent(String.self, forKey: .url)             ?? ""
        externalId      = try c.decodeIfPresent(String.self, forKey: .externalId)      ?? ""
        externalSource  = try c.decodeIfPresent(String.self, forKey: .externalSource)  ?? ""
        totalCount      = try c.decodeIfPresent(Int.self,    forKey: .totalCount)
        publicationYear = try c.decodeIfPresent(Int.self,    forKey: .publicationYear)
        lastReleaseDate = try c.decodeIfPresent(String.self, forKey: .lastReleaseDate)
        nextReleaseDate = try c.decodeIfPresent(String.self, forKey: .nextReleaseDate)
        // nil slices in Go → null in JSON → decode as empty array
        genres = try c.decodeIfPresent([String].self, forKey: .genres) ?? []
        tags   = try c.decodeIfPresent([Tag].self,    forKey: .tags)   ?? []
    }
}

struct SeriesEntry: Codable, Identifiable {
    var id: String { bookId }
    let position: Double
    let bookId: String
    let title: String
    let subtitle: String
    let mediaType: String
    let contributors: [BookContributor]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        position     = try c.decode(Double.self, forKey: .position)
        bookId       = try c.decode(String.self, forKey: .bookId)
        title        = try c.decode(String.self, forKey: .title)
        subtitle     = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        mediaType    = try c.decodeIfPresent(String.self, forKey: .mediaType) ?? ""
        contributors = try c.decodeIfPresent([BookContributor].self, forKey: .contributors) ?? []
    }
}

struct SeriesVolume: Codable, Identifiable {
    let id: String
    let seriesId: String
    let position: Double
    let title: String
    let releaseDate: String?
    let coverUrl: String
    let externalId: String
    let createdAt: String
    let updatedAt: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(String.self, forKey: .id)
        seriesId   = try c.decode(String.self, forKey: .seriesId)
        position   = try c.decode(Double.self, forKey: .position)
        title      = try c.decodeIfPresent(String.self, forKey: .title)      ?? ""
        releaseDate = try c.decodeIfPresent(String.self, forKey: .releaseDate)
        coverUrl   = try c.decodeIfPresent(String.self, forKey: .coverUrl)   ?? ""
        externalId = try c.decodeIfPresent(String.self, forKey: .externalId) ?? ""
        createdAt  = try c.decode(String.self, forKey: .createdAt)
        updatedAt  = try c.decode(String.self, forKey: .updatedAt)
    }
}
