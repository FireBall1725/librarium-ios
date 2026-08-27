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

    /// True once a load has finished with something to show. A cancelled
    /// attempt does not count: the whole point is that the next chance to run
    /// tries again rather than leaving an empty shelf on screen forever.
    private(set) var hasLoaded = false

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
            hasLoaded = true
            return
        }

        let selection = self.selection
        let sort = self.sort
        let perPage = self.perPage

        async let listed = Self.fetchPage(1, targets: targets, selection: selection,
                                          sort: sort, perPage: perPage)
        async let counted = Self.fetchFacets(targets: targets, selection: selection)

        let (rows, count, origins, failure) = await listed
        books = rows
        total = count
        serverURL = origins
        error = failure
        facets = await counted
        hasLoaded = failure == nil && !Task.isCancelled
    }

    func loadMore(appState: AppState) async {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let next = page + 1
        let (rows, count, origins, _) = await Self.fetchPage(
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

    /// What one account answered, or why it did not.
    private struct PageResult: @unchecked Sendable {
        let url: String
        let paged: Paged<Book>?
        let failure: String?
    }

    private static func fetchPage(
        _ page: Int, targets: [Target], selection: BrowseSelection,
        sort: BookSortOption, perPage: Int
    ) async -> ([Book], Int, [String: String], String?) {
        var rows: [Book] = []
        var total = 0
        var origins: [String: String] = [:]
        var failures: [String] = []

        await withTaskGroup(of: PageResult.self) { group in
            for target in targets {
                group.addTask {
                    do {
                        let paged = try await MeBrowseService(client: target.client).books(
                            selection: selection, sort: sort, page: page, perPage: perPage)
                        return PageResult(url: target.url, paged: paged, failure: nil)
                    } catch {
                        // Kept rather than swallowed. Every failure here used to
                        // render as an empty shelf, which is the same picture a
                        // new account gives and says nothing about what broke.
                        //
                        // Except cancellation, which is not a failure: a view
                        // that goes away mid-request cancels it, and reporting
                        // that puts "cancelled" in front of someone who did
                        // nothing but switch tabs.
                        return PageResult(url: target.url, paged: nil,
                                          failure: isCancellation(error)
                                              ? nil : error.localizedDescription)
                    }
                }
            }
            for await result in group {
                guard let paged = result.paged else {
                    if let failure = result.failure { failures.append(failure) }
                    continue
                }
                total += paged.total
                for book in paged.items {
                    origins[book.id] = result.url
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
        // Only when nothing came back. One server of two being unreachable is
        // a partial answer, not an error worth an alert over the half that
        // loaded.
        let failure = rows.isEmpty ? failures.first : nil
        return (rows, total, origins, failure)
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

    /// Whether an error is the request being called off rather than failing.
    ///
    /// URLSession reports it as `NSURLErrorCancelled`, which localises to the
    /// single word "cancelled" and reads, to anyone who sees it, like the app
    /// giving up for no reason.
    nonisolated static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let underlying: Error
        if case let APIError.networkError(inner) = error { underlying = inner } else { underlying = error }
        if underlying is CancellationError { return true }
        let ns = underlying as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }

    /// Interleaves two servers' pages on the key the reader asked to sort by.
    ///
    /// Only reached with more than one account. With one, the server has
    /// already ordered the page and this would be a second opinion about a
    /// question already answered.
    nonisolated static func merge(_ rows: [Book], by sort: BookSortOption) -> [Book] {
        let ascending = sort.dir == "asc"

        func text(_ b: Book) -> String {
            switch sort {
            case .titleAsc, .titleDesc:   return b.title.librariumSortKey()
            case .authorAsc, .authorDesc: return (b.contributors.first?.name ?? "").librariumSortKey()
            default: return ""
            }
        }

        func number(_ b: Book) -> Double {
            switch sort {
            case .recentlyAdded, .oldestFirst:
                // Parsed rather than compared as text. Two servers in different
                // zones write the same instant with different offsets, and
                // string order puts "…-04:00" before "…+01:00" whatever the
                // clock says.
                return (try? Date(b.createdAt, strategy: .iso8601)) .map(\.timeIntervalSince1970) ?? 0
            case .newestRelease, .oldestRelease:
                return Double(b.publishYear ?? 0)
            default:
                return 0
            }
        }

        switch sort {
        case .titleAsc, .titleDesc, .authorAsc, .authorDesc:
            return rows.sorted { ascending ? text($0) < text($1) : text($0) > text($1) }
        default:
            return rows.sorted { ascending ? number($0) < number($1) : number($0) > number($1) }
        }
    }
}
