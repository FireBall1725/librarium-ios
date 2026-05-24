// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation
import SwiftData

/// Single entry point that pulls **everything** for one library into
/// SwiftData on demand. Replaces the piecemeal "BookCache.syncFull +
/// SeriesCache.upsert + …" approach with one orchestrator. All future
/// trigger points (toggle-on, scene-active, pull-to-refresh) call this.
///
/// What gets cached on each pass:
/// - Library metadata (LibraryOfflineStore JSON — kept for now)
/// - Books (paginated, via BookCache; covers prefetched in parallel)
/// - Series list + per-series entries + per-series arcs
/// - Per-book editions + shelves (parallel, bounded by Swift's task
///   group concurrency)
/// - Tags (library-wide)
/// - Media types (server-wide; deduped by server on the first call)
///
/// "Bounded by Swift's task group concurrency" is the key — Swift caps
/// concurrent child tasks around 64, so 1,500 per-book api calls don't
/// detonate the connection pool.
struct LibrarySync {
    let modelContainer: ModelContainer

    /// Snapshot of progress emitted as the sync moves through its
    /// phases. `progress` is 0.0–1.0; `phase` is a short label like
    /// "books" / "covers" / "editions". UI surfaces this via the
    /// existing LibraryOfflineStore.bookCacheStates pipeline.
    struct Progress {
        let phase: String
        let progress: Double
    }

    @discardableResult
    func run(
        library: Library,
        serverAccountID: UUID,
        accessToken: String?,
        client: APIClient,
        onProgress: (@MainActor (Progress) -> Void)? = nil
    ) async -> Int {
        guard !library.serverURL.isEmpty else { return 0 }

        // 1. Books (paginated) — this is the bulk of the sync. Covers
        // are prefetched inline by BookCache.syncFull.
        let bookCache = BookCache(modelContainer: modelContainer)
        let bookCount = await bookCache.syncFull(
            library: library,
            serverAccountID: serverAccountID,
            accessToken: accessToken,
            client: client,
            onProgress: { pct in
                Task { @MainActor in
                    onProgress?(Progress(phase: "books", progress: pct * 0.7))
                }
            }
        )

        // 2. Tags + media types — small. Server-wide media types
        // dedupe naturally on the cache id.
        await Self.syncTagsAndMediaTypes(
            library: library,
            serverAccountID: serverAccountID,
            client: client,
            modelContainer: modelContainer
        )
        if let onProgress {
            await onProgress(Progress(phase: "tags", progress: 0.72))
        }

        // 3. Series + per-series entries + arcs in parallel.
        await Self.syncSeries(
            library: library,
            serverAccountID: serverAccountID,
            client: client,
            modelContainer: modelContainer,
            onProgress: onProgress
        )

        // 4. Per-book editions + shelves. The big one — N api calls
        // for N books. TaskGroup parallelism caps the wire pressure.
        await Self.syncBookEditionsAndShelves(
            library: library,
            serverAccountID: serverAccountID,
            client: client,
            modelContainer: modelContainer,
            onProgress: onProgress
        )

        if let onProgress {
            await onProgress(Progress(phase: "done", progress: 1.0))
        }
        return bookCount
    }

    // MARK: - Phase: tags + media types

    private static func syncTagsAndMediaTypes(
        library: Library,
        serverAccountID: UUID,
        client: APIClient,
        modelContainer: ModelContainer
    ) async {
        async let tagsTask: [Tag]? = try? await TagService(client: client).list(libraryId: library.id)
        async let typesTask: [MediaType]? = try? await MediaTypeService(client: client).list()

        if let tags = await tagsTask {
            TagCache(modelContainer: modelContainer)
                .upsert(tags, for: library, serverAccountID: serverAccountID)
        }
        if let types = await typesTask {
            MediaTypeCache(modelContainer: modelContainer)
                .upsert(types, serverURL: library.serverURL, serverAccountID: serverAccountID)
        }
    }

    // MARK: - Phase: series + entries + arcs

    private static func syncSeries(
        library: Library,
        serverAccountID: UUID,
        client: APIClient,
        modelContainer: ModelContainer,
        onProgress: (@MainActor (Progress) -> Void)?
    ) async {
        guard let allSeries = try? await SeriesService(client: client).list(libraryId: library.id) else {
            return
        }
        let seriesCache = SeriesCache(modelContainer: modelContainer)
        let arcCache = ArcCache(modelContainer: modelContainer)
        seriesCache.upsert(allSeries, for: library, serverAccountID: serverAccountID)

        // Pull entries + arcs in parallel for every series.
        let total = max(allSeries.count, 1)
        var done = 0
        await withTaskGroup(of: Void.self) { group in
            for series in allSeries {
                let seriesId = series.id
                group.addTask {
                    async let entriesTask: [SeriesEntry]? =
                        try? await SeriesService(client: client).books(libraryId: library.id, seriesId: seriesId)
                    async let arcsTask: [SeriesArc]? =
                        try? await SeriesService(client: client).arcs(libraryId: library.id, seriesId: seriesId)
                    if let entries = await entriesTask {
                        seriesCache.upsertEntries(
                            entries, for: library,
                            seriesId: seriesId, serverAccountID: serverAccountID
                        )
                    }
                    if let arcs = await arcsTask {
                        arcCache.upsert(
                            arcs, for: library,
                            seriesId: seriesId, serverAccountID: serverAccountID
                        )
                    }
                }
            }
            for await _ in group {
                done += 1
                if let onProgress {
                    let pct = 0.72 + (Double(done) / Double(total)) * 0.08
                    await onProgress(Progress(phase: "series", progress: pct))
                }
            }
        }
    }

    // MARK: - Phase: per-book editions + shelves

    private static func syncBookEditionsAndShelves(
        library: Library,
        serverAccountID: UUID,
        client: APIClient,
        modelContainer: ModelContainer,
        onProgress: (@MainActor (Progress) -> Void)?
    ) async {
        // Pull cached book ids so we know what to fan out across. We
        // already cached the books in phase 1; reading them back is
        // cheaper than re-paginating the api.
        let cache = BookCache(modelContainer: modelContainer)
        let books = cache.books(for: library)
        guard !books.isEmpty else { return }
        let editionCache = EditionCache(modelContainer: modelContainer)
        let shelfCache = ShelfCache(modelContainer: modelContainer)

        let total = max(books.count, 1)
        var done = 0
        await withTaskGroup(of: Void.self) { group in
            for book in books {
                let bookId = book.id
                group.addTask {
                    async let editionsTask: [BookEdition]? =
                        try? await BookService(client: client).editions(libraryId: library.id, bookId: bookId)
                    async let shelvesTask: [Shelf]? =
                        try? await BookService(client: client).shelves(libraryId: library.id, bookId: bookId)
                    if let editions = await editionsTask {
                        editionCache.upsert(editions, for: library, bookId: bookId, serverAccountID: serverAccountID)
                    }
                    if let shelves = await shelvesTask {
                        shelfCache.upsert(shelves, for: library, bookId: bookId, serverAccountID: serverAccountID)
                    }
                }
            }
            for await _ in group {
                done += 1
                if let onProgress {
                    let pct = 0.80 + (Double(done) / Double(total)) * 0.20
                    await onProgress(Progress(phase: "editions", progress: pct))
                }
            }
        }
    }
}
