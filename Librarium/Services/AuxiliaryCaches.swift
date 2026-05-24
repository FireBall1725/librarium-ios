// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation
import SwiftData

// MARK: - EditionCache

/// SwiftData wrapper for cached editions. One row per book carries
/// the entire edition list; the detail view decodes it on read.
struct EditionCache {
    let modelContainer: ModelContainer

    func upsert(_ editions: [BookEdition], for library: Library, bookId: String, serverAccountID: UUID) {
        guard !library.serverURL.isEmpty else { return }
        let context = ModelContext(modelContainer)
        let id = PersistedBookEditions.compositeID(
            serverURL: library.serverURL, libraryId: library.id, bookId: bookId
        )
        guard let payload = try? JSONEncoder().encode(editions) else { return }
        let existing = try? context.fetch(
            FetchDescriptor<PersistedBookEditions>(predicate: #Predicate { $0.id == id })
        ).first
        if let row = existing {
            row.serverURL = library.serverURL
            row.updatedAt = Date()
            row.payload = payload
        } else {
            context.insert(PersistedBookEditions(
                id: id, serverAccountID: serverAccountID,
                libraryId: library.id, bookId: bookId,
                updatedAt: Date(), payload: payload
            ))
        }
        try? context.save()
    }

    func editions(for library: Library, bookId: String) -> [BookEdition] {
        let context = ModelContext(modelContainer)
        let id = PersistedBookEditions.compositeID(
            serverURL: library.serverURL, libraryId: library.id, bookId: bookId
        )
        guard let row = try? context.fetch(
            FetchDescriptor<PersistedBookEditions>(predicate: #Predicate { $0.id == id })
        ).first else { return [] }
        return (try? JSONDecoder().decode([BookEdition].self, from: row.payload)) ?? []
    }
}

// MARK: - ShelfCache

/// SwiftData wrapper for cached shelf-memberships per book.
struct ShelfCache {
    let modelContainer: ModelContainer

    func upsert(_ shelves: [Shelf], for library: Library, bookId: String, serverAccountID: UUID) {
        guard !library.serverURL.isEmpty else { return }
        let context = ModelContext(modelContainer)
        let id = PersistedBookShelves.compositeID(
            serverURL: library.serverURL, libraryId: library.id, bookId: bookId
        )
        guard let payload = try? JSONEncoder().encode(shelves) else { return }
        let existing = try? context.fetch(
            FetchDescriptor<PersistedBookShelves>(predicate: #Predicate { $0.id == id })
        ).first
        if let row = existing {
            row.serverURL = library.serverURL
            row.updatedAt = Date()
            row.payload = payload
        } else {
            context.insert(PersistedBookShelves(
                id: id, serverAccountID: serverAccountID,
                libraryId: library.id, bookId: bookId,
                updatedAt: Date(), payload: payload
            ))
        }
        try? context.save()
    }

    func shelves(for library: Library, bookId: String) -> [Shelf] {
        let context = ModelContext(modelContainer)
        let id = PersistedBookShelves.compositeID(
            serverURL: library.serverURL, libraryId: library.id, bookId: bookId
        )
        guard let row = try? context.fetch(
            FetchDescriptor<PersistedBookShelves>(predicate: #Predicate { $0.id == id })
        ).first else { return [] }
        return (try? JSONDecoder().decode([Shelf].self, from: row.payload)) ?? []
    }
}

// MARK: - ArcCache

/// SwiftData wrapper for series-arc rows. One row per arc so the
/// series detail can fetch + sort them directly.
struct ArcCache {
    let modelContainer: ModelContainer

    func upsert(_ arcs: [SeriesArc], for library: Library, seriesId: String, serverAccountID: UUID) {
        guard !library.serverURL.isEmpty else { return }
        let context = ModelContext(modelContainer)
        let serverURL = library.serverURL
        let libraryId = library.id

        // Purge the existing arcs for this series so removed arcs go
        // away. Arcs can be renamed/reordered server-side.
        let existing = (try? context.fetch(
            FetchDescriptor<PersistedSeriesArc>(predicate: #Predicate {
                $0.serverURL == serverURL && $0.libraryId == libraryId && $0.seriesId == seriesId
            })
        )) ?? []
        for row in existing { context.delete(row) }

        for arc in arcs {
            let id = PersistedSeriesArc.compositeID(
                serverURL: serverURL, libraryId: libraryId, seriesId: seriesId, arcId: arc.id
            )
            guard let payload = try? JSONEncoder().encode(arc) else { continue }
            context.insert(PersistedSeriesArc(
                id: id, serverAccountID: serverAccountID,
                libraryId: libraryId, seriesId: seriesId, arcId: arc.id,
                position: arc.position, updatedAt: Date(), payload: payload
            ))
        }
        try? context.save()
    }

    func arcs(for library: Library, seriesId: String) -> [SeriesArc] {
        let context = ModelContext(modelContainer)
        let serverURL = library.serverURL
        let libraryId = library.id
        let descriptor = FetchDescriptor<PersistedSeriesArc>(
            predicate: #Predicate {
                $0.serverURL == serverURL && $0.libraryId == libraryId && $0.seriesId == seriesId
            },
            sortBy: [SortDescriptor(\.position)]
        )
        guard let rows = try? context.fetch(descriptor) else { return [] }
        return rows.compactMap { try? JSONDecoder().decode(SeriesArc.self, from: $0.payload) }
    }
}

// MARK: - TagCache

struct TagCache {
    let modelContainer: ModelContainer

    func upsert(_ tags: [Tag], for library: Library, serverAccountID: UUID) {
        guard !library.serverURL.isEmpty else { return }
        let context = ModelContext(modelContainer)
        let serverURL = library.serverURL
        let libraryId = library.id

        let existing = (try? context.fetch(
            FetchDescriptor<PersistedTag>(predicate: #Predicate {
                $0.serverURL == serverURL && $0.libraryId == libraryId
            })
        )) ?? []
        for row in existing { context.delete(row) }

        for tag in tags {
            let id = PersistedTag.compositeID(
                serverURL: serverURL, libraryId: libraryId, tagId: tag.id
            )
            guard let payload = try? JSONEncoder().encode(tag) else { continue }
            context.insert(PersistedTag(
                id: id, serverAccountID: serverAccountID,
                libraryId: libraryId, tagId: tag.id,
                name: tag.name, color: tag.color,
                updatedAt: Date(), payload: payload
            ))
        }
        try? context.save()
    }

    func tags(for library: Library) -> [Tag] {
        let context = ModelContext(modelContainer)
        let serverURL = library.serverURL
        let libraryId = library.id
        let descriptor = FetchDescriptor<PersistedTag>(
            predicate: #Predicate {
                $0.serverURL == serverURL && $0.libraryId == libraryId
            },
            sortBy: [SortDescriptor(\.sortName)]
        )
        guard let rows = try? context.fetch(descriptor) else { return [] }
        return rows.compactMap { try? JSONDecoder().decode(Tag.self, from: $0.payload) }
    }
}

// MARK: - MediaTypeCache

/// Server-wide media types (not per-library). Keyed on the composite
/// `serverURL|mediaTypeId` so two servers with different media-type
/// catalogs stay separate.
struct MediaTypeCache {
    let modelContainer: ModelContainer

    func upsert(_ types: [MediaType], serverURL: String, serverAccountID: UUID) {
        guard !serverURL.isEmpty else { return }
        let context = ModelContext(modelContainer)

        let existing = (try? context.fetch(
            FetchDescriptor<PersistedMediaType>(predicate: #Predicate { $0.serverURL == serverURL })
        )) ?? []
        for row in existing { context.delete(row) }

        for type in types {
            let id = PersistedMediaType.compositeID(serverURL: serverURL, mediaTypeId: type.id)
            guard let payload = try? JSONEncoder().encode(type) else { continue }
            context.insert(PersistedMediaType(
                id: id, serverAccountID: serverAccountID,
                mediaTypeId: type.id, name: type.name, displayName: type.displayName,
                updatedAt: Date(), payload: payload
            ))
        }
        try? context.save()
    }

    func types(serverURL: String) -> [MediaType] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PersistedMediaType>(
            predicate: #Predicate { $0.serverURL == serverURL },
            sortBy: [SortDescriptor(\.displayName)]
        )
        guard let rows = try? context.fetch(descriptor) else { return [] }
        return rows.compactMap { try? JSONDecoder().decode(MediaType.self, from: $0.payload) }
    }
}
