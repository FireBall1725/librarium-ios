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
