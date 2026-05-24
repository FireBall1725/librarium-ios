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

    /// Push any queued outbox ops, then drain the sync delta.
    /// Push-then-pull is the conventional order: we send our local
    /// mutations first so the server applies them, then pull any
    /// remaining server-side changes (including the canonical state
    /// of fields the server may have overridden via LWW).
    func syncOnce() async throws {
        try await drainOutbox()
        try await pullChanges()
    }

    /// Drain the sync delta until the server reports `has_more: false`.
    func pullChanges() async throws {
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

    /// Push every queued `PendingSyncOp` for this account to
    /// `POST /sync/apply` in batches, then clear the ops the server
    /// acknowledged (applied / discarded_stale / not_found / invalid).
    /// Transient errors leave the rows in place for the next drain.
    func drainOutbox() async throws {
        let context = ModelContext(modelContainer)
        let accountID = serverAccountID

        while true {
            let descriptor = FetchDescriptor<PendingSyncOp>(
                predicate: #Predicate { $0.serverAccountID == accountID },
                sortBy: [SortDescriptor(\.createdAt, order: .forward)]
            )
            // Cap each request at the server's batch limit.
            var fetch = descriptor
            fetch.fetchLimit = pageLimit
            let pending = try context.fetch(fetch)
            if pending.isEmpty { break }

            let formatter = SyncTimestampFormatter.shared
            let opRequests: [SyncApplyOpRequest] = pending.map { row in
                let value: SyncJSONValue?
                if let data = row.valueJSON,
                   let decoded = try? JSONDecoder().decode(SyncJSONValue.self, from: data) {
                    value = decoded
                } else {
                    value = nil
                }
                return SyncApplyOpRequest(
                    opId: row.opId,
                    entityType: row.entityType,
                    entityId: row.entityId,
                    field: row.field,
                    value: value,
                    deleted: row.deleted ? true : nil,
                    updatedAt: formatter.string(from: row.updatedAt)
                )
            }

            let req = SyncApplyRequest(clientId: nil, ops: opRequests)
            let resp: SyncApplyResponse = try await api.post("/api/v1/sync/apply", body: req)

            // Index results by op_id so we can clear the right rows.
            let resultsByOp = Dictionary(uniqueKeysWithValues: resp.results.map { ($0.opId, $0) })
            for row in pending {
                guard let result = resultsByOp[row.opId] else {
                    // Server didn't return a result for this op; leave
                    // queued and try next drain.
                    continue
                }
                switch result.status {
                case SyncApplyStatus.applied,
                     SyncApplyStatus.discardedStale,
                     SyncApplyStatus.notFound,
                     SyncApplyStatus.invalid:
                    context.delete(row)
                case SyncApplyStatus.error:
                    #if DEBUG
                    print("📤 [SyncService] op \(row.opId) errored: \(result.error ?? "<no detail>"); leaving queued")
                    #endif
                default:
                    #if DEBUG
                    print("📤 [SyncService] op \(row.opId) unknown status \(result.status); leaving queued")
                    #endif
                }
            }
            try context.save()

            // If the server didn't ack everything we sent (rare),
            // break so we don't loop forever on transient errors.
            if pending.count == pageLimit { continue }
            break
        }
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
