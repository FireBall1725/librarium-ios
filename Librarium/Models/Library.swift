import Foundation

struct Library: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let slug: String
    let ownerId: String
    let isPublic: Bool
    let createdAt: String
    let updatedAt: String

    // Client-side only — excluded from JSON
    var serverURL: String = ""
    var serverName: String = ""

    /// Unique identity across multi-server connections. The server-side `id` is a
    /// UUID, but two different Librarium servers can legitimately expose
    /// libraries with colliding UUIDs (e.g. both started from the same seed), so
    /// anything that maintains per-library client state (SwiftUI list identity,
    /// offline caches, per-library UserDefaults keys) must key on this instead.
    var clientKey: String { "\(serverURL)|\(id)" }

    enum CodingKeys: String, CodingKey {
        case id, name, description, slug, ownerId, isPublic, createdAt, updatedAt
    }
}

struct Paged<T: Decodable>: Decodable {
    let items: [T]
    let total: Int
    let page: Int
    let perPage: Int
}
