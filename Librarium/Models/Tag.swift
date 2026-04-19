import Foundation

struct Tag: Codable, Identifiable, Hashable {
    let id: String
    let libraryId: String
    let name: String
    let color: String
    let createdAt: String

    // Tags embedded in other responses (e.g. series) omit library_id / created_at
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(String.self, forKey: .id)
        name      = try c.decode(String.self, forKey: .name)
        color     = try c.decodeIfPresent(String.self, forKey: .color)     ?? "#6B7280"
        libraryId = try c.decodeIfPresent(String.self, forKey: .libraryId) ?? ""
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }
}
