import Foundation

struct ServerAccount: Identifiable {
    let id: UUID
    var name: String
    var url: String
    var accessToken: String
    var refreshToken: String
    var user: User

    static func defaultName(for url: String) -> String {
        guard let host = URL(string: url)?.host, !host.isEmpty else { return url }
        return host
    }
}

struct ServerAccountMeta: Codable {
    let id: UUID
    var name: String
    var url: String
    var user: User
}
