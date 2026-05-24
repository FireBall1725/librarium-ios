import Foundation
import SwiftData

/// One queued outbox entry. Written by local mutation paths (rating
/// changes, status updates, tombstones, etc.) before they reach the
/// server, then drained by `SyncService.drainOutbox()` via
/// `POST /sync/apply`.
///
/// Rows clear on successful apply (server says applied or
/// discarded_stale — both mean the server's state reflects the
/// intended outcome). Terminal errors (not_found / invalid) also
/// clear; the local mutation that produced the op is the one that
/// has to learn from the response. Transient errors (network, 5xx)
/// leave the row in place for the next drain.
///
/// `serverAccountID` scopes ops to the server they should land on, so
/// the multi-server case routes drains to the right `/sync/apply`.
@Model
final class PendingSyncOp {
    /// Client-side op id. Mirrors the `op_id` field on the wire and
    /// lets the apply response correlate back to this row.
    @Attribute(.unique) var opId: UUID
    var serverAccountID: UUID

    var entityType: String
    var entityId: UUID

    /// Per-field LWW field name (rating, read_status, progress,
    /// is_favorite). Empty for tombstone or row-level ops.
    var field: String?

    /// Pre-encoded JSON bytes for the op's value. Decoded back into a
    /// SyncJSONValue when building the /sync/apply request. Nil means
    /// the field should be cleared (or the op is a tombstone).
    var valueJSON: Data?

    var deleted: Bool

    /// Client-side timestamp the field was changed at; the server uses
    /// it for LWW comparison.
    var updatedAt: Date

    /// When this op was queued locally. Drain reads outbox rows in
    /// createdAt order so older ops apply first.
    var createdAt: Date

    init(
        opId: UUID = UUID(),
        serverAccountID: UUID,
        entityType: String,
        entityId: UUID,
        field: String? = nil,
        valueJSON: Data? = nil,
        deleted: Bool = false,
        updatedAt: Date,
        createdAt: Date = Date()
    ) {
        self.opId = opId
        self.serverAccountID = serverAccountID
        self.entityType = entityType
        self.entityId = entityId
        self.field = field
        self.valueJSON = valueJSON
        self.deleted = deleted
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }
}
