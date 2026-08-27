// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation
import Observation

/// The books surface, across every library on every account.
///
/// One selection struct drives both requests it makes. The list and the counts
/// take the same parameters because they answer the same question from two
/// sides, and a panel that says "Reading 29" over a list that ignores the tick
/// is the failure that shape exists to prevent.
@MainActor
@Observable
final class BrowseViewModel {

    // MARK: - State

    var books: [Book] = []
    var total = 0
    var facets = BookFacets()
    var selection = BrowseSelection()
    var sort: BookSortOption = .titleAsc

    var isLoading = false
    var isLoadingMore = false
    var error: String?

    private(set) var page = 1
    let perPage = 40

    /// Which server each book came from, so a tap can build a client for the
    /// right one. A book id is only unique within an install; two accounts can
    /// hand back the same id for different books.
    private(set) var serverURL: [String: String] = [:]

    var hasMore: Bool { books.count < total }

    // MARK: - Loading

    func load(appState: AppState) async {
        isLoading = true
        error = nil
        page = 1
        defer { isLoading = false }

        let targets = Self.targets(appState)
        guard !targets.isEmpty else {
            books = []
            total = 0
            facets = BookFacets()
            return
        }

        let selection = self.selection
        let sort = self.sort
        let perPage = self.perPage

        async let listed = Self.fetchPage(1, targets: targets, selection: selection,
                                          sort: sort, perPage: perPage)
        async let counted = Self.fetchFacets(targets: targets, selection: selection)

        let (rows, count, origins) = await listed
        books = rows
        total = count
        serverURL = origins
        facets = await counted
    }

    func loadMore(appState: AppState) async {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let next = page + 1
        let (rows, count, origins) = await Self.fetchPage(
            next, targets: Self.targets(appState), selection: selection,
            sort: sort, perPage: perPage)
        guard !rows.isEmpty else { return }
        page = next
        // By id, not by count. Two accounts paginate independently, so the same
        // book can arrive on two pages when one server runs out before the
        // other, and appending blind puts it in the grid twice.
        var seen = Set(books.map { $0.id })
        for row in rows where !seen.contains(row.id) {
            seen.insert(row.id)
            books.append(row)
        }
        total = max(total, count)
        serverURL.merge(origins) { current, _ in current }
    }

    // MARK: - Fetching

    /// One server and the client that talks to it.
    ///
    /// Built on the main actor before any request goes out. `AppState` is not
    /// `Sendable`, so the alternative is capturing it in a concurrent closure
    /// and hoping.
    struct Target: @unchecked Sendable {
        let url: String
        let client: APIClient
    }

    private static func targets(_ appState: AppState) -> [Target] {
        // Lite libraries live in SwiftData behind a `local://` URL that
        // URLSession cannot open, so including one costs a timeout per page
        // and returns nothing.
        appState.accounts
            .filter { $0.kind != .local && !$0.url.hasPrefix("local://") }
            .map { Target(url: $0.url, client: appState.makeClient(serverURL: $0.url)) }
    }

    private static func fetchPage(
        _ page: Int, targets: [Target], selection: BrowseSelection,
        sort: BookSortOption, perPage: Int
    ) async -> ([Book], Int, [String: String]) {
        var rows: [Book] = []
        var total = 0
        var origins: [String: String] = [:]

        await withTaskGroup(of: (String, Paged<Book>?).self) { group in
            for target in targets {
                group.addTask {
                    let paged = try? await MeBrowseService(client: target.client).books(
                        selection: selection, sort: sort, page: page, perPage: perPage)
                    return (target.url, paged)
                }
            }
            for await (url, paged) in group {
                guard let paged else { continue }
                total += paged.total
                for book in paged.items {
                    origins[book.id] = url
                    rows.append(book)
                }
            }
        }

        // Ranking is the server's job, and with one account this leaves its
        // order untouched. With several there is no server that can rank across
        // them, so the merge happens here rather than showing one account's
        // books above the other's whatever the sort says.
        if targets.count > 1 {
            rows = merge(rows, by: sort)
        }
        return (rows, total, origins)
    }

    private static func fetchFacets(targets: [Target], selection: BrowseSelection) async -> BookFacets {
        var merged = BookFacets()
        await withTaskGroup(of: BookFacets?.self) { group in
            for target in targets {
                group.addTask {
                    try? await MeBrowseService(client: target.client).facets(selection: selection)
                }
            }
            for await result in group {
                guard let result else { continue }
                merged = merged.merged(with: result)
            }
        }
        return merged
    }

    // MARK: - Helpers

    /// Interleaves two servers' pages on the key the reader asked to sort by.
    nonisolated static func merge(_ rows: [Book], by sort: BookSortOption) -> [Book] {
        let ascending = sort.dir == "asc"
        func key(_ b: Book) -> String {
            switch sort {
            case .titleAsc, .titleDesc:          return b.title.librariumSortKey()
            case .authorAsc, .authorDesc:        return (b.contributors.first?.name ?? "").librariumSortKey()
            case .recentlyAdded, .oldestFirst:   return b.createdAt
            case .newestRelease, .oldestRelease: return b.updatedAt
            }
        }
        return rows.sorted { ascending ? key($0) < key($1) : key($0) > key($1) }
    }
}
