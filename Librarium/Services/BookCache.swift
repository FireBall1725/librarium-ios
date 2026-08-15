// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation
import SwiftData

/// SwiftData-backed cache for book rows. Sits between the api layer and
/// the views: every successful online fetch writes through here, and the
/// views fall back to it when the network is unreachable. Designed to
/// be called from any actor — opens a fresh `ModelContext` on each call
/// so we don't need a singleton or main-actor pinning.
///
/// Identity is keyed on the composite `<serverURL>|<libraryId>|<bookId>`
/// so cloned-database setups (same UUIDs on two servers) stay distinct.
struct BookCache {
    let modelContainer: ModelContainer

    // MARK: - Writes

    /// Upsert a page of books for a given library. We always replace the
    /// stored row outright — the api response is the source of truth and
    /// trying to merge field-by-field would just hide bugs.
    func upsert(_ books: [Book], for library: Library, serverAccountID: UUID) {
        guard !library.serverURL.isEmpty else { return }
        let context = ModelContext(modelContainer)
        let encoder = JSONEncoder()
        let serverURL = library.serverURL
        for book in books {
            let id = PersistedBook.compositeID(
                serverURL: serverURL,
                libraryId: library.id,
                bookId: book.id
            )
            guard let payload = try? encoder.encode(book) else { continue }
            let primaryAuthor = book.contributors
                .first(where: { $0.role.caseInsensitiveCompare("author") == .orderedSame })?.name
                ?? book.contributors.first?.name

            let existing = try? context.fetch(
                FetchDescriptor<PersistedBook>(predicate: #Predicate { $0.id == id })
            ).first

            if let row = existing {
                // Keep these in lock-step with the schema. Rows that
                // predate the `serverURL` column carry an empty default
                // — assign here so the migration self-heals as users
                // hit each book during normal use.
                row.serverURL = serverURL
                row.title = book.title
                row.sortTitle = book.title.librariumSortKey()
                row.subtitle = book.subtitle
                row.coverUrl = book.coverUrl
                row.primaryAuthor = primaryAuthor
                row.readStatus = book.userReadStatus
                row.progressPct = book.userProgressPct
                row.rating = book.userRating
                row.updatedAt = Date()
                row.payload = payload
            } else {
                let row = PersistedBook(
                    id: id,
                    serverAccountID: serverAccountID,
                    libraryId: library.id,
                    bookId: book.id,
                    title: book.title,
                    subtitle: book.subtitle,
                    coverUrl: book.coverUrl,
                    primaryAuthor: primaryAuthor,
                    readStatus: book.userReadStatus,
                    progressPct: book.userProgressPct,
                    rating: book.userRating,
                    isFavorite: false,
                    updatedAt: Date(),
                    payload: payload
                )
                context.insert(row)
            }
        }
        try? context.save()
    }

    /// Full paginated sync — replacement for `LibraryOfflineStore.syncBooks`'s
    /// JSON write path. Pulls every page from the api and upserts each into
    /// SwiftData so a kept-offline library has the same on-device footprint
    /// as a Lite library does. Best-effort: per-page errors abort the loop
    /// but everything paginated up to that point stays cached.
    ///
    /// Returns the total number of rows that ended up in the cache (counted
    /// from the api's reported total, not the number of upserts) so callers
    /// can surface a clean "1,412 books cached" line.
    @discardableResult
    func syncFull(
        library: Library,
        serverAccountID: UUID,
        accessToken: String?,
        client: APIClient,
        onProgress: (@MainActor (Double) -> Void)? = nil
    ) async -> Int {
        guard !library.serverURL.isEmpty else { return 0 }
        let perPage = 100
        var page = 1
        var totalCached = 0
        let serverURL = library.serverURL


        do {
            let first = try await BookService(client: client).list(
                libraryId: library.id, page: page, perPage: perPage
            )
            upsert(first.items, for: library, serverAccountID: serverAccountID)
            totalCached += first.items.count
            let total = max(first.total, 1)
            if let onProgress {
                await onProgress(Double(totalCached) / Double(total))
            }
            await Self.prefetchCovers(for: first.items, serverURL: serverURL, accessToken: accessToken)

            while totalCached < first.total {
                page += 1
                let next = try await BookService(client: client).list(
                    libraryId: library.id, page: page, perPage: perPage
                )
                if next.items.isEmpty { break }
                upsert(next.items, for: library, serverAccountID: serverAccountID)
                totalCached += next.items.count
                if let onProgress {
                    await onProgress(Double(totalCached) / Double(total))
                }
                await Self.prefetchCovers(for: next.items, serverURL: serverURL, accessToken: accessToken)
            }
        } catch {
            // Caller decides what to do with a partial sync (most just leave
            // it — the next visit retries). We deliberately don't throw so
            // callers can `await` without ceremony.
            #if DEBUG
            print("⚠️ [BookCache.syncFull] aborted at page \(page): \(error)")
            #endif
        }
        return totalCached
    }

    /// Fan-out cover prefetch for a page of books. CoverCache.prefetch
    /// is a no-op when the cache already has the URL, so this is safe to
    /// run on every sync — only new books incur a download. Bounded by
    /// task-group concurrency (Swift caps these at ~64) so we don't
    /// melt the user's connection on a fresh 1,000-book sync.
    private static func prefetchCovers(for books: [Book], serverURL: String, accessToken: String?) async {
        await withTaskGroup(of: Void.self) { group in
            for book in books {
                guard let path = book.coverUrl, !path.isEmpty else { continue }
                let url: URL?
                if path.hasPrefix("http://") || path.hasPrefix("https://") {
                    url = URL(string: path)
                } else {
                    url = URL(string: serverURL + path)
                }
                guard let url else { continue }
                group.addTask {
                    await CoverCache.shared.prefetch(url: url, accessToken: accessToken)
                }
            }
        }
    }

    // MARK: - Reads

    /// Load every cached book for a library, decoded back into `Book`.
    /// Sorted by the natural-sort key (articles stripped, digits padded)
    /// so the offline list matches what the api would have returned for
    /// the default title-ascending order.
    ///
    /// Rows that predate the `sortTitle` column carry an empty key (the
    /// SwiftData migration default), which would collapse them all into
    /// the same sort bucket and surface the insertion order. We backfill
    /// missing keys inline on read — first visit after upgrade pays the
    /// cost once, then sorting works correctly.
    func books(for library: Library) -> [Book] {
        let context = ModelContext(modelContainer)
        let serverURL = library.serverURL
        let libraryId = library.id

        // Backfill any rows that predate the `serverURL` column — they
        // sit with empty defaults from SwiftData's lightweight migration
        // and would be invisible to the predicate below. One-time pass
        // per library; subsequent fetches stay fast.
        backfillServerURL(serverURL: serverURL, libraryId: libraryId, context: context)

        let descriptor = FetchDescriptor<PersistedBook>(
            predicate: #Predicate { $0.serverURL == serverURL && $0.libraryId == libraryId }
        )
        guard let rows = try? context.fetch(descriptor) else { return [] }

        var dirty = false
        for row in rows where row.sortTitle.isEmpty {
            row.sortTitle = row.title.librariumSortKey()
            dirty = true
        }
        if dirty { try? context.save() }

        let sorted = rows.sorted { lhs, rhs in
            lhs.sortTitle < rhs.sortTitle
        }
        let decoder = JSONDecoder()
        return sorted.compactMap { try? decoder.decode(Book.self, from: $0.payload) }
    }

    /// One-time migration helper: find any rows whose composite `id`
    /// starts with `<serverURL>|<libraryId>|` but whose `serverURL`
    /// column is empty, and fill the column in. Lets us predicate on
    /// `serverURL == ...` confidently even on installs that synced
    /// books before the column existed.
    private func backfillServerURL(serverURL: String, libraryId: String, context: ModelContext) {
        let prefix = "\(serverURL)|\(libraryId)|"
        let descriptor = FetchDescriptor<PersistedBook>(
            predicate: #Predicate { $0.serverURL.isEmpty }
        )
        guard let rows = try? context.fetch(descriptor), !rows.isEmpty else { return }
        var dirty = false
        for row in rows where row.id.hasPrefix(prefix) {
            row.serverURL = serverURL
            dirty = true
        }
        if dirty { try? context.save() }
    }

    /// Offline title/author search across a single cached library.
    /// Used as the fallback when the search tab's api fan-out fails for
    /// a kept-offline library — the user's local data behaves like a
    /// search index. Match is case-insensitive contains on title and
    /// `primaryAuthor`; deeper contributor / tag matching can layer on
    /// later if needed.
    /// Cross-library offline search for a single server. Predicates on
    /// `serverURL` (stable across sign-ins) rather than `serverAccountID`
    /// (rotates on every fresh login). The composite `id` is parsed to
    /// fill in `serverURL` for any rows that predate the column — same
    /// self-healing pattern `books(for:)` uses.
    func searchAllBooks(serverURL: String, query: String) -> [Book] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let context = ModelContext(modelContainer)
        backfillAllServerURLs(context: context)

        let descriptor = FetchDescriptor<PersistedBook>(
            predicate: #Predicate { $0.serverURL == serverURL },
            sortBy: [SortDescriptor(\.sortTitle)]
        )
        guard let rows = try? context.fetch(descriptor) else { return [] }
        let needle = trimmed.lowercased()
        let matches = rows.filter { row in
            if row.title.lowercased().contains(needle) { return true }
            if let author = row.primaryAuthor, author.lowercased().contains(needle) { return true }
            return false
        }
        let decoder = JSONDecoder()
        return matches.compactMap { try? decoder.decode(Book.self, from: $0.payload) }
    }

    /// Cross-library serverURL backfill. Finds every row with an empty
    /// `serverURL` column and derives the value from the composite `id`
    /// (which encodes `<serverURL>|<libraryId>|<bookId>`). One-time
    /// cost per launch; subsequent searches stay fast.
    private func backfillAllServerURLs(context: ModelContext) {
        let descriptor = FetchDescriptor<PersistedBook>(
            predicate: #Predicate { $0.serverURL.isEmpty }
        )
        guard let rows = try? context.fetch(descriptor), !rows.isEmpty else { return }
        var dirty = false
        for row in rows {
            guard let pipe = row.id.firstIndex(of: "|") else { continue }
            row.serverURL = String(row.id[..<pipe])
            dirty = true
        }
        if dirty { try? context.save() }
    }

    func searchBooks(serverURL: String, libraryId: String, query: String) -> [Book] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let context = ModelContext(modelContainer)
        backfillServerURL(serverURL: serverURL, libraryId: libraryId, context: context)
        let descriptor = FetchDescriptor<PersistedBook>(
            predicate: #Predicate { $0.serverURL == serverURL && $0.libraryId == libraryId },
            sortBy: [SortDescriptor(\.sortTitle)]
        )
        guard let rows = try? context.fetch(descriptor) else { return [] }
        let needle = trimmed.lowercased()
        let matches = rows.filter { row in
            if row.title.lowercased().contains(needle) { return true }
            if let author = row.primaryAuthor, author.lowercased().contains(needle) { return true }
            return false
        }
        let decoder = JSONDecoder()
        return matches.compactMap { try? decoder.decode(Book.self, from: $0.payload) }
    }

    /// All cached books for an account whose user-read-status matches
    /// one of the given values, sorted by `updatedAt` descending.
    /// Powers the offline Home dashboard — "currently reading" /
    /// "recently finished" tiles come straight from these rows when
    /// the api isn't reachable.
    func booksByReadStatus(serverURL: String, statuses: Set<String>, limit: Int = 20) -> [Book] {
        let context = ModelContext(modelContainer)
        backfillAllServerURLs(context: context)
        var descriptor = FetchDescriptor<PersistedBook>(
            predicate: #Predicate { $0.serverURL == serverURL },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit * 4 // over-fetch since we filter in Swift
        guard let rows = try? context.fetch(descriptor) else { return [] }
        let matches = rows.filter { row in
            guard let status = row.readStatus else { return false }
            return statuses.contains(status)
        }
        let decoder = JSONDecoder()
        return matches.prefix(limit).compactMap { try? decoder.decode(Book.self, from: $0.payload) }
    }

    /// Single-book lookup for the detail-view fallback. Returns nil when
    /// the row doesn't exist or its payload fails to decode.
    func book(serverURL: String, libraryId: String, bookId: String) -> Book? {
        let context = ModelContext(modelContainer)
        let id = PersistedBook.compositeID(serverURL: serverURL, libraryId: libraryId, bookId: bookId)
        guard let row = try? context.fetch(
            FetchDescriptor<PersistedBook>(predicate: #Predicate { $0.id == id })
        ).first else { return nil }
        return try? JSONDecoder().decode(Book.self, from: row.payload)
    }

    /// Purge every cached row for a given serverURL — called when a
    /// server is removed so we don't leak stale rows.
    func purge(serverURL: String) {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PersistedBook>(
            predicate: #Predicate { $0.serverURL == serverURL }
        )
        guard let rows = try? context.fetch(descriptor) else { return }
        for row in rows { context.delete(row) }
        try? context.save()
    }

    /// Drop every row for a single (serverURL, libraryId) tuple. Called
    /// when the user toggles "Keep offline" off — we keep their other
    /// libraries' caches untouched.
    func purgeLibrary(serverURL: String, libraryId: String) {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PersistedBook>(
            predicate: #Predicate { $0.serverURL == serverURL && $0.libraryId == libraryId }
        )
        guard let rows = try? context.fetch(descriptor) else { return }
        for row in rows { context.delete(row) }
        try? context.save()
    }

    /// Row count for a library — cheap way to display "x books cached"
    /// without decoding every payload, and for `LibraryOfflineStore` to
    /// decide whether a fingerprint short-circuit is safe.
    func bookCount(for library: Library) -> Int {
        let context = ModelContext(modelContainer)
        let serverURL = library.serverURL
        let libraryId = library.id
        backfillServerURL(serverURL: serverURL, libraryId: libraryId, context: context)
        let descriptor = FetchDescriptor<PersistedBook>(
            predicate: #Predicate { $0.serverURL == serverURL && $0.libraryId == libraryId }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }
}
