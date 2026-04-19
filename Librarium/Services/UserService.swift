import Foundation

struct UserService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func updateProfile(displayName: String, email: String) async throws -> User {
        struct Body: Encodable { let displayName: String; let email: String }
        return try await client.put(
            "/api/v1/auth/me",
            body: Body(displayName: displayName, email: email)
        )
    }

    func updatePassword(current: String, new: String) async throws {
        struct Body: Encodable { let currentPassword: String; let newPassword: String }
        struct Ack: Decodable { let message: String }
        let _: Ack = try await client.put(
            "/api/v1/auth/me/password",
            body: Body(currentPassword: current, newPassword: new)
        )
    }
}
