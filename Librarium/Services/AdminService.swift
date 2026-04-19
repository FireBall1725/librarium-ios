import Foundation

struct AdminService {
    let client: APIClient

    // MARK: - Users

    func users(page: Int = 1, perPage: Int = 20) async throws -> Paged<AdminUser> {
        try await client.get("/api/v1/admin/users?page=\(page)&per_page=\(perPage)")
    }

    func createUser(username: String, email: String, displayName: String, password: String) async throws -> AdminUser {
        struct Body: Encodable { let username, email, displayName, password: String }
        return try await client.post("/api/v1/admin/users",
                                     body: Body(username: username, email: email,
                                                displayName: displayName, password: password))
    }

    func setActive(userId: String, isActive: Bool) async throws -> AdminUser {
        struct Body: Encodable { let isActive: Bool }
        return try await client.patch("/api/v1/admin/users/\(userId)", body: Body(isActive: isActive))
    }

    func deleteUser(userId: String) async throws {
        try await client.delete("/api/v1/admin/users/\(userId)")
    }

    // MARK: - Providers

    func providers() async throws -> [ProviderStatus] {
        try await client.get("/api/v1/admin/providers")
    }

    func updateProvider(name: String, enabled: Bool, apiKey: String?) async throws -> [ProviderStatus] {
        struct Body: Encodable { let enabled: Bool; let apiKey: String? }
        return try await client.put("/api/v1/admin/providers/\(name)",
                                    body: Body(enabled: enabled, apiKey: apiKey))
    }
}
