import Foundation

struct MemberService {
    let client: APIClient

    func list(libraryId: String, search: String = "") async throws -> [LibraryMember] {
        var path = "/api/v1/libraries/\(libraryId)/members"
        if !search.isEmpty, let enc = search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "?search=\(enc)"
        }
        return try await client.get(path)
    }

    func add(libraryId: String, userId: String, roleId: String) async throws {
        struct Body: Encodable { let userId: String; let roleId: String }
        try await client.postVoid("/api/v1/libraries/\(libraryId)/members",
                                  body: Body(userId: userId, roleId: roleId))
    }

    func remove(libraryId: String, userId: String) async throws {
        try await client.delete("/api/v1/libraries/\(libraryId)/members/\(userId)")
    }

    func searchUsers(query: String) async throws -> [ContributorResult] {
        guard let enc = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        return try await client.get("/api/v1/users?q=\(enc)")
    }
}
