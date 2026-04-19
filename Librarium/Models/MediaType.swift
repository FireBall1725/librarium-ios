import Foundation

struct MediaType: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let displayName: String
}
