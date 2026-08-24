import Foundation
import SwiftData

/// Bridges the api DTO `UserBookInteraction` into the local SwiftData
/// `PersistedInteraction` row.
///
/// Call this from any read path that fetches an interaction so that
/// subsequent `/sync/changes` ops can land on the row instead of being
/// skipped because the local store doesn't know about it yet.
///
/// Per-field timestamps on the row default to the row-level `updatedAt`
/// since the api doesn't yet emit per-field timestamps on its read
/// surfaces. That's accurate as a baseline: any op the sync pull
/// returns later has its own timestamp and will overtake whatever the
/// backfill set, exactly as last-write-wins intends.
enum SyncBackfill {
    /// - Parameter bookID: which work this is about. Passed in rather than read
    ///   off the DTO because the per-edition read surface does not carry it,
    ///   and the caller always knows the book it is showing.
    static func writeInteraction(
        _ dto: UserBookInteraction,
        serverAccountID: UUID,
        bookID: UUID? = nil,
        in context: ModelContext
    ) {
        guard let id = UUID(uuidString: dto.id),
              let bookEditionID = UUID(uuidString: dto.bookEditionId) else { return }

        let updatedAt = SyncTimestampFormatter.shared.date(from: dto.updatedAt) ?? Date()

        let descriptor = FetchDescriptor<PersistedInteraction>(
            predicate: #Predicate { $0.id == id }
        )
        var existing = (try? context.fetch(descriptor))?.first

        // Nothing under that id, but perhaps something under this book.
        //
        // The server minted new row ids when reading state moved to the work,
        // so a store written before the upgrade holds the old one. Inserting
        // alongside it would leave two rows for one book, and the view takes
        // whichever comes back first. Adopt the new id instead: the row keeps
        // its pending local edits and starts matching the ops the server sends.
        if existing == nil, let bookID {
            let byBook = FetchDescriptor<PersistedInteraction>(
                predicate: #Predicate<PersistedInteraction> {
                    $0.bookID == bookID && $0.id != id
                }
            )
            if let stale = (try? context.fetch(byBook))?.first {
                stale.id = id
                existing = stale
            }
        }

        if let row = existing {
            // Filled in on the way past. A row written by an older build has no
            // book, and this is the read that knows which one it is.
            if row.bookID == nil { row.bookID = bookID }
            applyInto(row, from: dto, updatedAt: updatedAt)
        } else {
            let row = PersistedInteraction(
                id: id,
                serverAccountID: serverAccountID,
                bookEditionID: bookEditionID,
                bookID: bookID,
                readStatus: dto.readStatus,
                isFavorite: dto.isFavorite,
                updatedAt: updatedAt
            )
            applyInto(row, from: dto, updatedAt: updatedAt)
            context.insert(row)
        }
    }

    private static func applyInto(
        _ row: PersistedInteraction,
        from dto: UserBookInteraction,
        updatedAt: Date
    ) {
        // Only overwrite a field if the local row hasn't been touched
        // more recently than the backfill timestamp. Protects pending
        // outbox-first edits (rated locally, not yet drained) from
        // getting overwritten by a stale api read.
        if (row.ratingUpdatedAt ?? .distantPast) <= updatedAt {
            row.rating = dto.rating.map { Int($0) }
            row.ratingUpdatedAt = updatedAt
        }
        if (row.readStatusUpdatedAt ?? .distantPast) <= updatedAt {
            row.readStatus = dto.readStatus
            row.readStatusUpdatedAt = updatedAt
        }
        if (row.isFavoriteUpdatedAt ?? .distantPast) <= updatedAt {
            row.isFavorite = dto.isFavorite
            row.isFavoriteUpdatedAt = updatedAt
        }
        // UserBookInteraction has no progress payload yet; leave the
        // progress columns alone.
        row.updatedAt = max(row.updatedAt, updatedAt)
    }
}
