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
    /// Volumes the collection holds, counted by distinct position rather than
    /// by book row. A complete 56-volume run plus one three-in-one is 56
    /// volumes, not 57, and an anniversary reprint beside the standard edition
    /// is one volume held twice.
    let bookCount: Int
    /// How long the run is, when anybody knows. nil is not zero: it means the
    /// length is unknown, and `missingCount` has to stay silent rather than
    /// claim nothing is missing.
    let readCount: Int
    let readingCount: Int
    let arcCount: Int
    /// Averaged over the volumes anyone has rated, in whole points where two
    /// points are one star. nil when nothing in the run is rated, which is a
    /// different thing from a rating of nought.
    let rating: Int?
    let ratedBooks: Int
    let myRating: Int?
    let tags: [Tag]
    let createdAt: String
    let updatedAt: String
    /// First 4 books in the series — used by the redesigned series-list
    /// mosaic to render an auto-generated "series cover" from the
    /// volumes inside. The api already pre-builds the cover URLs.
    let previewBooks: [SeriesPreviewBook]

    /// Volumes nobody has, when the run's length is known.
    ///
    /// Computed rather than sent, because it is a subtraction the server has
    /// already made for its own sort and there is nothing to gain by making the
    /// client wonder which of two numbers to take away from the other.
    var missingCount: Int? {
        guard let total = totalCount, total > 0 else { return nil }
        return max(0, total - bookCount)
    }

    /// Stars out of five with halves, from the stored ten-point scale.
    var ratingStars: Double? {
        guard let rating, rating > 0 else { return nil }
        return Double(rating) / 2
    }

    // Custom decoder: Go nil slices serialize as null, and optional string fields
    // may be absent entirely (omitempty) or null (pointer types). Fall back to
    // sensible defaults so a single missing field doesn't kill the whole response.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(String.self,  forKey: .id)
        // Not `decode`. The cross-library index answers for runs the caller
        // can read, and a run whose library the caller only reaches through a
        // shared list arrives without one.
        libraryId       = try c.decodeIfPresent(String.self, forKey: .libraryId) ?? ""
        name            = try c.decode(String.self,  forKey: .name)
        isComplete      = try c.decodeIfPresent(Bool.self,   forKey: .isComplete)      ?? false
        bookCount       = try c.decodeIfPresent(Int.self,    forKey: .bookCount)        ?? 0
        readCount       = try c.decodeIfPresent(Int.self,    forKey: .readCount)        ?? 0
        readingCount    = try c.decodeIfPresent(Int.self,    forKey: .readingCount)     ?? 0
        arcCount        = try c.decodeIfPresent(Int.self,    forKey: .arcCount)         ?? 0
        rating          = try c.decodeIfPresent(Int.self,    forKey: .rating)
        ratedBooks      = try c.decodeIfPresent(Int.self,    forKey: .ratedBooks)       ?? 0
        myRating        = try c.decodeIfPresent(Int.self,    forKey: .myRating)
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
    /// The last position a container covers. An omnibus of one to three sits at
    /// one and spans to three rather than occupying a position of its own, so
    /// the run reads 1-3, 4, 5 instead of listing two volume ones.
    let positionEnd: Double?
    let bookId: String
    var title: String
    let subtitle: String
    let mediaType: String
    let contributors: [BookContributor]
    /// Arc this entry belongs to, if any. nil = entry is not assigned to an arc.
    let arcId: String?
    /// Whether any library holds this volume, or holds something that contains
    /// it. A run lists its whole length, gaps included, so this is what tells
    /// a volume on the shelf from one that is only known to exist.
    let held: Bool
    let userReadStatus: String
    let coverUrl: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        position     = try c.decode(Double.self, forKey: .position)
        positionEnd  = try c.decodeIfPresent(Double.self, forKey: .positionEnd)
        bookId       = try c.decode(String.self, forKey: .bookId)
        title        = try c.decode(String.self, forKey: .title)
        subtitle     = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        mediaType    = try c.decodeIfPresent(String.self, forKey: .mediaType) ?? ""
        contributors = try c.decodeIfPresent([BookContributor].self, forKey: .contributors) ?? []
        arcId        = try c.decodeIfPresent(String.self, forKey: .arcId)
        // Defaults to held. An older server does not send the field at all, and
        // reading its silence as "nobody has this" would grey out an entire
        // collection.
        held         = try c.decodeIfPresent(Bool.self, forKey: .held) ?? true
        userReadStatus = try c.decodeIfPresent(String.self, forKey: .userReadStatus) ?? ""
        coverUrl     = try c.decodeIfPresent(String.self, forKey: .coverUrl)
    }

    /// Stands in for an entry an older server did not send, so a page built
    /// around entries keeps working against one that only knows about books.
    static func placeholder(bookId: String, title: String, position: Double) -> SeriesEntry {
        let json = Data("""
        {"position":\(position),"book_id":"\(bookId)","title":"","held":true}
        """.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        // Force-decoding a literal this file wrote is not the same risk as
        // force-decoding a response: the only way it fails is a typo above,
        // which every run would hit.
        var entry = try! decoder.decode(SeriesEntry.self, from: json)
        entry.title = title
        return entry
    }

    /// 3 rather than 3.0, 4.5 kept, and a container written as its span.
    var positionLabel: String {
        func one(_ v: Double) -> String {
            v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
        }
        if let end = positionEnd, end > position { return one(position) + "-" + one(end) }
        return one(position)
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
