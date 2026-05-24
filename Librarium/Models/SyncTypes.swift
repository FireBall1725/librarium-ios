import Foundation

/// Wire-shape DTOs for the sync delta endpoint. Mirrors
/// `responses.SyncChangesResponse` / `responses.SyncOp` in librarium-api.

struct SyncChangesResponse: Decodable {
    let ops: [SyncOp]
    let serverTime: String
    let hasMore: Bool
}

struct SyncOp: Decodable {
    let entityType: String
    let entityId: UUID
    let field: String?
    let value: SyncJSONValue?
    let deleted: Bool?
    /// RFC3339 timestamp; parse via `updatedAtDate` to compare locally.
    let updatedAt: String

    var isDeleted: Bool { deleted == true }

    var updatedAtDate: Date? {
        SyncTimestampFormatter.shared.date(from: updatedAt)
    }
}

/// A loose JSON value carried in `SyncOp.value`. Field shape depends on
/// the field name (rating is int, read_status is string, progress is an
/// object, is_favorite is bool); apply logic switches on the field
/// rather than over-constraining the type here.
enum SyncJSONValue: Decodable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([SyncJSONValue])
    case object([String: SyncJSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? c.decode(Int.self) {
            self = .int(v)
        } else if let v = try? c.decode(Double.self) {
            self = .double(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else if let v = try? c.decode([SyncJSONValue].self) {
            self = .array(v)
        } else if let v = try? c.decode([String: SyncJSONValue].self) {
            self = .object(v)
        } else {
            throw DecodingError.dataCorruptedError(
                in: c,
                debugDescription: "Unsupported JSON value in sync op"
            )
        }
    }

    /// Re-encode to compact JSON Data. Used to round-trip the progress
    /// blob back into its JSONB column on the local model.
    func encodedJSON() -> Data? {
        let encoder = JSONEncoder()
        return try? encoder.encode(self)
    }

    var intValue: Int? {
        if case .int(let v) = self { return v }
        if case .double(let v) = self { return Int(v) }
        return nil
    }

    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }
}

extension SyncJSONValue: Encodable {
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

/// Cached ISO8601 formatter for sync timestamps. The api emits
/// fractional seconds; we keep them when parsing so per-microsecond LWW
/// comparisons stay precise.
enum SyncTimestampFormatter {
    static let shared: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
