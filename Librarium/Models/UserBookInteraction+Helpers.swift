import Foundation

extension UserBookInteraction {
    /// Memberwise init. The struct's existing `init(from decoder:)`
    /// suppresses Swift's auto-generated memberwise init; this explicit
    /// version lets call sites build optimistic copies (used by the
    /// outbox path while a /sync/apply push is in flight).
    init(
        id: String,
        userId: String,
        bookEditionId: String,
        readStatus: String,
        rating: Double?,
        notes: String,
        review: String,
        dateStarted: String?,
        dateFinished: String?,
        isFavorite: Bool,
        rereadCount: Int,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.userId = userId
        self.bookEditionId = bookEditionId
        self.readStatus = readStatus
        self.rating = rating
        self.notes = notes
        self.review = review
        self.dateStarted = dateStarted
        self.dateFinished = dateFinished
        self.isFavorite = isFavorite
        self.rereadCount = rereadCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Copy with `isFavorite` overridden. `updatedAt` becomes the new
    /// row timestamp so per-field LWW comparisons on the server reject
    /// any stale write that races us.
    func with(isFavorite: Bool, updatedAt: String) -> UserBookInteraction {
        UserBookInteraction(
            id: id,
            userId: userId,
            bookEditionId: bookEditionId,
            readStatus: readStatus,
            rating: rating,
            notes: notes,
            review: review,
            dateStarted: dateStarted,
            dateFinished: dateFinished,
            isFavorite: isFavorite,
            rereadCount: rereadCount,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// Copy with `rating` overridden. Pass nil to clear.
    func with(rating: Double?, updatedAt: String) -> UserBookInteraction {
        UserBookInteraction(
            id: id,
            userId: userId,
            bookEditionId: bookEditionId,
            readStatus: readStatus,
            rating: rating,
            notes: notes,
            review: review,
            dateStarted: dateStarted,
            dateFinished: dateFinished,
            isFavorite: isFavorite,
            rereadCount: rereadCount,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
