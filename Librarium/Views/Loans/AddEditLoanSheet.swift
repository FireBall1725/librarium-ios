import SwiftUI

struct AddEditLoanSheet: View {
    let library: Library
    var loan: Loan? = nil
    let onSave: (Loan) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var bookSearch = ""
    @State private var bookResults: [Book] = []
    @State private var selectedBook: Book?
    @State private var loanedTo = ""
    @State private var loanedAt = Date()
    @State private var hasDueDate = false
    @State private var dueDate = Date().addingTimeInterval(60*60*24*14)
    @State private var notes = ""
    @State private var isSaving = false
    @State private var error: String?
    @State private var searchTask: Task<Void, Never>?

    let iso = ISO8601DateFormatter()

    var body: some View {
        NavigationStack {
            Form {
                if loan == nil {
                    Section("Book") {
                        if let book = selectedBook {
                            HStack {
                                Text(book.title).font(.subheadline)
                                Spacer()
                                Button { selectedBook = nil; bookSearch = "" } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            TextField("Search books…", text: $bookSearch)
                                .autocorrectionDisabled()
                                .onChange(of: bookSearch) { _, q in
                                    searchTask?.cancel()
                                    guard !q.isEmpty else { bookResults = []; return }
                                    searchTask = Task {
                                        try? await Task.sleep(for: .milliseconds(300))
                                        guard !Task.isCancelled else { return }
                                        let paged = try? await BookService(client: appState.makeClient())
                                            .list(libraryId: library.id, query: q, perPage: 10)
                                        bookResults = paged?.items ?? []
                                    }
                                }
                            ForEach(bookResults) { book in
                                Button {
                                    selectedBook = book; bookSearch = book.title; bookResults = []
                                } label: {
                                    Text(book.title).font(.subheadline)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section("Loan Details") {
                    TextField("Loaned to", text: $loanedTo)
                    DatePicker("Loaned on", selection: $loanedAt, displayedComponents: .date)
                    Toggle("Has due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
                    }
                }

                Section("Notes") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical).lineLimit(3, reservesSpace: true)
                }

                if let err = error {
                    Section { Text(err).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle(loan == nil ? "New Loan" : "Edit Loan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled((loan == nil && selectedBook == nil) || loanedTo.isEmpty || isSaving)
                }
            }
            .onAppear {
                if let l = loan {
                    loanedTo = l.loanedTo; notes = l.notes
                    if let d = l.dueDate, !d.isEmpty, let parsed = iso.date(from: d) {
                        hasDueDate = true; dueDate = parsed
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save() async {
        isSaving = true; error = nil; defer { isSaving = false }
        do {
            let saved: Loan
            if let loan {
                var update = LoanUpdateBody()
                update.loanedTo = loanedTo; update.notes = notes
                update.dueDate = hasDueDate ? iso.string(from: dueDate) : nil
                saved = try await LoanService(client: appState.makeClient()).update(
                    libraryId: library.id, loanId: loan.id, body: update)
            } else {
                guard let book = selectedBook else { return }
                let body = LoanBody(
                    bookId: book.id, loanedTo: loanedTo,
                    loanedAt: iso.string(from: loanedAt),
                    dueDate: hasDueDate ? iso.string(from: dueDate) : nil,
                    notes: notes
                )
                saved = try await LoanService(client: appState.makeClient()).create(libraryId: library.id, body: body)
            }
            onSave(saved); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
