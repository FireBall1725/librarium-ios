import Foundation

struct User: Codable {
    let id: String
    let username: String
    let email: String
    let displayName: String
    let isInstanceAdmin: Bool
}
