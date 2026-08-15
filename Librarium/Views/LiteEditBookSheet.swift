// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftData
import SwiftUI

/// Edit a Lite library's book. The shared `AddEditBookSheet` loads tags
/// and media types from the api and saves through `BookService`, none of
/// which exists for a local:// library, so Lite gets its own sheet over
/// the same fields it can actually write.
///
/// Covers are absent on purpose: storing one locally needs an image
/// cache that Lite does not have yet.
struct LiteEditBookSheet: View {
    let library: Library
    let book: Book
    let serverAccountID: UUID
    var onSaved: (Book) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var subtitle: String
    @State private var author: String
    @State private var mediaType: String
    @State private var bookDescription: String

    // Edition fields. These live on BookEdition rather than Book, which
    // is why they were missing here: the sheet only wrote the book row.
    @State private var isbn13 = ""
    @State private var isbn10 = ""
    @State private var publisher = ""
    @State private var publishDate = ""
    @State private var pageCount = ""
    @State private var language = ""
    @State private var loadedEdition = false
    /// The author as it was when the sheet opened, so save can tell an
    /// untouched field from a deliberate change.
    private let originalAuthor: String

    /// Matches the list the scan flow and manual-add sheet seed. Lite has
    /// no server-side media-type catalogue to fetch, so the options are
    /// hardcoded in all three places.
    private let mediaTypes = ["Book", "Manga", "Comic", "Graphic novel", "Audiobook"]

    init(
        library: Library,
        book: Book,
        serverAccountID: UUID,
        onSaved: @escaping (Book) -> Void
    ) {
        self.library = library
        self.book = book
        self.serverAccountID = serverAccountID
        self.onSaved = onSaved

        // Split rather than chained: the single-expression form with two
        // `??` fallbacks tripped the type-checker's time limit.
        let authored = book.contributors.first {
            $0.role.caseInsensitiveCompare("author") == .orderedSame
        }
        let primaryAuthor: String = authored?.name ?? book.contributors.first?.name ?? ""
        _title = State(initialValue: book.title)
        _subtitle = State(initialValue: book.subtitle)
        _author = State(initialValue: primaryAuthor)
        self.originalAuthor = primaryAuthor
        _bookDescription = State(initialValue: book.description)
        // A book written before the media-type list existed, or one whose
        // stored value came from somewhere else, would otherwise select
        // nothing and silently save as the first option.
        _mediaType = State(initialValue: book.mediaType.isEmpty ? "Book" : book.mediaType)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Book") {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)
                    TextField("Subtitle (optional)", text: $subtitle)
                    TextField("Author (optional)", text: $author)
                        .textInputAutocapitalization(.words)
                }
                Section("Type") {
                    Picker("Media type", selection: $mediaType) {
                        // Carry an unrecognised stored value as its own
                        // option so opening the sheet cannot quietly
                        // rewrite it.
                        if !mediaTypes.contains(mediaType) {
                            Text(mediaType).tag(mediaType)
                        }
                        ForEach(mediaTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                }
                Section("Description") {
                    TextField("Description", text: $bookDescription, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)
                }

                Section {
                    TextField("ISBN-13", text: $isbn13)
                        .keyboardType(.numberPad)
                    TextField("ISBN-10", text: $isbn10)
                        .keyboardType(.numberPad)
                    TextField("Publisher", text: $publisher)
                    TextField("Published (YYYY or YYYY-MM-DD)", text: $publishDate)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Pages", text: $pageCount)
                        .keyboardType(.numberPad)
                    TextField("Language (e.g. en)", text: $language)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Edition")
                } footer: {
                    Text("Adding an ISBN lets Refresh metadata look this book up directly instead of guessing from the title.")
                }
            }
            .task { loadEdition() }
            .navigationTitle("Edit Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedTitle.isEmpty)
                }
            }
        }
    }

    /// Editions are not on the `Book` the caller hands us, so they are
    /// read from the cache when the sheet appears. Guarded because
    /// `.task` can re-fire and would otherwise stomp on typing.
    private func loadEdition() {
        guard !loadedEdition else { return }
        loadedEdition = true
        let editions = EditionCache(modelContainer: modelContext.container)
            .editions(for: library, bookId: book.id)
        guard let primary = editions.first(where: { $0.isPrimary }) ?? editions.first else { return }
        isbn13 = primary.isbn13
        isbn10 = primary.isbn10
        publisher = primary.publisher
        publishDate = primary.publishDate ?? ""
        pageCount = primary.pageCount.map(String.init) ?? ""
        language = primary.language
    }

    private func save() {
        let writer = LiteBookWriter(modelContainer: modelContext.container)
        // Edition first: it posts its own change notification, and the
        // book write below posts the one the caller's onSaved reacts to.
        writer.updateEdition(
            bookId: book.id,
            publisher: publisher.trimmingCharacters(in: .whitespacesAndNewlines),
            publishDate: publishDate.trimmingCharacters(in: .whitespacesAndNewlines),
            isbn10: isbn10.trimmingCharacters(in: .whitespacesAndNewlines),
            isbn13: isbn13.trimmingCharacters(in: .whitespacesAndNewlines),
            // An empty field means "no page count", not zero, so only a
            // parseable number is written.
            pageCount: Int(pageCount.trimmingCharacters(in: .whitespacesAndNewlines)),
            language: language.trimmingCharacters(in: .whitespacesAndNewlines),
            in: library,
            serverAccountID: serverAccountID
        )
        // Only send contributors when the field actually changed. The
        // sheet shows one author, so passing a list on every save would
        // discard any co-authors the book arrived with.
        let trimmedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        let authorsToWrite: [String]? = trimmedAuthor == originalAuthor
            ? nil
            : (trimmedAuthor.isEmpty ? [] : [trimmedAuthor])

        if let updated = writer.update(
            book: book,
            title: trimmedTitle,
            subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
            authors: authorsToWrite,
            mediaType: mediaType,
            description: bookDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            in: library,
            serverAccountID: serverAccountID
        ) {
            onSaved(updated)
        }
        dismiss()
    }
}
