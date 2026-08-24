import Foundation
import SwiftData

/// Local SwiftData mirror of the caller's reading state for a work.
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

    /// Which work this is about.
    ///
    /// Reading state belongs to the work, not to a printing: a reader who owns
    /// two editions of one book has one opinion of it, and asking which
    /// paperback they meant was a question with no answer.
    ///
    /// Optional only so the store migrates in place. A row written before this
    /// existed has none until the backfill fills it in from the edition below,
    /// and treating that as "not yet known" is what lets an install upgrade
    /// without losing anything queued offline.
    var bookID: UUID?

    /// The printing this row was keyed to before reading state moved to the
    /// work. Kept so the backfill has something to map from, and so a row
    /// written by an older build is still findable while it waits.
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
        bookID: UUID? = nil,
        readStatus: String = "unread",
        isFavorite: Bool = false,
        updatedAt: Date
    ) {
        self.id = id
        self.serverAccountID = serverAccountID
        self.bookEditionID = bookEditionID
        self.bookID = bookID
        self.readStatus = readStatus
        self.isFavorite = isFavorite
        self.updatedAt = updatedAt
    }
}
