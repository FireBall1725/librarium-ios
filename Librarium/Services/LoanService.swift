import Foundation

struct LoanService {
    let client: APIClient

    func list(libraryId: String) async throws -> [Loan] {
        try await client.get("/api/v1/libraries/\(libraryId)/loans")
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

struct LoanBody: Encodable {
    var bookId: String
    var loanedTo: String
    var loanedAt: String
    var dueDate: String?
    var notes: String = ""
    var tagIds: [String] = []
}

struct LoanUpdateBody: Encodable {
    var loanedTo: String?
    var dueDate: String?
    var returnedAt: String?
    var notes: String?
    var tagIds: [String]?
}
