import Foundation

struct SetupService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func status() async throws -> SetupStatus {
        try await client.get("/api/v1/setup/status")
    }

    func bootstrapAdmin(_ req: BootstrapAdminRequest) async throws -> AuthTokens {
        try await client.post("/api/v1/setup/admin", body: req)
    }
}
