import Foundation

struct LoanService {
    let client: APIClient

    /// The library's loans. Returned ones are left out unless asked for: the
    /// route's default is what is still out, which is what a badge wants and
    /// not what a history wants (librarium-ios-123).
    func list(libraryId: String, includeReturned: Bool = false) async throws -> [Loan] {
        let path = "/api/v1/libraries/\(libraryId)/loans"
        return try await client.get(includeReturned ? path + "?include_returned=true" : path)
    }

    func create(libraryId: String, body: LoanBody) async throws -> Loan {
        try await client.post("/api/v1/libraries/\(libraryId)/loans", body: body)
    }

    func update(libraryId: String, loanId: String, body: LoanUpdateBody) async throws -> Loan {
        try await client.patch("/api/v1/libraries/\(libraryId)/loans/\(loanId)", body: body)
    }

    func markReturned(libraryId: String, loanId: String) async throws -> Loan {
        struct Body: Encodable { let returnedAt: String }
        return try await client.patch(
            "/api/v1/libraries/\(libraryId)/loans/\(loanId)",
            body: Body(returnedAt: ISO8601DateFormatter().string(from: Date()))
        )
    }

    func delete(libraryId: String, loanId: String) async throws {
        try await client.delete("/api/v1/libraries/\(libraryId)/loans/\(loanId)")
    }
}

/// Loans dropped tags on 2026-04-27. The field is not sent and the response
/// does not carry one; a required `tags` on the model is what made every loan
/// fail to decode, including the one the sheet had just created
/// (librarium-ios-121).
struct LoanBody: Encodable {
    var bookId: String
    var loanedTo: String
    var loanedAt: String
    var dueDate: String?
    var notes: String = ""
}

struct LoanUpdateBody: Encodable {
    var loanedTo: String?
    var dueDate: String?
    var returnedAt: String?
    var notes: String?
    var tagIds: [String]?
}
