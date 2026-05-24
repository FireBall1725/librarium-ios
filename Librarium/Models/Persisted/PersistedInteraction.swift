import Foundation
import SwiftData

/// Local SwiftData mirror of a server-side `user_book_interactions` row.
///
/// Mirrors the server schema introduced in api migration 000018 +
/// 000019: per-field timestamps for the four most-contested soft fields
/// (rating, read_status, progress, is_favorite) plus row-level
/// `updated_at` and a `deleted_at` tombstone. The values get fed by the
/// sync delta endpoint (`GET /sync/changes`) and, in a later PR, written
/// out via the outbox (`POST /sync/apply`).
///
/// `serverAccountID` scopes rows to a single Librarium account so the
/// multi-server case (one user logged into self-hosted + Plus) shares a
/// single ModelContainer without rows colliding.
@Model
final class PersistedInteraction {
    /// Mirrors the server-side `user_book_interactions.id`. Marked
    /// unique so SwiftData can dedupe on inserts driven by sync ops.
    @Attribute(.unique) var id: UUID
    var serverAccountID: UUID
    var bookEditionID: UUID

    var rating: Int?
    var ratingUpdatedAt: Date?

    var readStatus: String
    var readStatusUpdatedAt: Date?

    /// Raw JSON bytes for the progress object. Decoded only when a
    /// surface needs it; sync passes them through as-is.
    var progressJSON: Data?
    var progressUpdatedAt: Date?

    var isFavorite: Bool
    var isFavoriteUpdatedAt: Date?

    /// Row-level updated_at. Bumped whenever any field is touched.
    /// Sync uses it as the cursor anchor.
    var updatedAt: Date

    /// Tombstone. Non-nil means the row is soft-deleted on the server;
    /// reads should filter it out.
    var deletedAt: Date?

    init(
        id: UUID,
        serverAccountID: UUID,
        bookEditionID: UUID,
        readStatus: String = "unread",
        isFavorite: Bool = false,
        updatedAt: Date
    ) {
        self.id = id
        self.serverAccountID = serverAccountID
        self.bookEditionID = bookEditionID
        self.readStatus = readStatus
        self.isFavorite = isFavorite
        self.updatedAt = updatedAt
    }
}
