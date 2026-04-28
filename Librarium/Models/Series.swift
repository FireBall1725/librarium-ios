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
    /// First 4 books in the series — used by the redesigned series-list
    /// mosaic to render an auto-generated "series cover" from the
    /// volumes inside. The api already pre-builds the cover URLs.
    let previewBooks: [SeriesPreviewBook]

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
        previewBooks = try c.decodeIfPresent([SeriesPreviewBook].self, forKey: .previewBooks) ?? []
    }
}

/// Trimmed book shape returned alongside `Series` for cover-mosaic
/// rendering: just enough to tile a 2×2 grid in the series list.
struct SeriesPreviewBook: Codable, Identifiable, Hashable {
    let bookId: String
    let title: String
    /// Pre-built relative URL the api emits when the book has a primary
    /// cover image. nil → fall back to the gradient placeholder tile.
    let coverUrl: String?

    var id: String { bookId }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bookId   = try c.decode(String.self, forKey: .bookId)
        title    = try c.decodeIfPresent(String.self, forKey: .title)    ?? ""
        coverUrl = try c.decodeIfPresent(String.self, forKey: .coverUrl)
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
    /// Arc this entry belongs to, if any. nil = entry is not assigned to an arc.
    let arcId: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        position     = try c.decode(Double.self, forKey: .position)
        bookId       = try c.decode(String.self, forKey: .bookId)
        title        = try c.decode(String.self, forKey: .title)
        subtitle     = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        mediaType    = try c.decodeIfPresent(String.self, forKey: .mediaType) ?? ""
        contributors = try c.decodeIfPresent([BookContributor].self, forKey: .contributors) ?? []
        arcId        = try c.decodeIfPresent(String.self, forKey: .arcId)
    }
}

/// Named sub-grouping within a series (e.g. "Wano Country Saga"). Each
/// arc carries optional vol_start / vol_end bounds the UI uses to render
/// the range label and place ghost rows for missing volumes.
struct SeriesArc: Codable, Identifiable {
    let id: String
    let seriesId: String
    let name: String
    let description: String
    let position: Double
    let volStart: Double?
    let volEnd: Double?
    let bookCount: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(String.self, forKey: .id)
        seriesId    = try c.decode(String.self, forKey: .seriesId)
        name        = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        position    = try c.decodeIfPresent(Double.self, forKey: .position) ?? 0
        volStart    = try c.decodeIfPresent(Double.self, forKey: .volStart)
        volEnd      = try c.decodeIfPresent(Double.self, forKey: .volEnd)
        bookCount   = try c.decodeIfPresent(Int.self,    forKey: .bookCount) ?? 0
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
