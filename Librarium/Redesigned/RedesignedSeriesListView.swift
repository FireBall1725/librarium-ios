// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftData
import SwiftUI

/// Top-level Series tab — browses every series across the primary
/// account's libraries. Series themselves don't have a mockup of their
/// own, so this borrows the editorial-list shape from the search rows:
/// a stacked-cover thumb, name, "N volumes · status" subtitle, optional
/// library badge for multi-library users, and chevron.
///
/// Multi-server v1 limitation: scopes to the primary account. The user's
/// other servers are ignored here; cross-server aggregation lands later.
struct RedesignedSeriesListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @State private var vm = RedesignedSeriesListViewModel()
    @State private var selectedSeries: SeriesListEntry?
    @State private var showFilters = false
    @State private var searchTask: Task<Void, Never>?
    @State private var views: [SavedList] = []
    @State private var showSaveView = false
    @State private var newViewName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        searchPill
                        SavedViewsBar(
                            views: views,
                            activeID: activeViewID,
                            canSave: vm.selection.activeCount > 0 || !vm.selection.query.isEmpty,
                            onOpen: { open($0) },
                            onSave: {
                                newViewName = ""
                                showSaveView = true
                            }
                        )
                        .padding(.bottom, 10)
                        SeriesFilterPills(
                            selection: $vm.selection, facets: vm.facets,
                            onChange: { reload() }
                        )
                        .padding(.bottom, 12)
                        listContent
                    }
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task(id: appState.accounts.map(\.id)) {
                await loadViews()
                if let fallback = views.first(where: { $0.isDefault }), vm.entries.isEmpty {
                    vm.selection = SeriesSelection(query: fallback.filterQuery)
                }
                await vm.load(appState: appState, modelContainer: modelContext.container)
            }
            .refreshable {
                await vm.load(appState: appState, modelContainer: modelContext.container)
            }
            .navigationDestination(item: $selectedSeries) { entry in
                RedesignedSeriesDetailView(library: entry.library, series: entry.series)
            }
            .sheet(isPresented: $showSaveView) {
                SaveViewSheet(name: $newViewName) { saveView() }
            }
            .sheet(isPresented: $showFilters) {
                SeriesFilterSheet(
                    selection: $vm.selection, facets: vm.facets,
                    onChange: { reload() }
                )
                .presentationDetents([.large])
            }
            .onChange(of: vm.selection.query) { _, _ in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    await vm.load(appState: appState, modelContainer: modelContext.container)
                }
            }
            .onChange(of: vm.sort) { _, _ in reload() }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Librarium · Browse")
                .font(Theme.Fonts.ui(12, weight: .medium))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.appText3)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Series")
                        .font(Theme.Fonts.pageTitle)
                        .foregroundStyle(Theme.Colors.appText)
                    if !vm.entries.isEmpty {
                        Text(runSummary)
                            .font(Theme.Fonts.ui(13, weight: .medium))
                            .foregroundStyle(Theme.Colors.appText3)
                    }
                }
                Spacer()
                sortMenu
                filterButton
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    // MARK: - Search pill

    @ViewBuilder
    private var searchPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Colors.appText3)
            TextField("Search series", text: $vm.selection.query)
                .font(Theme.Fonts.ui(14, weight: .medium))
                .foregroundStyle(Theme.Colors.appText)
                .tint(Theme.Colors.accent)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !vm.selection.query.isEmpty {
                Button { vm.selection.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Colors.appText3)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.Colors.appLine, lineWidth: 0.5))
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
    }

    // MARK: - List

    /// How many runs, and how many volumes are missing across them. The second
    /// number is the reason to open this surface at all, so it belongs in the
    /// header rather than only inside each row.
    private var runSummary: String {
        let runs = vm.entries.count
        let missing = vm.entries.compactMap { $0.series.missingCount }.reduce(0, +)
        let base = runs == 1 ? "1 series" : "\(runs) series"
        return missing > 0 ? "\(base) · \(missing) missing" : base
    }

    private func reload() {
        searchTask?.cancel()
        Task { await vm.load(appState: appState, modelContainer: modelContext.container) }
    }

    /// Matched on the query string rather than on which chip was tapped, so
    /// changing a filter after opening a view unticks it honestly.
    private var activeViewID: String? {
        let current = vm.selection.queryString()
        return views.first(where: { $0.filterQuery == current })?.id
    }

    private func open(_ view: SavedList) {
        vm.selection = SeriesSelection(query: view.filterQuery)
        reload()
    }

    private func loadViews() async {
        let client = appState.makePrimaryClient()
        views = (try? await ListService(client: client).savedViews(surface: "series")) ?? []
    }

    private func saveView() {
        let name = newViewName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let query = vm.selection.queryString()
        Task {
            let client = appState.makePrimaryClient()
            try? await ListService(client: client)
                .saveView(name: name, surface: "series", query: query)
            await loadViews()
        }
    }

    @ViewBuilder
    private var sortMenu: some View {
        Menu {
            ForEach(SeriesSortOption.allCases) { option in
                Button {
                    vm.sort = option
                } label: {
                    if vm.sort == option {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Colors.appText2)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.06), in: Circle())
                .overlay(Circle().stroke(Theme.Colors.appLine, lineWidth: 0.5))
        }
        .accessibilityLabel("Sort")
    }

    @ViewBuilder
    private var filterButton: some View {
        let n = vm.selection.activeCount
        Button { showFilters = true } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(n > 0 ? Theme.Colors.accentStrong : Theme.Colors.appText2)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle().fill(n > 0 ? Theme.Colors.accentSoft : Color.white.opacity(0.06))
                    )
                    .overlay(Circle().stroke(n > 0 ? Color.clear : Theme.Colors.appLine, lineWidth: 0.5))
                if n > 0 {
                    Text("\(n)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.Colors.appBackground)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Theme.Colors.accentStrong))
                        .offset(x: 2, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(n > 0 ? "Filter, \(n) applied" : "Filter")
    }

    @ViewBuilder
    private var listContent: some View {
        let filtered = vm.entries
        if vm.isLoading && vm.entries.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 240)
                .tint(Theme.Colors.appText2)
        } else if vm.entries.isEmpty {
            emptyState
        } else if filtered.isEmpty {
            VStack(spacing: 8) {
                Text("No matches")
                    .font(Theme.Fonts.cardTitle)
                    .foregroundStyle(Theme.Colors.appText)
                Text("Try a different search or clear the filters.")
                    .font(Theme.Fonts.ui(13, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText3)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, entry in
                    Button { selectedSeries = entry } label: {
                        seriesRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                    if idx != filtered.count - 1 {
                        Divider().background(Theme.Colors.appLine).padding(.leading, 22 + 44 + 12)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: emptyStateIcon)
                .font(.system(size: 32))
                .foregroundStyle(Theme.Colors.appText3)
            Text(emptyStateTitle)
                .font(Theme.Fonts.cardTitle)
                .foregroundStyle(Theme.Colors.appText)
            Text(emptyStateMessage)
                .font(Theme.Fonts.ui(13, weight: .medium))
                .foregroundStyle(Theme.Colors.appText3)
                .multilineTextAlignment(.center)
            #if DEBUG
            // Surface SwiftData state so we can see whether the cache
            // is populated vs whether the read predicate is filtering
            // everything out. Drops out of release builds.
            Text(debugCacheLine)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.Colors.appText3.opacity(0.6))
                .padding(.top, 8)
            #endif
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(.horizontal, 22)
    }

    private var isOfflineForSeries: Bool {
        let remotes = appState.accounts.filter { $0.kind == .remote && !$0.needsReauth }
        return !remotes.isEmpty && remotes.allSatisfy { NetworkMonitor.shared.shouldSkipAPI(for: $0.url) }
    }

    private var emptyStateIcon: String {
        isOfflineForSeries ? "icloud.slash" : "list.number"
    }

    private var emptyStateTitle: String {
        isOfflineForSeries ? "No series cached" : "No series yet"
    }

    private var emptyStateMessage: String {
        isOfflineForSeries
            ? "Connect to the server, open the Series tab, and let it sync — then series will appear here offline."
            : "Group books together by adding them to a series."
    }

    #if DEBUG
    private var debugCacheLine: String {
        let cache = SeriesCache(modelContainer: modelContext.container)
        let cacheCounts = appState.accounts
            .filter { $0.kind == .remote }
            .map { ($0.name, cache.seriesByServer(serverURL: $0.url).count) }
        let cacheStr = cacheCounts.map { "\($0.0):\($0.1)" }.joined(separator: " ")
        let netStr = NetworkMonitor.shared.isOnline ? "online" : "offline"
        let acctStr = appState.accounts.map { acct -> String in
            let k = acct.kind == .local ? "L" : "R"
            let r = acct.needsReauth ? "!" : ""
            return "\(k)\(r)"
        }.joined(separator: ",")
        return "cache[\(cacheStr)] vm:\(vm.entries.count) net:\(netStr) accts:[\(acctStr)]"
    }
    #endif

    // MARK: - Row

    @ViewBuilder
    private func seriesRow(entry: SeriesListEntry) -> some View {
        HStack(spacing: 12) {
            SeriesMosaic(series: entry.series, library: entry.library, size: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.series.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(subtitle(for: entry))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText3)
                    .lineLimit(1)
                if let missing = entry.series.missingCount, missing > 0 {
                    // The number people open this page for. A run reads
                    // "6 of 7" everywhere else on the row; this says what to do
                    // about the difference.
                    Text(missing == 1 ? "1 missing" : "\(missing) missing")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.Colors.warn)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Colors.appText3)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func subtitle(for entry: SeriesListEntry) -> String {
        let series = entry.series
        // "6 of 7" rather than "7 vols". The run's length is what a publisher
        // decided; how much of it is on the shelf is what the reader owns, and
        // printing only the first made a complete run and a barely-started one
        // read identically.
        let held: String
        if let total = series.totalCount, total > 0 {
            held = "\(series.bookCount) of \(total) vols"
        } else {
            held = series.bookCount == 1 ? "1 vol" : "\(series.bookCount) vols"
        }
        var parts = [held, SeriesFacetLabels.status(series.status.isEmpty ? "ongoing" : series.status).lowercased()]
        if let stars = series.ratingStars {
            parts.append(stars == stars.rounded()
                ? "★ \(Int(stars))"
                : String(format: "★ %.1f", stars))
        }
        if vm.showLibraryBadge, !entry.library.name.isEmpty {
            parts.append(entry.library.name)
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - View model

/// One server's slice of the cross-server series list. Aggregated by
/// `load` into the flat sorted list the view consumes.
private struct PerAccountSeries {
    let libraryCount: Int
    let entries: [SeriesListEntry]
    var facets = SeriesFacets()
}

struct SeriesListEntry: Identifiable, Hashable {
    let series: Series
    let library: Library

    var id: String { "\(library.serverURL)|\(library.id)|\(series.id)" }

    static func == (lhs: SeriesListEntry, rhs: SeriesListEntry) -> Bool {
        lhs.series.id == rhs.series.id
            && lhs.library.id == rhs.library.id
            && lhs.library.serverURL == rhs.library.serverURL
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(series.id)
        hasher.combine(library.id)
        hasher.combine(library.serverURL)
    }
}

@Observable
final class RedesignedSeriesListViewModel {
    var entries: [SeriesListEntry] = []
    var facets = SeriesFacets()
    var selection = SeriesSelection()
    var sort: SeriesSortOption = .name
    var isLoading = true
    /// True when the user has more than one library on the primary
    /// account — otherwise the per-row library badge is redundant.
    var showLibraryBadge = false

    /// Fan-out across every remote account. Each account contributes its
    /// own libraries → series; we flatten across all servers and sort by
    /// name. Lite accounts have no api so they're skipped; their local
    /// series will get layered in when the SwiftData book store lands.
    func load(appState: AppState, modelContainer: ModelContainer) async {
        isLoading = true
        defer { isLoading = false }

        // Offline / unreachable-server path runs FIRST and ignores
        // `needsReauth` — the user can't re-auth while offline, but
        // their cached series should still be browsable. Auth state
        // is only relevant for the online path below.
        let allRemote = appState.accounts.filter { $0.kind == .remote }
        let offline = allRemote.allSatisfy { NetworkMonitor.shared.shouldSkipAPI(for: $0.url) }
        if !allRemote.isEmpty, offline {
            await loadOffline(remotes: allRemote, modelContainer: modelContainer)
            return
        }

        let remotes = allRemote.filter { !$0.needsReauth }
        guard !remotes.isEmpty else {
            entries = []
            showLibraryBadge = false
            return
        }

        var collected: [SeriesListEntry] = []
        var totalLibCount = 0
        var counts = SeriesFacets()
        let cache = SeriesCache(modelContainer: modelContainer)
        let selection = self.selection
        let sort = self.sort

        await withTaskGroup(of: PerAccountSeries.self) { group in
            for account in remotes {
                let url = account.url
                let name = account.name
                let accountID = account.id
                group.addTask {
                    let client = await appState.makeClient(serverURL: url)
                    var libs: [Library]
                    do {
                        libs = try await LibraryService(client: client).list()
                        for i in libs.indices {
                            libs[i].serverURL = url
                            libs[i].serverName = name
                        }
                        NetworkMonitor.shared.markServerReachable(url)
                    } catch {
                        // Server unreachable — fall back to SwiftData
                        // for whatever this account has cached. Mark the
                        // server unreachable so subsequent visits within
                        // a minute skip the timeout and use the cache
                        // directly.
                        NetworkMonitor.shared.markServerUnreachable(url)
                        let cached = await Self.offlineSeriesForAccount(
                            serverURL: url,
                            serverName: name,
                            modelContainer: modelContainer
                        )
                        return PerAccountSeries(libraryCount: cached.libraryCount, entries: cached.entries)
                    }
                    // One request for the whole account. This used to ask
                    // `/libraries/{id}/series` once per library, so the request
                    // count grew with the collection and none of the answers
                    // carried a count: no volumes held, no volumes missing, no
                    // rating, and no facets to narrow by.
                    let byID = Dictionary(uniqueKeysWithValues: libs.map { ($0.id, $0) })
                    let page = try? await MeBrowseService(client: client)
                        .series(selection: selection, sort: sort)
                    let list = page?.items ?? []

                    var slice: [SeriesListEntry] = []
                    for series in list {
                        // A run whose library the caller only reaches through a
                        // shared list arrives without one. Falling back to any
                        // library on the same server keeps its covers pointed
                        // at the right host rather than dropping the row.
                        guard let lib = byID[series.libraryId] ?? libs.first else { continue }
                        slice.append(SeriesListEntry(series: series, library: lib))
                    }

                    // Write through per library, which is how the offline cache
                    // is keyed. Best-effort: failure just means the offline tab
                    // stays empty until the next online visit.
                    for (libID, group) in Dictionary(grouping: list, by: { $0.libraryId }) {
                        guard let lib = byID[libID] else { continue }
                        cache.upsert(group, for: lib, serverAccountID: accountID)
                    }

                    return PerAccountSeries(libraryCount: libs.count, entries: slice,
                                            facets: page?.facets ?? SeriesFacets())
                }
            }
            for await chunk in group {
                totalLibCount += chunk.libraryCount
                collected.append(contentsOf: chunk.entries)
                counts = counts.merged(with: chunk.facets)
            }
        }

        showLibraryBadge = totalLibCount > 1
        facets = counts
        // Runs with volumes nobody has. Derived from the counts already on
        // every row rather than asked for, because the server has no facet for
        // it and the subtraction is the same either way.
        if selection.incompleteOnly {
            collected = collected.filter { ($0.series.missingCount ?? 0) > 0 }
        }
        // Name order is the server's when there is one account, and a merge
        // when there are two, because no server can order across them.
        entries = sort == .name
            ? collected.sorted {
                $0.series.name.localizedStandardCompare($1.series.name) == .orderedAscending
            }
            : collected
    }

    /// Offline path. Reads every cached `Series` row for each remote
    /// account and stamps each one with its library context so the
    /// mosaic's cover lookup still hits the right server URL.
    private func loadOffline(remotes: [ServerAccount], modelContainer: ModelContainer) async {
        var collected: [SeriesListEntry] = []
        var totalLibCount = 0

        for account in remotes {
            let chunk = await Self.offlineSeriesForAccount(
                serverURL: account.url,
                serverName: account.name,
                modelContainer: modelContainer
            )
            totalLibCount += chunk.libraryCount
            collected.append(contentsOf: chunk.entries)
        }

        showLibraryBadge = totalLibCount > 1
        entries = collected.sorted {
            $0.series.name.localizedStandardCompare($1.series.name) == .orderedAscending
        }
    }

    /// Per-account offline read. Pulled out so both the airplane-mode
    /// short-circuit AND the online-fan-out catch can call it without
    /// duplication. Each entry is stamped with the right library +
    /// server URL so detail nav + cover lookups still work.
    private static func offlineSeriesForAccount(
        serverURL: String,
        serverName: String,
        modelContainer: ModelContainer
    ) async -> PerAccountSeries {
        let cache = SeriesCache(modelContainer: modelContainer)
        let store = LibraryOfflineStore.shared
        let libs = store.cachedLibraries().filter { $0.serverURL == serverURL }
        let libsByID = Dictionary(uniqueKeysWithValues: libs.map { ($0.id, $0) })
        let serverSeries = cache.seriesByServer(serverURL: serverURL)
        var entries: [SeriesListEntry] = []
        for series in serverSeries {
            var lib = libsByID[series.libraryId] ?? Library(
                id: series.libraryId,
                name: "Library",
                description: "",
                slug: "",
                ownerId: "",
                isPublic: false,
                createdAt: "",
                updatedAt: "",
                bookCount: nil,
                readingCount: nil,
                readCount: nil
            )
            lib.serverURL = serverURL
            lib.serverName = serverName
            entries.append(SeriesListEntry(series: series, library: lib))
        }
        return PerAccountSeries(libraryCount: libs.count, entries: entries)
    }

    private func primaryAccount(appState: AppState) -> ServerAccount? {
        if let id = appState.primaryAccountID,
           let primary = appState.accounts.first(where: { $0.id == id }) {
            return primary
        }
        return appState.accounts.first
    }
}

// MARK: - Series mosaic

/// 2×2 collage of the series's first 4 book covers — auto-derived from
/// `series.preview_books`. Empty slots fall back to a per-tile gradient
/// so the grid always reads as 4 cells. Mirrors the web's `SeriesMosaic`
/// shape so a series renders the same on either client.
///
/// Width and height are configured separately so callers can choose
/// either a square (series-list 56×56) or a 2:3 thumb (search-row
/// 44×60) without forking the implementation.
struct SeriesMosaic: View {
    let series: Series
    let library: Library
    let width: CGFloat
    let height: CGFloat
    /// Outer corner radius — defaults to 8 for the larger square; smaller
    /// thumbs in search rows want a tighter 6 to match neighbouring book
    /// covers.
    var cornerRadius: CGFloat = 8

    @Environment(AppState.self) private var appState

    /// Convenience for callers that want a square mosaic.
    init(series: Series, library: Library, size: CGFloat, cornerRadius: CGFloat = 8) {
        self.init(series: series, library: library, width: size, height: size, cornerRadius: cornerRadius)
    }

    init(series: Series, library: Library, width: CGFloat, height: CGFloat, cornerRadius: CGFloat = 8) {
        self.series = series
        self.library = library
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        let tiles = Array(series.previewBooks.prefix(4))
        // Pad to 4 with nil so the grid always renders consistent cells.
        let padded: [SeriesPreviewBook?] = tiles + Array(repeating: nil, count: max(0, 4 - tiles.count))
        Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            GridRow {
                tile(padded[0], idx: 0)
                tile(padded[1], idx: 1)
            }
            GridRow {
                tile(padded[2], idx: 2)
                tile(padded[3], idx: 3)
            }
        }
        .frame(width: width, height: height)
        // Nothing on the shelf, so nothing in colour. A run that exists only as
        // volumes nobody has drew a full-strength mosaic from its covers and
        // read exactly like one the reader owns.
        .saturation(series.bookCount == 0 ? 0 : 1)
        .opacity(series.bookCount == 0 ? 0.55 : 1)
        .background(Theme.Colors.appLine)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
    }

    @ViewBuilder
    private func tile(_ book: SeriesPreviewBook?, idx: Int) -> some View {
        let tileW = width / 2
        let tileH = height / 2
        if let book, let url = coverURL(for: book) {
            // Reuse BookCoverImage so we get bearer-token auth + the
            // generated-fallback when the cover URL fails to load.
            BookCoverImage(
                url: url,
                width: tileW,
                height: tileH,
                title: book.title,
                author: nil
            )
        } else {
            mosaicGradient(idx: idx, title: book?.title ?? series.name, tileW: tileW, tileH: tileH)
                .frame(width: tileW, height: tileH)
        }
    }

    private func coverURL(for book: SeriesPreviewBook) -> URL? {
        library.coverURL(for: book.coverUrl)
    }

    /// Per-tile gradient placeholder — picks one of 4 jewel-tone palettes
    /// from the title's first byte + tile index so empty cells still
    /// look intentional rather than blank.
    @ViewBuilder
    private func mosaicGradient(idx: Int, title: String, tileW: CGFloat, tileH: CGFloat) -> some View {
        let palette = Self.gradient(for: title, idx: idx)
        let glyphSize = max(min(tileW, tileH) * 0.45, 8)
        ZStack {
            LinearGradient(colors: [palette.top, palette.bottom],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(String(title.prefix(1)).uppercased())
                .font(.system(size: glyphSize, weight: .bold))
                .foregroundStyle(.white.opacity(0.30))
        }
    }

    private struct MosaicPalette { let top: Color; let bottom: Color }

    private static let palettes: [MosaicPalette] = [
        MosaicPalette(top: Color(hex: 0xc8508c), bottom: Color(hex: 0xdc8a50)),
        MosaicPalette(top: Color(hex: 0x5064dc), bottom: Color(hex: 0x2cb8c8)),
        MosaicPalette(top: Color(hex: 0x3a8c5a), bottom: Color(hex: 0x8aaa3a)),
        MosaicPalette(top: Color(hex: 0x8c50c8), bottom: Color(hex: 0xc850dc))
    ]

    private static func gradient(for title: String, idx: Int) -> MosaicPalette {
        let firstByte = Int(title.utf8.first ?? 0)
        return palettes[(firstByte + idx) % palettes.count]
    }
}
