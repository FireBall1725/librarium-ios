import Foundation

struct AuthService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func login(identifier: String, password: String) async throws -> AuthTokens {
        try await client.post(
            "/api/v1/auth/login",
            body: LoginRequest(identifier: identifier, password: password)
        )
    }

    func logout() async throws {
        try await client.postVoid("/api/v1/auth/logout")
    }
}
