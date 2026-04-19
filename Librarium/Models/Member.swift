import Foundation

struct LibraryMember: Codable, Identifiable {
    var id: String { userId }
    let userId: String
    let username: String
    let displayName: String
    let email: String
    let roleId: String
    let role: String
    let joinedAt: String
}
