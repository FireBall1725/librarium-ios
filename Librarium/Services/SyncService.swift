import Foundation
import SwiftData

/// Drives the sync delta loop for one server account.
///
/// On every call to `syncOnce`, the service:
///   1. Calls `GET /sync/changes?since=<cursor>&limit=<page>` against
///      the account's API client.
///   2. Applies each returned op to the local SwiftData store.
///   3. Advances the per-account cursor (persisted in `UserDefaults`)
///      so the next call only pulls newer ops.
///   4. Re-runs while the response indicates `has_more`.
///
/// v1 scope mirrors the server: user_book_interactions only. Ops that
/// reference an entity the local store doesn't have yet are skipped
/// (logged in DEBUG); a follow-up will backfill the store via the
/// existing per-resource endpoints so subsequent ops can land.
actor SyncService {
    private let api: APIClient
    private let serverAccountID: UUID
    private let modelContainer: ModelContainer
    private let userDefaults: UserDefaults

    /// Page size for `GET /sync/changes`. The server caps at 1000.
    private let pageLimit = 500

    init(
        api: APIClient,
        serverAccountID: UUID,
        modelContainer: ModelContainer,
        userDefaults: UserDefaults = .standard
    ) {
        self.api = api
        self.serverAccountID = serverAccountID
        self.modelContainer = modelContainer
        self.userDefaults = userDefaults
    }

    private var cursorKey: String { "sync.lastSyncedThrough.\(serverAccountID.uuidString)" }

    var lastSyncedThrough: Date {
        get { userDefaults.object(forKey: cursorKey) as? Date ?? .distantPast }
        set { userDefaults.set(newValue, forKey: cursorKey) }
    }

    /// Run one drain of the sync delta. Returns after the server reports
    /// `has_more: false`.
    func syncOnce() async throws {
        let context = ModelContext(modelContainer)
        let formatter = SyncTimestampFormatter.shared
        var since = lastSyncedThrough

        repeat {
            let sinceParam = formatter.string(from: since)
            let path = "/api/v1/sync/changes?since=\(sinceParam)&limit=\(pageLimit)"
            let resp: SyncChangesResponse = try await api.get(path)

            for op in resp.ops {
                applyOp(op, in: context)
            }
            try context.save()

            // Advance the cursor to the max updated_at in this page,
            // so the next iteration picks up where we left off even
            // mid-drain.
            if let maxOpTS = resp.ops.compactMap(\.updatedAtDate).max() {
                since = maxOpTS
            }

            if !resp.hasMore { break }
        } while true

        // Persist the final cursor; on next launch we resume from here.
        lastSyncedThrough = since

        #if DEBUG
        print("📥 [SyncService \(serverAccountID.uuidString.prefix(8))] synced through \(since)")
        #endif
    }

    /// Apply a single op to the local store. Best-effort: if the local
    /// row doesn't exist yet, the op is skipped (v1 limitation; the
    /// sync ops don't carry enough to upsert from scratch). When step
    /// 5.5 lands, existing endpoints will write rows in and subsequent
    /// ops will land cleanly.
    private func applyOp(_ op: SyncOp, in context: ModelContext) {
        guard op.entityType == "user_book_interaction" else {
            #if DEBUG
            print("📥 [SyncService] ignored unknown entity_type=\(op.entityType)")
            #endif
            return
        }

        let id = op.entityId
        let descriptor = FetchDescriptor<PersistedInteraction>(
            predicate: #Predicate { $0.id == id }
        )
        let row: PersistedInteraction?
        do {
            row = try context.fetch(descriptor).first
        } catch {
            #if DEBUG
            print("📥 [SyncService] fetch error for \(id): \(error)")
            #endif
            return
        }

        guard let row else {
            #if DEBUG
            print("📥 [SyncService] no local row for \(id); skipping (need backfill)")
            #endif
            return
        }

        guard let opTS = op.updatedAtDate else {
            #if DEBUG
            print("📥 [SyncService] unparsable updated_at: \(op.updatedAt)")
            #endif
            return
        }

        if op.isDeleted {
            if row.deletedAt == nil || row.deletedAt! < opTS {
                row.deletedAt = opTS
                row.updatedAt = opTS
            }
            return
        }

        switch op.field {
        case "rating":
            if row.ratingUpdatedAt == nil || row.ratingUpdatedAt! < opTS {
                row.rating = op.value?.intValue
                row.ratingUpdatedAt = opTS
                row.updatedAt = max(row.updatedAt, opTS)
            }
        case "read_status":
            if let s = op.value?.stringValue,
               row.readStatusUpdatedAt == nil || row.readStatusUpdatedAt! < opTS {
                row.readStatus = s
                row.readStatusUpdatedAt = opTS
                row.updatedAt = max(row.updatedAt, opTS)
            }
        case "is_favorite":
            if let b = op.value?.boolValue,
               row.isFavoriteUpdatedAt == nil || row.isFavoriteUpdatedAt! < opTS {
                row.isFavorite = b
                row.isFavoriteUpdatedAt = opTS
                row.updatedAt = max(row.updatedAt, opTS)
            }
        case "progress":
            if row.progressUpdatedAt == nil || row.progressUpdatedAt! < opTS {
                row.progressJSON = op.value?.encodedJSON()
                row.progressUpdatedAt = opTS
                row.updatedAt = max(row.updatedAt, opTS)
            }
        default:
            #if DEBUG
            print("📥 [SyncService] ignored field=\(op.field ?? "<nil>")")
            #endif
        }
    }
}
