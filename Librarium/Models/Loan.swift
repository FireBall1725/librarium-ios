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

    /// Out past its due date. A loan with no due date is never overdue: it was
    /// lent open-endedly, and inventing a deadline for it would put a red badge
    /// on a book nobody is waiting for.
    var isOverdue: Bool {
        guard isActive, let dueDate, let due = Self.day(dueDate) else { return false }
        return due < Calendar.current.startOfDay(for: Date())
    }

    /// How the date reads on a row: "3 days overdue", "due Friday", or the
    /// date itself once it is far enough out that a weekday means nothing.
    var dueLabel: String? {
        guard isActive, let dueDate, let due = Self.day(dueDate) else { return nil }
        let today = Calendar.current.startOfDay(for: Date())
        let days = Calendar.current.dateComponents([.day], from: today, to: due).day ?? 0
        switch days {
        case ..<0:
            let late = -days
            return late == 1 ? "1 day overdue" : "\(late) days overdue"
        case 0:  return "due today"
        case 1:  return "due tomorrow"
        case 2...6:
            return "due " + due.formatted(.dateTime.weekday(.wide))
        default:
            return "due " + due.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    /// The API sends dates as either a plain day or a full timestamp depending
    /// on the column, so both are tried rather than assuming one.
    private static func day(_ raw: String) -> Date? {
        if let d = try? Date(raw, strategy: .iso8601) {
            return Calendar.current.startOfDay(for: d)
        }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: String(raw.prefix(10))) {
            return Calendar.current.startOfDay(for: d)
        }
        return nil
    }
}
