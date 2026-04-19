import Foundation

struct Loan: Codable, Identifiable {
    let id: String
    let libraryId: String
    let bookId: String
    let bookTitle: String
    let loanedTo: String
    let loanedAt: String
    let dueDate: String?
    let returnedAt: String?
    let notes: String
    let tags: [Tag]
    let createdAt: String
    let updatedAt: String

    var isActive: Bool { returnedAt == nil }
}
