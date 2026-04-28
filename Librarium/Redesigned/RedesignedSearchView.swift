// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// Redesigned Search — mockup card #10.
///
/// Cross-type search across the primary account: books (server-side
/// fuzzy via existing list endpoint), series (client-side filter on the
/// per-library list), and contributors (server-wide search endpoint).
/// Results are rendered as a single mixed list with a segmented control
/// at the top to filter by type, plus per-segment counts.
///
/// Multi-server is single-server-only for v1 (primary account); the
/// redesigned profile (mockup card 8) will own the server switcher.
struct RedesignedSearchView: View {
    @Environment(AppState.self) private var appState

    @State private var vm = RedesignedSearchViewModel()
    @State private var searchTask: Task<Void, Never>?
    @State private var pendingDetail: BookDetailRequest?
    @State private var loadedDetail: BookDetailLoaded?
    @State private var selectedSeries: SeriesSearchResult?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.appBackground.ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                        header
                        searchPill
                        if vm.hasQuery {
                            segments
                            results
                        } else {
                            emptyHint
                        }
                    }
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $loadedDetail) { detail in
                RedesignedBookDetailView(library: detail.library, book: detail.book)
            }
            .navigationDestination(item: $selectedSeries) { result in
                RedesignedSeriesDetailView(library: result.library, series: result.series)
            }
        }
        .onChange(of: vm.query) { _, _ in
            searchTask?.cancel()
            let q = vm.query
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await vm.search(query: q, appState: appState)
            }
        }
        .onChange(of: pendingDetail) { _, request in
            guard let request else { return }
            Task { await loadDetail(request: request) }
        }
        .alert("Open", isPresented: Binding(
            get: { vm.stubAlert != nil },
            set: { if !$0 { vm.stubAlert = nil } }
        )) {
            Button("OK") { vm.stubAlert = nil }
        } message: {
            Text(vm.stubAlert ?? "")
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .bottom) {
            Text("Search")
                .font(Theme.Fonts.pageTitle)
                .foregroundStyle(Theme.Colors.appText)
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    // MARK: - Search input

    @ViewBuilder
    private var searchPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Colors.appText3)
            TextField("Search titles, authors, series…", text: $vm.query)
                .font(Theme.Fonts.ui(14, weight: .medium))
                .foregroundStyle(Theme.Colors.appText)
                .tint(Theme.Colors.accent)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !vm.query.isEmpty {
                Button { vm.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Colors.appText3)
                }
            }
            if vm.isLoading {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(Theme.Colors.appText3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.Colors.appLine, lineWidth: 0.5))
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    // MARK: - Segments

    @ViewBuilder
    private var segments: some View {
        HStack(spacing: 4) {
            segmentButton(.all,     label: "All",     count: vm.totalCount)
            segmentButton(.books,   label: "Books",   count: vm.bookResults.count)
            segmentButton(.series,  label: "Series",  count: vm.seriesResults.count)
            segmentButton(.authors, label: "Authors", count: vm.contributorResults.count)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private func segmentButton(_ tag: SearchSegment, label: String, count: Int) -> some View {
        let active = vm.segment == tag
        Button { vm.segment = tag } label: {
            Text("\(label) · \(count)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? Theme.Colors.appText : Theme.Colors.appText2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(active ? Color.white.opacity(0.08) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        VStack(spacing: 0) {
            if vm.totalCount == 0 && !vm.isLoading {
                Text("No matches")
                    .font(Theme.Fonts.cardTitle)
                    .foregroundStyle(Theme.Colors.appText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else {
                if vm.shouldShow(.series) {
                    ForEach(vm.seriesResults) { result in
                        searchRow(seriesResult: result)
                            .onTapGesture { selectedSeries = result }
                    }
                }
                if vm.shouldShow(.books) {
                    ForEach(vm.bookResults) { result in
                        searchRow(bookResult: result)
                            .onTapGesture {
                                pendingDetail = BookDetailRequest(
                                    libraryId: result.library.id,
                                    libraryName: result.library.name,
                                    bookId: result.book.id
                                )
                            }
                    }
                }
                if vm.shouldShow(.authors) {
                    ForEach(vm.contributorResults) { result in
                        searchRow(contributor: result)
                            .onTapGesture { vm.stubAlert = "Contributor detail isn't redesigned yet — opening it lands later." }
                    }
                }
            }
        }
        .padding(.horizontal, 18)
    }

    // MARK: - Result rows

    @ViewBuilder
    private func searchRow(bookResult result: BookSearchResult) -> some View {
        let primaryAuthor = result.book.contributors
            .first(where: { $0.role.caseInsensitiveCompare("author") == .orderedSame })?.name
            ?? result.book.contributors.first?.name
        searchRowShell(
            thumb: AnyView(
                BookCoverImage(
                    url: bookCoverURL(for: result),
                    width: 44,
                    height: 60,
                    title: result.book.title,
                    author: primaryAuthor,
                    readStatus: result.book.userReadStatus
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
            ),
            title: result.book.title,
            subtitle: bookSubtitle(for: result, author: primaryAuthor),
            badge: bookBadge(for: result.book)
        )
    }

    @ViewBuilder
    private func searchRow(seriesResult result: SeriesSearchResult) -> some View {
        searchRowShell(
            thumb: AnyView(
                SeriesMosaic(
                    series: result.series,
                    library: result.library,
                    width: 44,
                    height: 60,
                    cornerRadius: 6
                )
            ),
            title: "\(result.series.name) (series)",
            subtitle: seriesSubtitle(for: result.series),
            badge: ("Series", Theme.Colors.appText2, Color.white.opacity(0.06))
        )
    }

    @ViewBuilder
    private func searchRow(contributor: ContributorResult) -> some View {
        let initials = abbreviation(for: contributor.name)
        searchRowShell(
            thumb: AnyView(
                ZStack {
                    LinearGradient(
                        colors: [Color(hex: 0x6a4d3a), Color(hex: 0x3a2a20)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    Text(initials)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            ),
            title: contributor.name,
            subtitle: "Author",
            badge: ("Author", Theme.Colors.appText2, Color.white.opacity(0.06))
        )
    }

    @ViewBuilder
    private func searchRowShell(
        thumb: AnyView,
        title: String,
        subtitle: String,
        badge: (text: String, fg: Color, bg: Color)?
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                thumb
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Colors.appText)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Colors.appText3)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let badge {
                    Text(badge.text)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(badge.fg)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(badge.bg, in: Capsule())
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            Divider().background(Theme.Colors.appLine)
        }
    }

    // MARK: - Empty hint

    @ViewBuilder
    private var emptyHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(Theme.Colors.appText3)
            Text("Find anything")
                .font(Theme.Fonts.cardTitle)
                .foregroundStyle(Theme.Colors.appText)
            Text("Search by title, author, or series across your libraries.")
                .font(Theme.Fonts.ui(13, weight: .medium))
                .foregroundStyle(Theme.Colors.appText3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(.horizontal, 22)
    }

    // MARK: - Helpers

    private func bookCoverURL(for result: BookSearchResult) -> URL? {
        guard let path = result.book.coverUrl, !path.isEmpty else { return nil }
        return URL(string: result.library.serverURL + path)
    }

    private func bookSubtitle(for result: BookSearchResult, author: String?) -> String {
        var parts: [String] = []
        if let a = author, !a.isEmpty { parts.append(a) }
        if let rating = result.book.userRating, rating > 0 {
            let display = Double(rating) / 2.0
            parts.append("★ \(display.formatted(.number.precision(.fractionLength(1))))")
        }
        if appState.accounts.count > 1 || result.library.name.isEmpty == false {
            // Surface the library name in the subtitle when the user has
            // multiple libraries — otherwise the row would be ambiguous.
            parts.append(result.library.name)
        }
        return parts.joined(separator: " · ")
    }

    private func bookBadge(for book: Book) -> (text: String, fg: Color, bg: Color)? {
        if let pct = book.userProgressPct, pct > 0 && pct < 100 {
            return ("Reading", Theme.Colors.accentStrong, Theme.Colors.accentSoft)
        }
        if let count = book.activeLoanCount, count > 0 {
            return ("Lent", Color(hex: 0x1a1306), Color(hex: 0xf59e0b, opacity: 0.92))
        }
        return nil
    }

    private func seriesSubtitle(for series: Series) -> String {
        var parts: [String] = []
        let count = series.bookCount
        if count > 0 {
            parts.append("\(count) volume\(count == 1 ? "" : "s")")
        } else if let total = series.totalCount, total > 0 {
            parts.append("\(total) volume\(total == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    /// Two-letter (or two-word) abbreviation for series / author thumbs.
    private func abbreviation(for name: String) -> String {
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased()
    }

    // MARK: - Detail loading (book taps)

    private func loadDetail(request: BookDetailRequest) async {
        defer { pendingDetail = nil }
        guard let account = primaryAccount() else { return }
        let client = appState.makeClient(serverURL: account.url)
        do {
            let book: Book = try await BookService(client: client).get(libraryId: request.libraryId, bookId: request.bookId)
            var lib = try await LibraryService(client: client).get(request.libraryId)
            lib.serverURL = account.url
            lib.serverName = account.name
            loadedDetail = BookDetailLoaded(library: lib, book: book)
        } catch {
            // Silently ignore — search row taps shouldn't block on errors.
        }
    }

    private func primaryAccount() -> ServerAccount? {
        if let id = appState.primaryAccountID,
           let primary = appState.accounts.first(where: { $0.id == id }) {
            return primary
        }
        return appState.accounts.first
    }
}

// MARK: - Result types

struct BookSearchResult: Identifiable, Hashable {
    let book: Book
    let library: Library

    var id: String { "\(library.id)|\(book.id)" }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.book.id == rhs.book.id && lhs.library.id == rhs.library.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(book.id)
        hasher.combine(library.id)
    }
}

struct SeriesSearchResult: Identifiable, Hashable {
    let series: Series
    let library: Library

    var id: String { "\(library.id)|\(series.id)" }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.series.id == rhs.series.id && lhs.library.id == rhs.library.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(series.id)
        hasher.combine(library.id)
    }
}

enum SearchSegment: Hashable {
    case all, books, series, authors
}

// MARK: - View model

@Observable
final class RedesignedSearchViewModel {
    var query: String = ""
    var segment: SearchSegment = .all

    var bookResults: [BookSearchResult] = []
    var seriesResults: [SeriesSearchResult] = []
    var contributorResults: [ContributorResult] = []

    var isLoading = false
    var stubAlert: String?

    /// Runs against the primary account. Cross-type fan-out: each library
    /// contributes books + series; contributors come from the server-wide
    /// endpoint so they're per-server (not per-library).
    func search(query: String, appState: AppState) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            bookResults = []
            seriesResults = []
            contributorResults = []
            return
        }

        guard let account = Self.primaryAccount(appState: appState) else { return }
        let client = appState.makeClient(serverURL: account.url)

        isLoading = true
        defer { isLoading = false }

        // Fetch the user's libraries on this server so we know what to
        // fan out across. Cached results aren't re-fetched here yet —
        // search hits live every keystroke.
        let libraries: [Library]
        do {
            var libs = try await LibraryService(client: client).list()
            for i in libs.indices {
                libs[i].serverURL = account.url
                libs[i].serverName = account.name
            }
            libraries = libs
        } catch {
            return
        }

        async let books = Self.fanOutBooks(client: client, libraries: libraries, query: trimmed)
        async let series = Self.fanOutSeries(client: client, libraries: libraries, query: trimmed)
        async let contributors = Self.searchContributors(client: client, query: trimmed)

        if let value = try? await books { bookResults = value }
        if let value = try? await series { seriesResults = value }
        if let value = try? await contributors { contributorResults = value }
    }

    private static func fanOutBooks(client: APIClient, libraries: [Library], query: String) async throws -> [BookSearchResult] {
        // 100 per library covers typical "all volumes of a long-running
        // series" queries without needing a paginated infinite-scroll on
        // the search screen. If a single query genuinely exceeds 100
        // matches in one library, we'd want a "show more" affordance —
        // tracked for a later pass.
        var out: [BookSearchResult] = []
        try await withThrowingTaskGroup(of: (Library, [Book]).self) { group in
            for lib in libraries {
                group.addTask {
                    let page = try await BookService(client: client).list(
                        libraryId: lib.id, query: query, page: 1, perPage: 100,
                        tag: "", typeFilter: "", letter: "",
                        sort: "title", sortDir: "asc"
                    )
                    return (lib, page.items)
                }
            }
            for try await (lib, books) in group {
                out.append(contentsOf: books.map { BookSearchResult(book: $0, library: lib) })
            }
        }
        return out.sorted { $0.book.title.localizedStandardCompare($1.book.title) == .orderedAscending }
    }

    private static func fanOutSeries(client: APIClient, libraries: [Library], query: String) async throws -> [SeriesSearchResult] {
        // Series doesn't have a server-side `?q=`, so pull each library's
        // full list and filter client-side. The lists are small (typically
        // <100) so this is fine for v1.
        let q = query.lowercased()
        var out: [SeriesSearchResult] = []
        try await withThrowingTaskGroup(of: (Library, [Series]).self) { group in
            for lib in libraries {
                group.addTask {
                    let s = (try? await SeriesService(client: client).list(libraryId: lib.id)) ?? []
                    return (lib, s)
                }
            }
            for try await (lib, allSeries) in group {
                let matches = allSeries.filter { $0.name.lowercased().contains(q) }
                out.append(contentsOf: matches.map { SeriesSearchResult(series: $0, library: lib) })
            }
        }
        return out.sorted { $0.series.name.localizedStandardCompare($1.series.name) == .orderedAscending }
    }

    private static func searchContributors(client: APIClient, query: String) async throws -> [ContributorResult] {
        try await ContributorService(client: client).search(query: query)
    }

    var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var totalCount: Int {
        bookResults.count + seriesResults.count + contributorResults.count
    }

    func shouldShow(_ kind: SearchSegment) -> Bool {
        if segment == .all { return true }
        return segment == kind
    }

    static func primaryAccount(appState: AppState) -> ServerAccount? {
        if let id = appState.primaryAccountID,
           let primary = appState.accounts.first(where: { $0.id == id }) {
            return primary
        }
        return appState.accounts.first
    }
}
