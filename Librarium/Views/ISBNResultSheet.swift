import SwiftUI

// Thin Identifiable wrapper so sheet(item:) works with a plain ISBN string.
struct ISBNQuery: Identifiable {
    let isbn: String
    var id: String { isbn }
}

struct ISBNResultSheet: View {
    let isbn: String
    let libraries: [Library]

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = true
    @State private var lookupResult: ISBNLookupResult?
    @State private var libraryMatches: [String: Book] = [:]   // clientKey → Book
    @State private var justAdded: Set<String> = []            // clientKeys added this session
    @State private var error: String?
    @State private var addingToLibrary: Library?

    private var librariesWithBook: [Library] {
        libraries.filter { libraryMatches[$0.clientKey] != nil || justAdded.contains($0.clientKey) }
    }
    private var librariesWithoutBook: [Library] {
        libraries.filter { libraryMatches[$0.clientKey] == nil && !justAdded.contains($0.clientKey) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Looking up \(isbn)…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let result = lookupResult {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            bookCard(result)
                            Divider()
                            libraryStatusSection
                        }
                        .padding()
                    }
                } else {
                    notFoundView
                }
            }
            .navigationTitle("Scan Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $addingToLibrary) { library in
                AddEditBookSheet(library: library, initialLookup: lookupResult) { _ in
                    justAdded.insert(library.clientKey)
                    addingToLibrary = nil
                }
            }
            .task { await load() }
            .alert("Error", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    // MARK: - Book card

    private func bookCard(_ result: ISBNLookupResult) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if !result.coverUrl.isEmpty, let url = URL(string: result.coverUrl) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                    }
                }
                .frame(width: 72, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(radius: 3, y: 2)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(result.title)
                    .font(.headline)
                    .lineLimit(3)
                if !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !result.authors.isEmpty {
                    Text(result.authors.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if !result.publisher.isEmpty {
                    Text(result.publisher).font(.caption).foregroundStyle(.secondary)
                }
                let displayISBN = result.isbn13.isEmpty ? result.isbn10 : result.isbn13
                if !displayISBN.isEmpty {
                    Label(displayISBN, systemImage: "barcode")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text("via \(result.providerDisplay)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Library status

    @ViewBuilder
    private var libraryStatusSection: some View {
        if libraries.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "books.vertical")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No libraries yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
        } else {
            VStack(alignment: .leading, spacing: 16) {
                if !librariesWithBook.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("In your collection", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                        ForEach(librariesWithBook) { library in
                            HStack {
                                Text(library.name).font(.subheadline)
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.subheadline)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                if !librariesWithoutBook.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(librariesWithBook.isEmpty ? "Not in your collection" : "Add to another library")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(librariesWithBook.isEmpty ? .secondary : .primary)
                        ForEach(librariesWithoutBook) { library in
                            Button { addingToLibrary = library } label: {
                                HStack {
                                    Text(library.name)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Label("Add", systemImage: "plus.circle.fill")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.tint)
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Not found

    private var notFoundView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("Book Not Found")
                    .font(.title3.bold())
                Text("No information found for \(isbn).\nYou can still add it manually.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if !libraries.isEmpty {
                Menu("Add to Library") {
                    ForEach(libraries) { library in
                        Button(library.name) { addingToLibrary = library }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Load

    private func load() async {
        isLoading = true; defer { isLoading = false }
        // Quick-scan metadata lookups always hit the user's primary server, so
        // the result doesn't drift based on which library happens to be open.
        let client = appState.makePrimaryClient()

        // Lookup book metadata and per-library ownership checks in parallel
        async let lookupTask: [ISBNLookupResult]? = try? LookupService(client: client).isbn(isbn)

        var matches: [String: Book] = [:]
        await withTaskGroup(of: (String, Book?).self) { group in
            for library in libraries {
                // Hit each server the library belongs to, not just the active one.
                let perLibClient = appState.makeClient(serverURL: library.serverURL)
                group.addTask {
                    let book = try? await BookService(client: perLibClient).byISBN(
                        libraryId: library.id, isbn: isbn)
                    return (library.clientKey, book)
                }
            }
            for await (key, book) in group {
                if let book { matches[key] = book }
            }
        }

        lookupResult = (await lookupTask)?.first
        libraryMatches = matches
    }
}
