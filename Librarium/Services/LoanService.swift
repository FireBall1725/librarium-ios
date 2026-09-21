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

    /// Takes the whole loan, not just its id.
    ///
    /// The PATCH is a replace, not a merge: it refuses a body with no
    /// `loaned_to` and clears the due date and the notes it is not sent. So
    /// marking a book returned by sending only the date failed outright, and
    /// would have wiped the rest of the record if it had not
    /// (librarium-ios-122).
    @discardableResult
    func markReturned(_ loan: Loan, on day: Date = Date()) async throws -> Loan {
        var body = LoanUpdateBody()
        body.loanedTo = loan.loanedTo
        body.dueDate = loan.dueDate
        body.notes = loan.notes
        body.returnedAt = Self.day.string(from: day)
        return try await client.patch(
            "/api/v1/libraries/\(loan.libraryId)/loans/\(loan.id)",
            body: body
        )
    }

    /// The server takes loan dates as plain days, not instants.
    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

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

/// A loan update. The route replaces rather than merges, so a field left nil
/// here is a field cleared on the server: send the whole record back.
struct LoanUpdateBody: Encodable {
    var loanedTo: String?
    var dueDate: String?
    var returnedAt: String?
    var notes: String?
}
