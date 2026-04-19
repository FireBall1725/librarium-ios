import Foundation

struct AdminUser: Codable, Identifiable {
    let id: String
    let username: String
    let email: String
    let displayName: String
    let isInstanceAdmin: Bool
    let isActive: Bool
    let createdAt: String
    let lastLoginAt: String?
}

struct ProviderStatus: Codable, Identifiable {
    var id: String { name }
    let name: String
    let displayName: String
    let description: String
    let requiresKey: Bool
    let capabilities: [String]
    let helpText: String?
    let helpUrl: String?
    let enabled: Bool
    let hasApiKey: Bool
}
