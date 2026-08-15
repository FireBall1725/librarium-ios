// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftData
import SwiftUI

/// Redesigned books grid — mockup card #3.
///
/// Layout: 3-column cover-forward grid on the editorial dark surface.
/// Each tile is the cover (with overlaid rating / progress / lent badges
/// once the api Phase 1 fields land) plus a two-line title + author meta.
///
/// Reuses `BooksViewModel` from the legacy view so paging, search, sort,
/// and offline-cache fall-through stay identical — only the visual layer
/// is new. The advanced filters sheet, bulk select, and letter index
/// from the legacy view are deferred to later passes.
struct RedesignedBooksView: View {
    let library: Library
    @Environment(AppState.self) private var appState
    @Environment(\.libraryBack) private var onBack
    @Environment(\.modelContext) private var modelContext

    @State private var vm = BooksViewModel()
    @State private var searchTask: Task<Void, Never>?
    @State private var showAdd = false
    @State private var showLiteManualAdd = false
    @State private var selectedBook: Book?
    @State private var offlineStore = LibraryOfflineStore.shared

    /// True for a Lite-mode local library. Gates every api call below so
    /// URLSession never sees the synthetic `local://` base URL, and hides
    /// the add-book affordance until the SwiftData book write path lands
    /// (PR2). Single source of truth so adding more api call sites
    /// stays safe.
    private var isLocalLibrary: Bool {
        library.serverURL.hasPrefix("local://")
    }

    /// Whether this library is kept on-device for offline browsing. Lite
    /// libraries are implicitly always cached (their data IS the library),
    /// so the toggle is locked on for them.
    private var isKeptOffline: Bool {
        if isLocalLibrary { return true }
        return offlineStore.isEnabled(for: library.clientKey)
    }

    /// In-progress sync percentage (0.0–1.0) or nil when not syncing.
    /// Driven by `LibraryOfflineStore.bookCacheStates` which the sync
    /// path updates on every page upserted. `@Observable` propagates
    /// the change to this view automatically.
    private var syncProgress: Double? {
        if case .syncing(let p, _) = offlineStore.bookCacheStates[library.clientKey] {
            return p
        }
        return nil
    }

    /// Friendly label for the current sync phase. Updates as the sync
    /// works through books → tags → series → editions/shelves so the
    /// user knows what's happening when the percentage seems stuck.
    private var syncPhaseLabel: String? {
        guard case .syncing(_, let phase) = offlineStore.bookCacheStates[library.clientKey] else {
            return nil
        }
        switch phase {
        case "books":    return "Downloading books"
        case "tags":     return "Downloading tags"
        case "series":   return "Downloading series"
        case "editions": return "Downloading book details"
        case "done":     return "Finishing up"
        default:         return "Downloading library"
        }
    }

    private var isSyncing: Bool { syncProgress != nil }

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    header
                    syncBanner
                    toolbarRow
                    filterRow
                    grid
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            // Lite libraries live entirely in SwiftData — no api to call
            // against (the synthetic `local://` URL would trip URLSession's
            // "unsupported URL" alert). Read straight from BookCache so
            // the grid mirrors whatever LiteBookWriter / LiteManualAddSheet
            // have written, then bail out before the api branch below.
            if isLocalLibrary {
                loadLiteBooks()
                return
            }
            guard vm.books.isEmpty else { return }
            await loadBooks()
        }
        // Re-read SwiftData whenever the sync state ticks forward so the
        // user watches books fill in instead of staring at an empty page
        // until the sync completes. Cheap fetch; sync emits a handful of
        // progress callbacks across the whole pagination.
        .onChange(of: syncProgress) { _, _ in
            guard isKeptOffline else { return }
            let cache = BookCache(modelContainer: modelContext.container)
            let cached = cache.books(for: library)
            if !cached.isEmpty {
                vm.books = cached
                vm.total = cached.count
            }
        }
        .refreshable {
            if isLocalLibrary {
                loadLiteBooks()
                return
            }
            await loadBooks()
        }
        // The scan flow lives in a fullScreenCover above the app shell,
        // so dismissing it does not re-fire .task on this view. Listen
        // for LiteBookWriter's notification and refresh from cache when
        // the affected library matches ours.
        .onReceive(NotificationCenter.default.publisher(for: .liteLibraryDidChange)) { note in
            guard isLocalLibrary,
                  let changedID = note.userInfo?["libraryID"] as? String,
                  changedID == library.id else { return }
            loadLiteBooks()
        }
        .onChange(of: vm.searchText) { _, _ in
            if isLocalLibrary {
                // Local search is just an in-memory filter against the
                // cache — no network, no debounce needed (typing into a
                // few-hundred-book list is instant). We still cancel any
                // pending remote-search task so a stale remote response
                // can't clobber the local filter result.
                searchTask?.cancel()
                loadLiteBooks()
                return
            }
            guard !appState.isOffline else { return }
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await vm.search(client: appState.makeClient(serverURL: library.serverURL), libraryId: library.id)
            }
        }
        .onChange(of: vm.sortOption) { _, _ in
            if isLocalLibrary {
                loadLiteBooks()
                return
            }
            guard !appState.isOffline else { return }
            Task { await vm.search(client: appState.makeClient(serverURL: library.serverURL), libraryId: library.id) }
        }
        .onChange(of: vm.selectedMediaType) { _, _ in
            if isLocalLibrary {
                loadLiteBooks()
                return
            }
            guard !appState.isOffline else { return }
            Task { await vm.search(client: appState.makeClient(serverURL: library.serverURL), libraryId: library.id) }
        }
        .sheet(isPresented: $showAdd) {
            AddEditBookSheet(library: library) { _ in
                Task { await vm.load(client: appState.makeClient(serverURL: library.serverURL), libraryId: library.id) }
            }
        }
        .sheet(isPresented: $showLiteManualAdd) {
            if let account = appState.accounts.first(where: { $0.url == library.serverURL && $0.kind == .local }) {
                LiteManualAddSheet(library: library, serverAccountID: account.id) {
                    // Re-read from SwiftData so the just-added book lands
                    // in the grid without a full sync round-trip.
                    let cache = BookCache(modelContainer: modelContext.container)
                    let cached = cache.books(for: library)
                    vm.books = cached
                    vm.total = cached.count
                }
            }
        }
        .navigationDestination(item: $selectedBook) { book in
            RedesignedBookDetailView(library: library, book: book)
        }
        .alert("Error", isPresented: Binding(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") { vm.error = nil }
        } message: { Text(vm.error ?? "") }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Back to library list — sits where the mockup's `.eyebrow`
            // does. We surface a tap target on the eyebrow itself rather
            // than a separate chevron so the chrome stays light.
            VStack(alignment: .leading, spacing: 8) {
                Button(action: { onBack?() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                        Text(library.name)
                            .font(Theme.Fonts.ui(12, weight: .medium))
                            .tracking(1.0)
                            .textCase(.uppercase)
                    }
                    .foregroundStyle(Theme.Colors.appText3)
                }
                Text(countTitle)
                    .font(Theme.Fonts.pageTitle)
                    .foregroundStyle(Theme.Colors.appText)
            }
            Spacer()

            offlineToggle
                .padding(.bottom, 4)

            sortMenu
                .padding(.bottom, 4)

            Button(action: { isLocalLibrary ? (showLiteManualAdd = true) : (showAdd = true) }) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
            }
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var countTitle: String {
        // Prefer the live `total` from the active query; fall back to the
        // library-level book count while the first page is in flight.
        let count = vm.total > 0 ? vm.total : (library.bookCount ?? vm.books.count)
        if count == 0 { return "No books" }
        return "\(count.formatted()) book\(count == 1 ? "" : "s")"
    }

    /// Spotify-style download banner. Visible only while the offline sync
    /// is paginating; shows a progress bar + the running count so the
    /// user knows why the list is shorter than the library total. We re-
    /// read SwiftData on every progress tick so the "downloaded so far"
    /// number tracks reality, not just the api page count.
    @ViewBuilder
    private var syncBanner: some View {
        if let syncProgress {
            let downloaded = vm.books.count
            let total = library.bookCount ?? max(downloaded, 0)
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath.icloud")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                VStack(alignment: .leading, spacing: 6) {
                    Text(syncBannerTitle(downloaded: downloaded, total: total))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Colors.appText)
                    ProgressView(value: max(0, min(1, syncProgress)))
                        .tint(Theme.Colors.accent)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.Colors.accentSoft.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Theme.Colors.accent.opacity(0.35), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
        }
    }

    private func syncBannerTitle(downloaded: Int, total: Int) -> String {
        let phase = syncPhaseLabel ?? "Downloading library"
        if phase == "Downloading books", total > 0 {
            return "\(phase) — \(downloaded.formatted()) of \(total.formatted())"
        }
        return "\(phase)…"
    }

    @ViewBuilder
    private var offlineToggle: some View {
        let state = offlineStore.bookCacheStates[library.clientKey]
        Button {
            guard !isLocalLibrary else { return }
            let enabled = offlineStore.isEnabled(for: library.clientKey)
            let container = modelContext.container
            offlineStore.setEnabled(!enabled, for: library.clientKey, modelContainer: container)
            if !enabled,
               let account = appState.accounts.first(where: { $0.url == library.serverURL }) {
                // Just turned on — kick a sync immediately so the user
                // sees progress instead of an empty cached state.
                let accountID = account.id
                let accessToken = account.accessToken
                let client = appState.makeClient(serverURL: library.serverURL)
                Task {
                    await offlineStore.syncBooks(
                        for: library,
                        client: client,
                        serverAccountID: accountID,
                        accessToken: accessToken,
                        modelContainer: container
                    )
                }
            }
        } label: {
            Image(systemName: offlineIconName(state: state))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isKeptOffline ? Theme.Colors.accent : Theme.Colors.appText3)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.08), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
        }
        // Lite libraries are inherently offline — the user can't toggle
        // them off, but we keep the icon visible so the indicator state
        // stays consistent across remote + local libraries.
        .disabled(isLocalLibrary)
        .opacity(isLocalLibrary ? 0.7 : 1.0)
    }

    private func offlineIconName(state: BookCacheState?) -> String {
        if isLocalLibrary { return "iphone.gen3" }
        switch state {
        case .syncing:
            return "arrow.triangle.2.circlepath.icloud"
        case .cached:
            return "checkmark.icloud.fill"
        case .notCached, nil:
            return isKeptOffline ? "icloud.and.arrow.down" : "icloud"
        }
    }

    @ViewBuilder
    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $vm.sortOption) {
                ForEach(BookSortOption.allCases) { opt in
                    Text(opt.label).tag(opt)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Colors.appText2)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.Colors.appLine, lineWidth: 0.5))
        }
    }

    // MARK: - Toolbar (search pill)

    @ViewBuilder
    private var toolbarRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText3)
                TextField("Search titles, authors, ISBN…", text: $vm.searchText)
                    .font(Theme.Fonts.ui(14, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText)
                    .tint(Theme.Colors.accent)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !vm.searchText.isEmpty {
                    Button(action: { vm.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Colors.appText3)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.Colors.appLine, lineWidth: 0.5))
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    // MARK: - Filter chips
    //
    // Mockup-faithful chips. Status filters (Reading / Read / Unread) need
    // a server-side `read_status` filter on `/libraries/{id}/books?q=` that
    // doesn't exist yet — they're rendered disabled until that ships. The
    // media-type chips reuse the metadata the VM already fetches.

    @ViewBuilder
    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", active: vm.selectedMediaType == nil) {
                    vm.selectedMediaType = nil
                }
                ForEach(vm.availableMediaTypes, id: \.id) { type in
                    chip(type.displayName, active: vm.selectedMediaType?.id == type.id) {
                        vm.selectedMediaType = (vm.selectedMediaType?.id == type.id) ? nil : type
                    }
                }
            }
            .padding(.horizontal, 18)
        }
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private func chip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Theme.Fonts.ui(13, weight: .medium))
                .foregroundStyle(active ? Theme.Colors.accentStrong : Theme.Colors.appText2)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(active ? Theme.Colors.accentSoft : Color.white.opacity(0.06))
                )
                .overlay(
                    Capsule().stroke(active ? Color.clear : Theme.Colors.appLine, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grid

    private var columns: [GridItem] {
        // `.top` alignment so all covers in a row start at the same Y
        // even when neighbour tiles have a longer (2-line) title pushing
        // their meta block taller. Default `.center` made covers drift
        // down on tiles with shorter titles.
        [GridItem(.flexible(), spacing: 12, alignment: .top),
         GridItem(.flexible(), spacing: 12, alignment: .top),
         GridItem(.flexible(), spacing: 12, alignment: .top)]
    }

    @ViewBuilder
    private var grid: some View {
        if vm.isLoading && vm.books.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 240)
                .tint(Theme.Colors.appText2)
        } else if vm.books.isEmpty {
            emptyState
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(vm.books, id: \.id) { book in
                    Button { selectedBook = book } label: {
                        BookTile(book: book, library: library)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if book.id == vm.books.last?.id, vm.hasMore, !vm.isLoadingMore {
                            Task { await vm.loadMore(client: appState.makeClient(serverURL: library.serverURL), libraryId: library.id) }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)

            if vm.isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .tint(Theme.Colors.appText2)
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
                .font(Theme.Fonts.rowMeta)
                .foregroundStyle(Theme.Colors.appText3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(.horizontal, 18)
    }

    /// When the offline sync is running we don't want the empty state to
    /// read like the library is broken — it just hasn't finished
    /// downloading. Swap copy + icon while syncing so the user pairs the
    /// banner above with the matching empty body.
    private var emptyStateIcon: String {
        if isSyncing { return "arrow.triangle.2.circlepath.icloud" }
        return "books.vertical"
    }

    private var emptyStateTitle: String {
        if isSyncing { return (syncPhaseLabel ?? "Downloading your library") + "…" }
        return vm.hasActiveFilters ? "No matches" : "No books yet"
    }

    private var emptyStateMessage: String {
        if isSyncing { return "Books will appear as they sync." }
        if vm.hasActiveFilters { return "Try a different search or filter." }
        return isLocalLibrary
            ? "Use the scan button to add books to your library."
            : "Add your first book to get started."
    }

    // MARK: - Load + sync helpers

    /// Lite-mode read path. Reads everything for the library out of
    /// SwiftData, then filters in memory by the current search text +
    /// media-type chip. Plenty fast for any Lite library size — typical
    /// local catalogs are a few hundred books at most.
    ///
    /// Title and author are case-insensitive substring matches. ISBN
    /// search is intentionally skipped here: it would require reading
    /// EditionCache for every book on every keystroke and the on-device
    /// scan flow is the more natural way to find a book by ISBN.
    private func loadLiteBooks() {
        let cache = BookCache(modelContainer: modelContext.container)
        let cached = cache.books(for: library)
        let q = vm.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let mediaTypeName = vm.selectedMediaType?.displayName.lowercased()

        let filtered = cached.filter { book in
            if let mediaTypeName, !mediaTypeName.isEmpty {
                if book.mediaType.lowercased() != mediaTypeName { return false }
            }
            if q.isEmpty { return true }
            if book.title.lowercased().contains(q) { return true }
            for c in book.contributors where c.name.lowercased().contains(q) {
                return true
            }
            return false
        }
        vm.books = sortLite(filtered, by: vm.sortOption)
        vm.total = vm.books.count
    }

    /// Apply the active `BookSortOption` to the Lite result set. Mirrors
    /// the api's sort keys: title / author / created_at / publish_date,
    /// each with an asc/desc dir. `BookCache.books(for:)` already returns
    /// rows ordered by `sortTitle`, so the title cases are essentially
    /// passthroughs — included for clarity.
    private func sortLite(_ books: [Book], by option: BookSortOption) -> [Book] {
        switch option {
        case .titleAsc:
            return books.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .titleDesc:
            return books.sorted { $0.title.localizedStandardCompare($1.title) == .orderedDescending }
        case .authorAsc, .authorDesc:
            let primary: (Book) -> String = { $0.contributors.first?.name ?? "" }
            return books.sorted {
                let cmp = primary($0).localizedStandardCompare(primary($1))
                return option == .authorAsc ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        case .recentlyAdded:
            return books.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
        case .oldestFirst:
            return books.sorted { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
        case .newestRelease, .oldestRelease:
            // BookCache doesn't surface publishDate (lives on edition).
            // Fall back to title order rather than nothing.
            return books.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    /// Single entry point for the BooksView load path. Strategy:
    ///
    /// - Kept-offline (and Lite) libraries are SwiftData-primary: render
    ///   from the cache immediately so opening the view is instant, then
    ///   kick a background sync to refresh from the server when online.
    /// - Non-cached remote libraries hit the api directly. On failure the
    ///   user gets the standard error alert — there's nothing on-device
    ///   to show them.
    ///
    /// In both paths a successful api response writes through to
    /// SwiftData so a future offline visit picks up the same view.
    private func loadBooks() async {
        let client = appState.makeClient(serverURL: library.serverURL)
        let container = modelContext.container
        let accountID = appState.accounts
            .first(where: { $0.url == library.serverURL })?.id

        if isKeptOffline, !isLocalLibrary {
            // Render from SwiftData first so the user sees their library
            // even before the network round-trips. The full sync below
            // backfills any missing pages and updates rating/status etc.
            let cache = BookCache(modelContainer: container)
            let cached = cache.books(for: library)
            if !cached.isEmpty {
                vm.books = cached
                vm.total = cached.count
                vm.error = nil
            }

            // Online refresh. When the server is reachable, syncBooks
            // pulls every page and write-throughs to SwiftData. When
            // it fails (truly offline) we keep the cached view we just
            // painted — no error alert needed. Skip the round-trip
            // entirely when NetworkMonitor knows we're offline.
            guard !appState.isOffline else { return }
            if let accountID, let accessToken = appState.accounts.first(where: { $0.id == accountID })?.accessToken {
                await LibraryOfflineStore.shared.syncBooks(
                    for: library,
                    client: client,
                    serverAccountID: accountID,
                    accessToken: accessToken,
                    modelContainer: container
                )
                let refreshed = cache.books(for: library)
                if !refreshed.isEmpty {
                    vm.books = refreshed
                    vm.total = refreshed.count
                    vm.error = nil
                }
            }
            return
        }

        // Not kept offline — straight api fetch. On success, still write
        // through to SwiftData so toggling "Keep offline" later finds
        // some data already there.
        await vm.load(client: client, libraryId: library.id)
        if vm.error == nil, let accountID {
            let books = vm.books
            Task.detached(priority: .background) {
                BookCache(modelContainer: container).upsert(books, for: library, serverAccountID: accountID)
            }
        }
    }
}

// MARK: - Book tile

private struct BookTile: View {
    let book: Book
    let library: Library

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            cover
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(Theme.Fonts.ui(12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText)
                    // Reserve 2 lines so single-line titles still take
                    // the same vertical space as 2-line ones — keeps
                    // author rows aligned across columns.
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                if let author = primaryAuthor, !author.isEmpty {
                    Text(author)
                        .font(Theme.Fonts.ui(11, weight: .medium))
                        .foregroundStyle(Theme.Colors.appText3)
                        .lineLimit(1)
                }
                if let pct = activeProgress {
                    progressBar(pct: pct)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private var cover: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = w * 1.5
            ZStack(alignment: .topLeading) {
                BookCoverImage(
                    url: coverURL,
                    width: w,
                    height: h,
                    title: book.title,
                    author: primaryAuthor,
                    readStatus: book.userReadStatus
                )

                if let count = book.activeLoanCount, count > 0 {
                    lentChip
                        .padding(8)
                        .frame(maxHeight: .infinity, alignment: .bottomLeading)
                }

                if let rating = book.userRating, rating > 0 {
                    starsChip(rating: rating)
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .frame(width: w, height: h)
        }
        .aspectRatio(2.0/3.0, contentMode: .fit)
    }

    /// Fanned cover URL — match against the library's server prefix so the
    /// authenticated cover endpoint is hit with the right Bearer token.
    private var coverURL: URL? {
        library.coverURL(for: book.coverUrl)
    }

    private var primaryAuthor: String? {
        book.contributors
            .first(where: { $0.role.caseInsensitiveCompare("author") == .orderedSame })?.name
            ?? book.contributors.first?.name
    }

    /// 0-100, only if the user has any progress on this book.
    private var activeProgress: Double? {
        guard let pct = book.userProgressPct, pct > 0 else { return nil }
        return pct
    }

    @ViewBuilder
    private var lentChip: some View {
        Text("Lent")
            .font(.system(size: 9, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(Color(hex: 0x1a1306))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color(hex: 0xf59e0b, opacity: 0.92), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func starsChip(rating: Int) -> some View {
        // userRating is the 1-10 half-star integer; convert to display
        // value (5 = "★ 2.5", 10 = "★ 5.0").
        let display = Double(rating) / 2.0
        HStack(spacing: 3) {
            Text("★").font(.system(size: 9, weight: .bold))
            Text(display.formatted(.number.precision(.fractionLength(1))))
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(Theme.Colors.gold)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.55), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
    }

    @ViewBuilder
    private func progressBar(pct: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 99)
                    .fill(Color.white.opacity(0.08))
                RoundedRectangle(cornerRadius: 99)
                    .fill(LinearGradient(
                        colors: [Theme.Colors.accent, Theme.Colors.accentStrong],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: geo.size.width * CGFloat(min(max(pct, 0), 100) / 100.0))
            }
        }
        .frame(height: 3)
    }
}

