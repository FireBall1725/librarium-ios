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

    var id: String { bookId }
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
