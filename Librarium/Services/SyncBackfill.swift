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
    static func writeInteraction(
        _ dto: UserBookInteraction,
        serverAccountID: UUID,
        in context: ModelContext
    ) {
        guard let id = UUID(uuidString: dto.id),
              let bookEditionID = UUID(uuidString: dto.bookEditionId) else { return }

        let updatedAt = SyncTimestampFormatter.shared.date(from: dto.updatedAt) ?? Date()

        let descriptor = FetchDescriptor<PersistedInteraction>(
            predicate: #Predicate { $0.id == id }
        )
        let existing = (try? context.fetch(descriptor))?.first

        if let row = existing {
            applyInto(row, from: dto, updatedAt: updatedAt)
        } else {
            let row = PersistedInteraction(
                id: id,
                serverAccountID: serverAccountID,
                bookEditionID: bookEditionID,
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
