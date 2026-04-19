import Foundation

struct SetupStatus: Decodable {
    let initialized: Bool
}

struct BootstrapAdminRequest: Encodable {
    let username: String
    let email: String
    let displayName: String
    let password: String
}
