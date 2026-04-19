import Foundation

struct MediaTypeService {
    let client: APIClient

    func list() async throws -> [MediaType] {
        try await client.get("/api/v1/media-types")
    }
}
