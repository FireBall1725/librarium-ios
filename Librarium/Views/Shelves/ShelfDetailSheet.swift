import SwiftUI

struct ShelfDetailSheet: View {
    let library: Library
    let shelf: Shelf
    let onUpdate: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var books: [Book] = []
    @State private var isLoading = true
    @State private var showEdit = false
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if !shelf.description.isEmpty {
                        Text(shelf.description).font(.subheadline).foregroundStyle(.secondary)
                    }
                    LabeledContent("Books", value: "\(shelf.bookCount)")
                }

                Section("Books") {
                    if isLoading { HStack { Spacer(); ProgressView(); Spacer() } }
                    else if books.isEmpty { Text("No books on this shelf").foregroundStyle(.secondary) }
                    else {
                        ForEach(books) { book in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(book.title).font(.subheadline)
                                if let c = book.contributors.first {
                                    Text(c.name).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task {
                                        try? await ShelfService(client: appState.makeClient())
                                            .removeBook(libraryId: library.id, shelfId: shelf.id, bookId: book.id)
                                        books.removeAll { $0.id == book.id }
                                    }
                                } label: { Label("Remove", systemImage: "minus.circle") }
                            }
                        }
                    }
                }
            }
            .navigationTitle(shelf.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showEdit = true } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(isPresented: $showEdit) {
                AddEditShelfSheet(library: library, shelf: shelf) { _ in onUpdate(); dismiss() }
            }
            .confirmationDialog("Delete \"\(shelf.name)\"?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        try? await ShelfService(client: appState.makeClient()).delete(libraryId: library.id, shelfId: shelf.id)
                        onUpdate(); dismiss()
                    }
                }
            }
            .task {
                books = (try? await ShelfService(client: appState.makeClient()).books(libraryId: library.id, shelfId: shelf.id)) ?? []
                isLoading = false
            }
        }
    }
}
