// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation
import SwiftData

/// SwiftData wrapper for the series-list cache. Same shape as BookCache,
/// just for `[Series]`. Series payloads are small enough that we can
/// upsert the full list returned by `SeriesService.list(libraryId:)`
/// without needing pagination — it's a single round-trip per library.
struct SeriesCache {
    let modelContainer: ModelContainer

    func upsert(_ all: [Series], for library: Library, serverAccountID: UUID) {
        guard !library.serverURL.isEmpty else { return }
        let context = ModelContext(modelContainer)
        let encoder = JSONEncoder()
        let serverURL = library.serverURL

        for series in all {
            let id = PersistedSeries.compositeID(
                serverURL: serverURL,
                libraryId: library.id,
                seriesId: series.id
            )
            guard let payload = try? encoder.encode(series) else { continue }
            let existing = try? context.fetch(
                FetchDescriptor<PersistedSeries>(predicate: #Predicate { $0.id == id })
            ).first
            if let row = existing {
                row.serverURL = serverURL
                row.name = series.name
                row.sortName = series.name.librariumSortKey()
                row.bookCount = series.bookCount
                row.updatedAt = Date()
                row.payload = payload
            } else {
                let row = PersistedSeries(
                    id: id,
                    serverAccountID: serverAccountID,
                    libraryId: library.id,
                    seriesId: series.id,
                    name: series.name,
                    bookCount: series.bookCount,
                    updatedAt: Date(),
                    payload: payload
                )
                context.insert(row)
            }
        }
        try? context.save()
    }

    /// All cached series across every library on the given server URL.
    /// Sorted by `sortName` so the offline list matches the api's
    /// natural-sort order.
    ///
    /// We fetch every row and filter in Swift instead of predicating on
    /// `serverURL == serverURL` — older rows can carry an empty serverURL
    /// from the SwiftData migration default, and parsing the composite
    /// `id` is more reliable than depending on the column. Cost is fine
    /// for the offline scale (rare hundreds of series per library).
    func seriesByServer(serverURL: String) -> [Series] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PersistedSeries>(
            sortBy: [SortDescriptor(\.sortName)]
        )
        guard let rows = try? context.fetch(descriptor) else { return [] }
        #if DEBUG
        print("📚 [SeriesCache] total rows in DB: \(rows.count), filtering for serverURL=\(serverURL)")
        #endif
        let filtered = rows.filter { row in
            // Match by stored serverURL OR by id prefix (handles
            // migration-default empty serverURL columns).
            if row.serverURL == serverURL { return true }
            return row.id.hasPrefix("\(serverURL)|")
        }
        #if DEBUG
        print("📚 [SeriesCache] matched rows for \(serverURL): \(filtered.count)")
        #endif
        let decoder = JSONDecoder()
        return filtered.compactMap { try? decoder.decode(Series.self, from: $0.payload) }
    }

    /// Upsert the entries belonging to one series. Called from the
    /// series-detail VM on a successful online load. Replaces the
    /// previous list (positions can change as the user reorders).
    func upsertEntries(_ entries: [SeriesEntry], for library: Library, seriesId: String, serverAccountID: UUID) {
        guard !library.serverURL.isEmpty else { return }
        let context = ModelContext(modelContainer)
        let serverURL = library.serverURL
        let libraryId = library.id

        // Purge existing entries for this series first — positions can
        // shift and old rows would shadow the new layout.
        let existing = (try? context.fetch(
            FetchDescriptor<PersistedSeriesEntry>(
                predicate: #Predicate {
                    $0.serverURL == serverURL && $0.libraryId == libraryId && $0.seriesId == seriesId
                }
            )
        )) ?? []
        for row in existing { context.delete(row) }

        let now = Date()
        for entry in entries {
            let id = PersistedSeriesEntry.compositeID(
                serverURL: serverURL,
                libraryId: libraryId,
                seriesId: seriesId,
                bookId: entry.bookId
            )
            let row = PersistedSeriesEntry(
                id: id,
                serverAccountID: serverAccountID,
                libraryId: libraryId,
                seriesId: seriesId,
                bookId: entry.bookId,
                position: entry.position,
                arcId: entry.arcId,
                updatedAt: now
            )
            context.insert(row)
        }
        try? context.save()
    }

    /// Read cached entries for a series — used by the series-detail
    /// view's offline fallback. Returns entries sorted by position so
    /// the UI can just render them in order.
    func entries(serverURL: String, libraryId: String, seriesId: String) -> [(bookId: String, position: Double, arcId: String?)] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PersistedSeriesEntry>(
            predicate: #Predicate {
                $0.serverURL == serverURL && $0.libraryId == libraryId && $0.seriesId == seriesId
            },
            sortBy: [SortDescriptor(\.position)]
        )
        guard let rows = try? context.fetch(descriptor) else { return [] }
        return rows.map { ($0.bookId, $0.position, $0.arcId) }
    }

    func purge(serverURL: String) {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PersistedSeries>(
            predicate: #Predicate { $0.serverURL == serverURL }
        )
        guard let rows = try? context.fetch(descriptor) else { return }
        for row in rows { context.delete(row) }
        try? context.save()
    }

    func purgeLibrary(serverURL: String, libraryId: String) {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PersistedSeries>(
            predicate: #Predicate { $0.serverURL == serverURL && $0.libraryId == libraryId }
        )
        guard let rows = try? context.fetch(descriptor) else { return }
        for row in rows { context.delete(row) }
        try? context.save()
    }

    private func backfill(context: ModelContext) {
        let descriptor = FetchDescriptor<PersistedSeries>(
            predicate: #Predicate { $0.serverURL.isEmpty || $0.sortName.isEmpty }
        )
        guard let rows = try? context.fetch(descriptor), !rows.isEmpty else { return }
        var dirty = false
        for row in rows {
            if row.serverURL.isEmpty, let pipe = row.id.firstIndex(of: "|") {
                row.serverURL = String(row.id[..<pipe])
                dirty = true
            }
            if row.sortName.isEmpty {
                row.sortName = row.name.librariumSortKey()
                dirty = true
            }
        }
        if dirty { try? context.save() }
    }
}
