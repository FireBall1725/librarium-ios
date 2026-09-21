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

    /// When it went out, as a date. Nil when the string is neither shape.
    var lentOn: Date? { Self.day(loanedAt) }

    /// The API sends dates as either a plain day or a full timestamp depending
    /// on the column, and either way a loan date is a calendar day rather than
    /// an instant: a book lent on 2 June was lent on 2 June wherever you read
    /// it. So the day part is parsed in the reader's own calendar first.
    ///
    /// Parsing the timestamp as an instant instead is how a loan dated
    /// 2026-06-02T00:00:00Z came out as "1 Jun" anywhere west of Greenwich.
    static func day(_ raw: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: String(raw.prefix(10))) {
            return Calendar.current.startOfDay(for: d)
        }
        if let d = try? Date(raw, strategy: .iso8601) {
            return Calendar.current.startOfDay(for: d)
        }
        return nil
    }
}
