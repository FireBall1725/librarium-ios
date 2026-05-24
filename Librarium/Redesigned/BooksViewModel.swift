// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

enum BookSortOption: String, CaseIterable, Identifiable {
    case titleAsc, titleDesc
    case authorAsc, authorDesc
    case recentlyAdded, oldestFirst
    case newestRelease, oldestRelease

    var id: String { rawValue }
    var label: String {
        switch self {
        case .titleAsc:       return "Title (A–Z)"
        case .titleDesc:      return "Title (Z–A)"
        case .authorAsc:      return "Author (A–Z)"
        case .authorDesc:     return "Author (Z–A)"
        case .recentlyAdded:  return "Recently added"
        case .oldestFirst:    return "Oldest added"
        case .newestRelease:  return "Newest release"
        case .oldestRelease:  return "Oldest release"
        }
    }
    var field: String {
        switch self {
        case .titleAsc, .titleDesc:              return "title"
        case .authorAsc, .authorDesc:            return "author"
        case .recentlyAdded, .oldestFirst:       return "created_at"
        case .newestRelease, .oldestRelease:     return "publish_date"
        }
    }
    var dir: String {
        switch self {
        case .titleAsc, .authorAsc, .oldestFirst, .oldestRelease:      return "asc"
        case .titleDesc, .authorDesc, .recentlyAdded, .newestRelease:  return "desc"
        }
    }
}

@Observable
final class BooksViewModel {
    var books: [Book] = []
    var total = 0
    var page = 1
    let perPage = 25
    var isLoading = false
    var isLoadingMore = false
    var error: String?

    var searchText = ""
    var selectedTag: Tag?
    var selectedMediaType: MediaType?
    var selectedLetter: String?
    var sortOption: BookSortOption = .titleAsc
    var availableTags: [Tag] = []
    var availableMediaTypes: [MediaType] = []
    var availableLetters: Set<String> = []

    var hasMore: Bool { books.count < total }
    var hasActiveFilters: Bool {
        !searchText.isEmpty || selectedTag != nil || selectedMediaType != nil || selectedLetter != nil
    }

    func load(client: APIClient, libraryId: String) async {
        isLoading = true; error = nil; page = 1
        let t0 = Date()
        print("📚 [BooksVM] load() start offline=false lib=\(libraryId)")

        let metadataTask = Task { await self.loadMetadata(client: client, libraryId: libraryId) }

        do {
            let paged = try await BookService(client: client).list(
                libraryId: libraryId, query: searchText, page: 1, perPage: perPage,
                tag: selectedTag?.name ?? "", typeFilter: selectedMediaType?.name ?? "",
                letter: selectedLetter ?? "",
                sort: sortOption.field, sortDir: sortOption.dir)
            books = paged.items; total = paged.total
            isLoading = false
            print("📚 [BooksVM] books visible after \(Int(Date().timeIntervalSince(t0)*1000))ms count=\(paged.items.count)/\(paged.total)")
            await metadataTask.value
            print("📚 [BooksVM] load() done after \(Int(Date().timeIntervalSince(t0)*1000))ms")
        } catch {
            if !Self.isCancellation(error) { self.error = error.localizedDescription }
            isLoading = false
            print("📚 [BooksVM] load() failed after \(Int(Date().timeIntervalSince(t0)*1000))ms err=\(error)")
        }
    }

    func loadMetadata(client: APIClient, libraryId: String) async {
        let letters = Task { () -> [String]? in try? await BookService(client: client).letters(libraryId: libraryId) }
        let tags    = Task { () -> [Tag]?    in try? await TagService(client: client).list(libraryId: libraryId) }
        let types   = Task { () -> Result<[MediaType], Error> in
            do { return .success(try await MediaTypeService(client: client).list()) }
            catch { return .failure(error) }
        }

        if let result = await letters.value, availableLetters.isEmpty { availableLetters = Set(result) }
        if let result = await tags.value, availableTags.isEmpty { availableTags = result }
        switch await types.value {
        case .success(let result):
            print("📚 [BooksVM] media-types decoded ok count=\(result.count) first=\(result.first?.displayName ?? "nil")")
            if availableMediaTypes.isEmpty { availableMediaTypes = result }
        case .failure(let err):
            print("🔴 [BooksVM] media-types decode failed: \(err)")
        }
    }

    func loadMore(client: APIClient, libraryId: String) async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        page += 1
        do {
            let paged = try await BookService(client: client).list(
                libraryId: libraryId, query: searchText, page: page, perPage: perPage,
                tag: selectedTag?.name ?? "", typeFilter: selectedMediaType?.name ?? "",
                letter: selectedLetter ?? "",
                sort: sortOption.field, sortDir: sortOption.dir)
            books.append(contentsOf: paged.items); total = paged.total
        } catch {
            page -= 1
            if !Self.isCancellation(error) { self.error = error.localizedDescription }
        }
    }

    func search(client: APIClient, libraryId: String) async {
        page = 1; isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let paged = try await BookService(client: client).list(
                libraryId: libraryId, query: searchText, page: 1, perPage: perPage,
                tag: selectedTag?.name ?? "", typeFilter: selectedMediaType?.name ?? "",
                letter: selectedLetter ?? "",
                sort: sortOption.field, sortDir: sortOption.dir)
            books = paged.items; total = paged.total
        } catch {
            if !Self.isCancellation(error) { self.error = error.localizedDescription }
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let underlying: Error
        if case let APIError.networkError(inner) = error { underlying = inner } else { underlying = error }
        if underlying is CancellationError { return true }
        let ns = underlying as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }
        return false
    }

    func loadFromCache(offlineKey: String) {
        if let cached = LibraryOfflineStore.shared.cachedBooks(for: offlineKey) {
            books = cached; total = cached.count
        }
    }
}
