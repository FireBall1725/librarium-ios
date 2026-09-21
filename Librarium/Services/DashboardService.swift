import Foundation

/// Per-server dashboard endpoints (cross-library aggregation against the
/// caller's user). Mirrors the api router under `/api/v1/dashboard/*`.
struct DashboardService {
    let client: APIClient

    func currentlyReading() async throws -> [DashboardBook] {
        try await client.get("/api/v1/dashboard/currently-reading")
    }

    func recentlyFinished() async throws -> [DashboardBook] {
        try await client.get("/api/v1/dashboard/recently-finished")
    }

    func stats() async throws -> DashboardStats {
        try await client.get("/api/v1/dashboard/stats")
    }

    /// The next volume of a run you are partway through.
    func continueSeries() async throws -> [ContinueSeriesEntry] {
        try await client.get("/api/v1/dashboard/continue-series")
    }

    func recentlyAdded() async throws -> [DashboardBook] {
        try await client.get("/api/v1/dashboard/recently-added")
    }

    /// A handful of books the server picked today, so a shelf of 1,600 has a
    /// way of showing you the ones you forgot you owned.
    func picksOfTheDay() async throws -> [DashboardBook] {
        try await client.get("/api/v1/dashboard/picks-of-the-day")
    }
}

/// The next volume of a run, with enough of the run on it to say why it is
/// here: "you read 14, here is 15".
struct ContinueSeriesEntry: Decodable, Identifiable, Hashable {
    let seriesId: String
    let seriesName: String
    let position: Int
    let lastReadPosition: Int
    let bookId: String
    let libraryId: String
    let libraryName: String
    let title: String
    let authors: String
    let coverUrl: String?

    var serverURL: String = ""
    var serverName: String = ""

    var id: String { "\(serverURL)|\(bookId)" }

    enum CodingKeys: String, CodingKey {
        case seriesId, seriesName, position, lastReadPosition, bookId
        case libraryId, libraryName, title, authors, coverUrl
    }

    /// The same row shape the other rails draw, so one tile view serves all
    /// of them.
    var asBook: DashboardBook {
        var book = DashboardBook(
            bookId: bookId, libraryId: libraryId, libraryName: libraryName,
            title: title, coverUrl: coverUrl, authors: authors,
            readStatus: "", updatedAt: ""
        )
        book.serverURL = serverURL
        book.serverName = serverName
        return book
    }
}

/// Lightweight book row returned by the dashboard endpoints. Carries the
/// minimum needed to render a tile + navigate to detail (book_id +
/// library_id + cover URL). Authors is a pre-joined display string from
/// the api ("Tite Kubo" / "D. Thomas, A. Hunt").
struct DashboardBook: Codable, Identifiable, Hashable {
    let bookId: String
    let libraryId: String
    let libraryName: String
    let title: String
    let coverUrl: String?
    let authors: String
    let readStatus: String
    let updatedAt: String

    // Client-side only — stamped at fan-out time so each row carries its
    // source server. Lets the dashboard render covers from the book's own
    // server (rather than whichever account happens to be primary) and
    // route detail navigation back to the right api.
    var serverURL: String = ""
    var serverName: String = ""

    var id: String { "\(serverURL)|\(bookId)" }

    enum CodingKeys: String, CodingKey {
        case bookId, libraryId, libraryName, title, coverUrl, authors, readStatus, updatedAt
    }

    init(bookId: String, libraryId: String, libraryName: String, title: String,
         coverUrl: String?, authors: String, readStatus: String, updatedAt: String,
         serverURL: String = "", serverName: String = "") {
        self.serverURL = serverURL
        self.serverName = serverName
        self.bookId = bookId
        self.libraryId = libraryId
        self.libraryName = libraryName
        self.title = title
        self.coverUrl = coverUrl
        self.authors = authors
        self.readStatus = readStatus
        self.updatedAt = updatedAt
    }

    /// Written out because the rails do not all answer with the same fields:
    /// recently-added and picks-of-the-day carry no `updated_at`, and a
    /// required one there is what a synthesised decoder turns into an empty
    /// rail rather than an error (librarium-ios-022).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bookId = try c.decode(String.self, forKey: .bookId)
        libraryId = try c.decodeIfPresent(String.self, forKey: .libraryId) ?? ""
        libraryName = try c.decodeIfPresent(String.self, forKey: .libraryName) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        coverUrl = try c.decodeIfPresent(String.self, forKey: .coverUrl)
        authors = try c.decodeIfPresent(String.self, forKey: .authors) ?? ""
        readStatus = try c.decodeIfPresent(String.self, forKey: .readStatus) ?? ""
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }
}

struct DashboardStats: Codable {
    let totalBooks: Int
    let booksRead: Int
    let booksReading: Int
    let booksAddedThisYear: Int
    let booksReadThisYear: Int
    let favoritesCount: Int
    let monthlyReads: [MonthlyRead]
}

struct MonthlyRead: Codable, Hashable {
    let month: String  // "2026-04"
    let count: Int
}
