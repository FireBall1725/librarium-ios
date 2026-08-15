// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftData
import SwiftUI

/// Re-fetch a Lite book's metadata and let the user choose, field by
/// field, what to keep.
///
/// Review-first on purpose. A Lite book is the only copy that exists, so
/// an unattended overwrite would destroy work with no server-side
/// history to recover from. Fields that are currently empty default to
/// on; fields that already hold a value default to off, so the safe
/// action is also the default one.
struct LiteRefreshMetadataSheet: View {
    let library: Library
    let book: Book
    let serverAccountID: UUID
    var onApplied: (Book) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case loading
        case picking([ISBNLookupResult])   // no ISBN: choose the right book first
        case reviewing(ISBNLookupResult)
        case empty
        case failed(String)
    }

    @State private var phase: Phase = .loading
    @State private var selected: Set<Field> = []
    @State private var incoming: ISBNLookupResult?

    /// The fields a refresh can write. Deliberately excludes anything
    /// the user cannot see the result of, and anything Lite has no
    /// storage for.
    private enum Field: String, CaseIterable, Hashable {
        case title, subtitle, author, description, cover
        // Edition-level. These live on BookEdition rather than Book, so
        // applying them writes through updateEdition.
        case publisher, publishDate, pageCount, language, isbn13, isbn10

        var label: String {
            switch self {
            case .title: return "Title"
            case .subtitle: return "Subtitle"
            case .author: return "Author"
            case .description: return "Description"
            case .cover: return "Cover"
            case .publisher: return "Publisher"
            case .publishDate: return "Published"
            case .pageCount: return "Pages"
            case .language: return "Language"
            case .isbn13: return "ISBN-13"
            case .isbn10: return "ISBN-10"
            }
        }

        var isEditionField: Bool {
            switch self {
            case .title, .subtitle, .author, .description, .cover: return false
            case .publisher, .publishDate, .pageCount, .language, .isbn13, .isbn10: return true
            }
        }
    }

    /// The books primary edition. Loaded once in `load()`: it used to
    /// be computed, and `currentValue(_:)` calls it per field while
    /// `changedFields` walks all eleven, so a single body render cost
    /// about thirty SwiftData fetches and JSON decodes inside a List.
    @State private var primaryEdition: BookEdition?

    /// Editions carry the ISBN; the book row does not.
    private var primaryISBN: String {
        guard let edition = primaryEdition else { return "" }
        return edition.isbn13.isEmpty ? edition.isbn10 : edition.isbn13
    }

    /// One fetch, at load time. Everything downstream reads the stored
    /// value rather than going back to SwiftData.
    private func loadPrimaryEdition() {
        let editions = EditionCache(modelContainer: modelContext.container)
            .editions(for: library, bookId: book.id)
        primaryEdition = editions.first(where: { $0.isPrimary }) ?? editions.first
    }

    private var currentAuthor: String {
        let authored = book.contributors.first {
            $0.role.caseInsensitiveCompare("author") == .orderedSame
        }
        return authored?.name ?? book.contributors.first?.name ?? ""
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Looking up metadata…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .picking(let candidates):
                    candidateList(candidates)

                case .reviewing(let result):
                    reviewList(result)

                case .empty:
                    ContentUnavailableView(
                        "No match found",
                        systemImage: "magnifyingglass",
                        description: Text(
                            primaryISBN.isEmpty
                            ? "Nothing came back for \"\(book.title)\". Try editing the title, or add an ISBN."
                            : "Nothing came back for ISBN \(primaryISBN)."
                        )
                    )

                case .failed(let message):
                    ContentUnavailableView(
                        "Lookup failed",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                }
            }
            .navigationTitle("Refresh Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if case .reviewing = phase {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") { apply() }
                            .disabled(selected.isEmpty)
                    }
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Candidate picking (books with no ISBN)

    @ViewBuilder
    private func candidateList(_ candidates: [ISBNLookupResult]) -> some View {
        List {
            Section {
                ForEach(Array(candidates.enumerated()), id: \.offset) { _, candidate in
                    Button {
                        Task { await choose(candidate) }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(candidate.title)
                                .font(.subheadline.weight(.medium))
                            if !candidate.authors.isEmpty {
                                Text(candidate.authors.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 6) {
                                Text(candidate.providerDisplay)
                                if !candidate.publishDate.isEmpty {
                                    Text("· \(candidate.publishDate)")
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Which book is this?")
            } footer: {
                Text("This book has no ISBN, so these are title matches. Pick one to see what would change.")
            }
        }
    }

    // MARK: - Field review

    @ViewBuilder
    private func reviewList(_ result: ISBNLookupResult) -> some View {
        let changes = changedFields(against: result)
        if changes.isEmpty {
            ContentUnavailableView(
                "Nothing to update",
                systemImage: "checkmark.circle",
                description: Text("\(result.providerDisplay) agrees with what you already have.")
            )
        } else {
            List {
                Section {
                    ForEach(changes, id: \.self) { field in
                        Button {
                            if selected.contains(field) { selected.remove(field) }
                            else { selected.insert(field) }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: selected.contains(field)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(field) ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(field.label)
                                        .font(.subheadline.weight(.medium))
                                    if currentValue(field).isEmpty {
                                        Text("Currently empty")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    } else {
                                        Text(currentValue(field))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .strikethrough()
                                            .lineLimit(3)
                                    }
                                    Text(incomingValue(field, from: result))
                                        .font(.caption)
                                        .lineLimit(6)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Changes from \(result.providerDisplay)")
                } footer: {
                    Text("Fields you already filled in are off by default so a refresh can't overwrite your own edits.")
                }
            }
        }
    }

    // MARK: - Field access

    private func currentValue(_ field: Field) -> String {
        let edition = primaryEdition
        switch field {
        case .title: return book.title
        case .subtitle: return book.subtitle
        case .author: return currentAuthor
        case .description: return book.description
        case .cover: return book.coverUrl ?? ""
        case .publisher: return edition?.publisher ?? ""
        case .publishDate: return edition?.publishDate ?? ""
        case .pageCount: return edition?.pageCount.map(String.init) ?? ""
        case .language: return edition?.language ?? ""
        case .isbn13: return edition?.isbn13 ?? ""
        case .isbn10: return edition?.isbn10 ?? ""
        }
    }

    private func incomingValue(_ field: Field, from result: ISBNLookupResult) -> String {
        switch field {
        case .title: return result.title
        case .subtitle: return result.subtitle
        case .author: return result.authors.joined(separator: ", ")
        case .description: return result.description
        case .cover: return result.coverUrl
        case .publisher: return result.publisher
        case .publishDate: return result.publishDate
        case .pageCount: return result.pageCount.map(String.init) ?? ""
        case .language: return result.language
        case .isbn13: return result.isbn13
        case .isbn10: return result.isbn10
        }
    }

    /// Fields where the incoming value is non-empty and different. A
    /// provider returning "" never counts as a change, or a refresh
    /// would offer to blank out everything it does not know.
    private func changedFields(against result: ISBNLookupResult) -> [Field] {
        Field.allCases.filter { field in
            let new = incomingValue(field, from: result)
            return !new.isEmpty && new != currentValue(field)
        }
    }

    // MARK: - Actions

    private func load() async {
        loadPrimaryEdition()
        let aggregator = LiteMetadataAggregator(providers: LiteMetadataSettings.allProviders)

        let isbn = primaryISBN
        if isbn.isEmpty {
            // No ISBN to look up, so fall back to a title search and let
            // the user confirm which book it is.
            var query = book.title
            if !currentAuthor.isEmpty { query += " \(currentAuthor)" }
            let candidates = await aggregator.search(query: query)
            phase = candidates.isEmpty ? .empty : .picking(candidates)
            return
        }

        let results = await aggregator.lookup(isbn: isbn)
        guard let merged = LiteMetadataAggregator.merge(results) else {
            phase = .empty
            return
        }
        startReview(with: merged)
    }

    /// A search hit carries no description, so once the user picks one we
    /// re-look-up by its ISBN to get the full record.
    private func choose(_ candidate: ISBNLookupResult) async {
        phase = .loading
        let isbn = candidate.isbn13.isEmpty ? candidate.isbn10 : candidate.isbn13
        guard !isbn.isEmpty else {
            startReview(with: candidate)
            return
        }
        let results = await LiteMetadataAggregator(providers: LiteMetadataSettings.allProviders).lookup(isbn: isbn)
        startReview(with: LiteMetadataAggregator.merge(results) ?? candidate)
    }

    private func startReview(with result: ISBNLookupResult) {
        incoming = result
        // Pre-select only the fields that are currently empty. Filling a
        // blank is what the user came for; replacing their own text is
        // something they should have to ask for.
        selected = Set(changedFields(against: result).filter { currentValue($0).isEmpty })
        phase = .reviewing(result)
    }

    private func apply() {
        guard let incoming else { return }
        let writer = LiteBookWriter(modelContainer: modelContext.container)

        // Edition fields go through their own write path. Passing nil
        // for anything unselected leaves the stored value alone.
        if selected.contains(where: \.isEditionField) {
            writer.updateEdition(
                bookId: book.id,
                publisher: selected.contains(.publisher) ? incoming.publisher : nil,
                publishDate: selected.contains(.publishDate) ? incoming.publishDate : nil,
                isbn10: selected.contains(.isbn10) ? incoming.isbn10 : nil,
                isbn13: selected.contains(.isbn13) ? incoming.isbn13 : nil,
                pageCount: selected.contains(.pageCount) ? incoming.pageCount : nil,
                language: selected.contains(.language) ? incoming.language : nil,
                in: library,
                serverAccountID: serverAccountID
            )
        }

        let updated = writer.update(
            book: book,
            title: selected.contains(.title) ? incoming.title : book.title,
            subtitle: selected.contains(.subtitle) ? incoming.subtitle : book.subtitle,
            // nil leaves the existing contributor list untouched. The
            // old code passed the primary author back on every apply,
            // which meant refreshing any field at all dropped every
            // co-author the book had.
            authors: selected.contains(.author) ? incoming.authors : nil,
            mediaType: book.mediaType,
            description: selected.contains(.description) ? incoming.description : book.description,
            coverUrl: selected.contains(.cover) ? incoming.coverUrl : book.coverUrl,
            in: library,
            serverAccountID: serverAccountID
        )
        if let updated { onApplied(updated) }
        dismiss()
    }
}
