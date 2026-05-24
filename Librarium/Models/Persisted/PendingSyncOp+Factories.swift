import Foundation

/// Convenience factories so call sites don't have to hand-marshal a
/// SyncJSONValue + JSONEncoder dance just to queue an outbox op.
extension PendingSyncOp {
    static func rating(
        serverAccountID: UUID,
        entityID: UUID,
        value: Int?,
        updatedAt: Date = Date()
    ) -> PendingSyncOp {
        let json = value.map { SyncJSONValue.int($0) } ?? .null
        return PendingSyncOp(
            serverAccountID: serverAccountID,
            entityType: "user_book_interaction",
            entityId: entityID,
            field: "rating",
            valueJSON: json.encodedJSON(),
            deleted: false,
            updatedAt: updatedAt
        )
    }

    static func readStatus(
        serverAccountID: UUID,
        entityID: UUID,
        value: String,
        updatedAt: Date = Date()
    ) -> PendingSyncOp {
        PendingSyncOp(
            serverAccountID: serverAccountID,
            entityType: "user_book_interaction",
            entityId: entityID,
            field: "read_status",
            valueJSON: SyncJSONValue.string(value).encodedJSON(),
            deleted: false,
            updatedAt: updatedAt
        )
    }

    static func isFavorite(
        serverAccountID: UUID,
        entityID: UUID,
        value: Bool,
        updatedAt: Date = Date()
    ) -> PendingSyncOp {
        PendingSyncOp(
            serverAccountID: serverAccountID,
            entityType: "user_book_interaction",
            entityId: entityID,
            field: "is_favorite",
            valueJSON: SyncJSONValue.bool(value).encodedJSON(),
            deleted: false,
            updatedAt: updatedAt
        )
    }

    static func progress(
        serverAccountID: UUID,
        entityID: UUID,
        value: SyncJSONValue?,
        updatedAt: Date = Date()
    ) -> PendingSyncOp {
        PendingSyncOp(
            serverAccountID: serverAccountID,
            entityType: "user_book_interaction",
            entityId: entityID,
            field: "progress",
            valueJSON: (value ?? .null).encodedJSON(),
            deleted: false,
            updatedAt: updatedAt
        )
    }

    static func tombstone(
        serverAccountID: UUID,
        entityID: UUID,
        updatedAt: Date = Date()
    ) -> PendingSyncOp {
        PendingSyncOp(
            serverAccountID: serverAccountID,
            entityType: "user_book_interaction",
            entityId: entityID,
            field: nil,
            valueJSON: nil,
            deleted: true,
            updatedAt: updatedAt
        )
    }
}
