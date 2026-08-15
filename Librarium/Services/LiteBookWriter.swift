// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation
import SwiftData

/// Writes a freshly-scanned book into a Lite-mode library's SwiftData
/// store. Mirrors what `POST /books` would do server-side: creates a
/// synthetic Book + a primary BookEdition, with metadata from the
/// `ISBNLookupResult` the scan flow already has. No api round-trip;
/// Lite is local-only.
struct LiteBookWriter {
    let modelContainer: ModelContainer

    /// Insert a book into the cache. Returns the constructed Book so
    /// the scan flow can route to the just-added detail screen.
    /// Returns nil only if the JSON round-trip to build the Book
    /// somehow fails — never throws.
    @discardableResult
    func add(
        lookup: ISBNLookupResult,
        to library: Library,
        serverAccountID: UUID,
        mediaType: String = "Book",
        readStatus: String = "unread"
    ) -> Book? {
        let bookId = UUID().uuidString
        let editionId = UUID().uuidString
        let nowISO = ISO8601DateFormatter().string(from: Date())

        let contributors: [[String: Any]] = lookup.authors.enumerated().map { idx, name in
            [
                "contributorId": UUID().uuidString,
                "name": name,
                "role": "Author",
                "displayOrder": idx
            ]
        }

        let bookDict: [String: Any] = [
            "id": bookId,
            "libraryId": library.id,
            "title": lookup.title,
            "subtitle": lookup.subtitle,
            "mediaTypeId": "",
            "mediaType": mediaType,
            "description": lookup.description,
            "createdAt": nowISO,
            "updatedAt": nowISO,
            "contributors": contributors,
            "tags": [],
            "genres": [],
            "coverUrl": lookup.coverUrl,
            "hasCover": !lookup.coverUrl.isEmpty,
            "userReadStatus": readStatus,
            "activeLoanCount": 0
        ]

        guard let bookData = try? JSONSerialization.data(withJSONObject: bookDict),
              let book = try? Self.decoder.decode(Book.self, from: bookData) else {
            return nil
        }

        // Persist the book row.
        let bookCache = BookCache(modelContainer: modelContainer)
        bookCache.upsert([book], for: library, serverAccountID: serverAccountID)
        // Tell open BooksView instances to re-read from cache. The scan
        // flow lives in a fullScreenCover above the books view, so .task
        // / .onAppear don't refire when it dismisses — without this
        // ping, the just-added book stays invisible until the user
        // navigates away and back.
        NotificationCenter.default.post(
            name: .liteLibraryDidChange,
            object: nil,
            userInfo: ["libraryID": library.id]
        )

        // Persist a primary edition so the detail view's Editions
        // section isn't empty. ISBN + publisher + pageCount come from
        // the Open Library lookup; everything else gets sensible
        // defaults the user can edit later.
        let editionDict: [String: Any] = [
            "id": editionId,
            "bookId": bookId,
            "format": "physical",
            "language": lookup.language,
            "editionName": "",
            "narrator": "",
            "publisher": lookup.publisher,
            "publishDate": lookup.publishDate,
            "isbn_10": lookup.isbn10,
            "isbn_13": lookup.isbn13,
            "copyCount": 1,
            "description": lookup.description,
            "pageCount": lookup.pageCount as Any,
            "isPrimary": true,
            "createdAt": nowISO,
            "updatedAt": nowISO
        ]
        if let editionData = try? JSONSerialization.data(withJSONObject: editionDict),
           let edition = try? Self.decoder.decode(BookEdition.self, from: editionData) {
            EditionCache(modelContainer: modelContainer)
                .upsert([edition], for: library, bookId: bookId, serverAccountID: serverAccountID)
        }

        return book
    }

    /// Manual-add variant for books without an ISBN. The user types
    /// title + author + media type into the LiteManualAddSheet; we
    /// build a minimal lookup-shaped payload and reuse the same write
    /// path so editions get created the same way scanned books do.
    @discardableResult
    func addManual(
        title: String,
        author: String,
        to library: Library,
        serverAccountID: UUID,
        mediaType: String = "Book",
        readStatus: String = "unread"
    ) -> Book? {
        let lookup = ISBNLookupResult(
            provider: "manual",
            providerDisplay: "Manual entry",
            title: title,
            subtitle: "",
            authors: author.isEmpty ? [] : [author],
            publisher: "",
            publishDate: "",
            isbn10: "",
            isbn13: "",
            description: "",
            coverUrl: "",
            language: "",
            pageCount: nil,
            categories: nil
        )
        return add(
            lookup: lookup,
            to: library,
            serverAccountID: serverAccountID,
            mediaType: mediaType,
            readStatus: readStatus
        )
    }

    /// Edit an existing Lite book's metadata. `Book`'s properties are
    /// `let`, so this round-trips through JSON the same way `add` builds
    /// one: encode the current book, overwrite the edited keys, decode
    /// back. Anything not passed keeps its current value.
    ///
    /// `coverUrl` is writable because a Lite cover is a remote URL, not
    /// a local file: the metadata refresh can point the book at an
    /// Open Library or Hardcover image and the existing cover pipeline
    /// renders it. Capturing a cover with the camera is still out,
    /// since that would need local image storage.
    ///
    /// Pass `nil` for `coverUrl` to leave the current one alone.
    @discardableResult
    func update(
        book: Book,
        title: String,
        subtitle: String,
        authors: [String]?,
        mediaType: String,
        description: String,
        coverUrl: String? = nil,
        in library: Library,
        serverAccountID: UUID
    ) -> Book? {
        guard var dict = try? JSONSerialization.jsonObject(
            with: JSONEncoder().encode(book)
        ) as? [String: Any] else { return nil }

        dict["title"] = title
        dict["subtitle"] = subtitle
        dict["mediaType"] = mediaType
        dict["description"] = description
        dict["updatedAt"] = ISO8601DateFormatter().string(from: Date())
        if let coverUrl {
            dict["coverUrl"] = coverUrl
            // hasCover drives the placeholder-jacket fallback, so it has
            // to move with the URL or a refreshed cover renders as a
            // generated jacket anyway.
            dict["hasCover"] = !coverUrl.isEmpty
        }

        // Contributors: `authors` nil means leave the list alone, which
        // is what a caller that did not touch the author field wants.
        // Passing a list replaces it wholesale.
        //
        // This used to take a single joined string, so a two-author book
        // came back as one contributor literally named "A, B", and any
        // edit that did not change the author still collapsed the list
        // to its first entry.
        if let authors {
            let existingIDs = book.contributors
                .filter { $0.role.caseInsensitiveCompare("author") == .orderedSame }
                .map(\.contributorId)
            // Reuse existing ids positionally so a re-save keeps stable
            // identities rather than churning a new uuid every time.
            dict["contributors"] = authors.enumerated().map { idx, name in
                [
                    "contributorId": idx < existingIDs.count ? existingIDs[idx] : UUID().uuidString,
                    "name": name,
                    "role": "Author",
                    "displayOrder": idx
                ]
            }
        }

        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let updated = try? Self.decoder.decode(Book.self, from: data) else {
            return nil
        }

        // `BookCache.upsert` rewrites the row's denormalised interaction
        // columns (read status, rating, favourite, progress) from the
        // Book it is handed. The caller's Book is a snapshot taken when
        // their screen opened, and interaction changes since then were
        // written to the row only — `mirrorInteractionToPersistedBook`
        // does not touch the payload. Without capturing and restoring
        // them, editing a title silently rolls back a book the user
        // marked as reading five seconds earlier.
        let context = ModelContext(modelContainer)
        let compositeID = PersistedBook.compositeID(
            serverURL: library.serverURL,
            libraryId: library.id,
            bookId: book.id
        )
        var descriptor = FetchDescriptor<PersistedBook>(
            predicate: #Predicate { $0.id == compositeID }
        )
        descriptor.fetchLimit = 1
        let existing = try? context.fetch(descriptor).first
        let keptStatus = existing?.readStatus
        let keptRating = existing?.rating
        let keptFavorite = existing?.isFavorite
        let keptProgress = existing?.progressPct

        BookCache(modelContainer: modelContainer)
            .upsert([updated], for: library, serverAccountID: serverAccountID)

        if keptStatus != nil || keptRating != nil || keptFavorite != nil || keptProgress != nil {
            let restoreContext = ModelContext(modelContainer)
            var restoreDescriptor = FetchDescriptor<PersistedBook>(
                predicate: #Predicate { $0.id == compositeID }
            )
            restoreDescriptor.fetchLimit = 1
            if let row = try? restoreContext.fetch(restoreDescriptor).first {
                if let keptStatus { row.readStatus = keptStatus }
                if let keptRating { row.rating = keptRating }
                if let keptFavorite { row.isFavorite = keptFavorite }
                if let keptProgress { row.progressPct = keptProgress }
                try? restoreContext.save()
            }
        }

        NotificationCenter.default.post(
            name: .liteLibraryDidChange,
            object: nil,
            userInfo: ["libraryID": library.id]
        )
        return updated
    }

    /// Edit the primary edition's fields.
    ///
    /// Publisher, publish date, ISBNs, page count and language live on
    /// the edition, not the book, which is why editing or refreshing a
    /// book left them untouched: `update` above only writes
    /// `PersistedBook`. Anything passed as nil keeps its current value.
    ///
    /// Creates a primary edition when the book has none, which is the
    /// case for anything added through the manual sheet before this
    /// existed.
    @discardableResult
    func updateEdition(
        bookId: String,
        publisher: String? = nil,
        publishDate: String? = nil,
        isbn10: String? = nil,
        isbn13: String? = nil,
        pageCount: Int? = nil,
        language: String? = nil,
        in library: Library,
        serverAccountID: UUID
    ) -> BookEdition? {
        let cache = EditionCache(modelContainer: modelContainer)
        let existing = cache.editions(for: library, bookId: bookId)
        let primary = existing.first(where: { $0.isPrimary }) ?? existing.first
        let nowISO = ISO8601DateFormatter().string(from: Date())

        var dict: [String: Any]
        if let primary,
           let encoded = try? JSONEncoder().encode(primary),
           let asDict = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any] {
            dict = asDict
        } else {
            dict = [
                "id": UUID().uuidString,
                "bookId": bookId,
                "format": "physical",
                "language": "",
                "editionName": "",
                "narrator": "",
                "publisher": "",
                "publishDate": "",
                "isbn_10": "",
                "isbn_13": "",
                "copyCount": 1,
                "description": "",
                "isPrimary": true,
                "createdAt": nowISO,
                "updatedAt": nowISO
            ]
        }

        if let publisher { dict["publisher"] = publisher }
        if let publishDate { dict["publishDate"] = publishDate }
        if let isbn10 { dict["isbn_10"] = isbn10 }
        if let isbn13 { dict["isbn_13"] = isbn13 }
        if let language { dict["language"] = language }
        if let pageCount { dict["pageCount"] = pageCount }
        dict["updatedAt"] = nowISO

        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let edition = try? Self.decoder.decode(BookEdition.self, from: data) else {
            return nil
        }
        cache.upsert([edition], for: library, bookId: bookId, serverAccountID: serverAccountID)
        NotificationCenter.default.post(
            name: .liteLibraryDidChange,
            object: nil,
            userInfo: ["libraryID": library.id]
        )
        return edition
    }

    /// Decoder without any key-conversion strategy. We hand-build the
    /// JSON dicts with the exact key names Book / BookEdition's
    /// CodingKeys expect (camelCase for most, but BookEdition uses
    /// explicit snake_case raw values for `isbn_10` / `isbn_13` that
    /// `.convertFromSnakeCase` would silently rename and break).
    private static let decoder = JSONDecoder()
}

extension Notification.Name {
    /// Posted by `LiteBookWriter` after a successful write so any open
    /// books view can re-read SwiftData. `userInfo["libraryID"]` carries
    /// the affected library's id (String).
    static let liteLibraryDidChange = Notification.Name("liteLibraryDidChange")
}
