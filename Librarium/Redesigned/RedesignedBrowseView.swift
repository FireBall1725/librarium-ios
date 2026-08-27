// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// The books surface: everything the reader can see, in one grid.
///
/// The per-library grid is still where you go to work on one library, sync it
/// for offline, or add to it. This is the other half, and the half the phone did
/// not have: the whole collection, ranked together, narrowed by any of eleven
/// dimensions rather than by which library you happened to open.
///
/// Library is one of those dimensions here rather than the way in. That is the
/// same move the API made when `/libraries/{id}/books` became `/me/books`, and
/// it is what makes "what am I missing" a question the phone can ask.
struct RedesignedBrowseView: View {
    /// A filter to open on, for the surfaces that push into this one. An
    /// author's page is this grid with one contributor ticked, so it is the
    /// same view rather than a second grid with the same bugs.
    var initialSelection: BrowseSelection?
    /// What to call the scope when it did not come from the library facet.
    var initialTitle: String?
    /// Set by the shell when the scanner finds a book already on a shelf and
    /// the reader asks to open it. Cleared once pushed, so backing out of the
    /// detail does not immediately push it again.
    var openBookID: Binding<String?> = .constant(nil)
    /// Whether this tab is the one on screen.
    ///
    /// The shell keeps every tab alive behind an opacity, so a plain `.task`
    /// fires for all four at launch: four screens' worth of requests for the
    /// one the reader is looking at, and any of them can be cancelled by the
    /// next re-render with nothing to try again.
    var isActive = true

    @Environment(AppState.self) private var appState

    @State private var vm = BrowseViewModel()
    @State private var libraries: [String: Library] = [:]
    @State private var searchTask: Task<Void, Never>?
    @State private var showFilters = false
    @State private var showSearch = false
    @State private var selected: BookOpenRequest?
    @State private var selectedGroup: AuthorSelection?
    @State private var reauthAccount: ServerAccount?
    @State private var views: [SavedList] = []
    @State private var showSaveView = false
    @State private var newViewName = ""

    /// The tab root owns a navigation stack; a pushed copy must not. Two nested
    /// stacks look like one until something is pushed onto the inner one, and
    /// then the back button goes to the wrong place.
    private var isRoot: Bool { initialSelection == nil }

    var body: some View {
        if isRoot {
            NavigationStack { content }
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            ZStack {
                Theme.Colors.appBackground.ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        header
                        ReauthBannerStack(
                            accounts: appState.accounts.filter { $0.needsReauth },
                            onTap: { reauthAccount = $0 }
                        )
                        searchPill
                        if isRoot {
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
                        }
                        ActiveFilterPills(
                            selection: $vm.selection, facets: vm.facets,
                            onChange: { reload() }
                        )
                        .padding(.bottom, 12)
                        grid
                    }
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(isRoot ? .hidden : .visible, for: .navigationBar)
            // Keyed on being on screen, so the first visit loads and a visit
            // after a cancelled attempt tries again instead of leaving an empty
            // shelf up for the rest of the session.
            .task(id: isActive) {
                guard isActive, !vm.hasLoaded else { return }
                if let initialSelection {
                    vm.selection = initialSelection
                } else {
                    // Returned rather than read back off `@State`: a write and
                    // a read in the same closure sees the old value, so the
                    // default view was never being applied.
                    let loaded = await loadViews()
                    if let fallback = loaded.first(where: { $0.isDefault }) {
                        vm.selection = BrowseSelection(query: fallback.filterQuery)
                    }
                }
                await loadLibraries()
                await vm.load(appState: appState)
            }
            .refreshable {
                await loadLibraries()
                await vm.load(appState: appState)
            }
            .onChange(of: vm.selection.query) { _, _ in
                searchTask?.cancel()
                searchTask = Task {
                    // Long enough that typing a title is one request rather
                    // than one per keystroke, short enough that it still feels
                    // like the list is following along.
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    await vm.load(appState: appState)
                }
            }
            .onChange(of: vm.sort) { _, _ in reload() }
            .onChange(of: openBookID.wrappedValue) { _, _ in pushScannedBook() }
            .sheet(isPresented: $showFilters) {
                BrowseFilterSheet(
                    selection: $vm.selection, facets: vm.facets,
                    onChange: { reload() }
                )
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showSearch) {
                RedesignedSearchView()
            }
            .sheet(item: $reauthAccount) { account in
                ReauthSheet(account: account)
            }
            .sheet(isPresented: $showSaveView) {
                SaveViewSheet(name: $newViewName) { saveView() }
            }
            .navigationDestination(item: $selected) { request in
                RedesignedBookDetailView(library: request.library, book: request.book)
            }
            .navigationDestination(item: $selectedGroup) { pick in
                RedesignedBrowseView(
                    initialSelection: pick.selection,
                    initialTitle: pick.name
                )
            }
            .alert("Error", isPresented: Binding(
                get: { vm.error != nil }, set: { if !$0 { vm.error = nil } }
            )) {
                Button("OK") { vm.error = nil }
            } message: { Text(vm.error ?? "") }
        }
        .navigationTitle(isRoot ? "" : (initialTitle ?? "Books"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Text(scopeLabel)
                    .font(Theme.Fonts.ui(12, weight: .medium))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.appText3)
                Text(countTitle)
                    .font(Theme.Fonts.pageTitle)
                    .foregroundStyle(Theme.Colors.appText)
            }
            Spacer()

            // Five buttons across the top of a phone is a toolbar nobody can
            // aim at. Sort and filter stay out because they are used on almost
            // every visit; the surfaces you cross to occasionally go behind
            // the overflow, which is where the web page puts them too.
            if isRoot { moreMenu }
            sortMenu
            filterButton
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    /// What the grid is currently showing, said in the eyebrow rather than
    /// hidden in the filter sheet. One library selected names it; several name
    /// how many; none names the whole collection.
    private var scopeLabel: String {
        if let initialTitle { return initialTitle }
        let picked = vm.selection[.library]
        if picked.isEmpty { return "All libraries" }
        if picked.count == 1, let id = picked.first {
            if let name = libraries[id]?.name { return name }
            if let match = vm.facets.library.first(where: { $0.value == id }) { return match.label }
        }
        return "\(picked.count) libraries"
    }

    private var countTitle: String {
        if vm.isLoading && !vm.hasLoaded { return "Loading…" }
        // Rows when grouped, books when not. Sixty volumes of one run are
        // sixty books and one row, and the header says books.
        let count = vm.selection.grouped ? vm.bookTotal : vm.total
        if count == 0 { return "No books" }
        return "\(count.formatted()) book\(count == 1 ? "" : "s")"
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
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var moreMenu: some View {
        Menu {
            NavigationLink { RedesignedAuthorsView() } label: {
                Label("Authors", systemImage: "person.2")
            }
            NavigationLink { RedesignedLoansView() } label: {
                Label("Loans", systemImage: "arrow.left.arrow.right")
            }
            NavigationLink { RedesignedSuggestionsView() } label: {
                Label("Suggestions", systemImage: "sparkles")
            }
            Divider()
            // One level down rather than a tab of its own. Syncing a library
            // offline and adding to it are things you do to a library, which is
            // rarer than asking a question about the whole collection.
            NavigationLink { LibrariesBrowser() } label: {
                Label("Libraries", systemImage: "building.columns")
            }
            Button { showSearch = true } label: {
                Label("Search everything", systemImage: "magnifyingglass")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Colors.appText2)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.06), in: Circle())
                .overlay(Circle().stroke(Theme.Colors.appLine, lineWidth: 0.5))
        }
        .accessibilityLabel("More")
        .padding(.bottom, 4)
    }

    /// Any server will do for a group's cover: the URL the API builds is
    /// absolute from the host's root and a run belongs to one instance.
    private var primaryServerURL: String {
        libraries.values.first?.serverURL ?? ""
    }

    /// Opening a run shows its volumes, with the grouping off so it does not
    /// collapse straight back into the row that was just tapped.
    private func openGroup(_ group: SeriesGroup) {
        var narrowed = vm.selection
        narrowed.series = [group.seriesId]
        narrowed.grouped = false
        selectedGroup = AuthorSelection(
            id: group.seriesId, name: group.seriesName, selection: narrowed)
    }

    @ViewBuilder
    private var sortMenu: some View {
        Menu {
            Button {
                vm.selection.grouped.toggle()
                reload()
            } label: {
                if vm.selection.grouped {
                    Label("Group by series", systemImage: "checkmark")
                } else {
                    Text("Group by series")
                }
            }
            Divider()
            ForEach(BookSortOption.allCases) { option in
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
        .padding(.bottom, 4)
    }

    // MARK: - Search

    @ViewBuilder
    private var searchPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Colors.appText3)
            TextField("Search titles, authors, ISBN…", text: $vm.selection.query)
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
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.Colors.appLine, lineWidth: 0.5))
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    // MARK: - Grid

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 12, alignment: .top),
         GridItem(.flexible(), spacing: 12, alignment: .top),
         GridItem(.flexible(), spacing: 12, alignment: .top)]
    }

    @ViewBuilder
    private var grid: some View {
        if vm.selection.grouped {
            groupedGrid
        } else {
            flatGrid
        }
    }

    /// Runs collapsed into one tile each, standalone books beside them.
    ///
    /// The reason this is the default view on the web: a shelf of 1,425 books
    /// where 740 of them are volumes of forty manga runs reads as forty runs
    /// and a few hundred books, not as an alphabet of near-identical spines.
    @ViewBuilder
    private var groupedGrid: some View {
        if vm.isLoading && vm.groups.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 240)
                .tint(Theme.Colors.appText2)
        } else if vm.groups.isEmpty {
            emptyState
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(vm.groups) { row in
                    switch row {
                    case .book(let book):
                        Button { open(book) } label: {
                            BookTile(book: book, serverURL: vm.serverURL[book.id] ?? "")
                        }
                        .buttonStyle(.plain)
                    case .series(let group):
                        Button { openGroup(group) } label: {
                            SeriesGroupTile(group: group, serverURL: primaryServerURL)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 18)
            .onAppear {
                if vm.hasMore, !vm.isLoadingMore {
                    Task { await vm.loadMore(appState: appState) }
                }
            }

            if vm.isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .tint(Theme.Colors.appText2)
            }
        }
    }

    @ViewBuilder
    private var flatGrid: some View {
        if vm.isLoading && vm.books.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 240)
                .tint(Theme.Colors.appText2)
        } else if vm.books.isEmpty {
            emptyState
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(vm.books, id: \.id) { book in
                    Button { open(book) } label: {
                        BookTile(book: book, serverURL: vm.serverURL[book.id] ?? "")
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if book.id == vm.books.last?.id, vm.hasMore, !vm.isLoadingMore {
                            Task { await vm.loadMore(appState: appState) }
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
        // Two different nothings. An empty shelf needs a book added; a filter
        // that matches nothing needs the filter cleared, and telling someone to
        // add a book they already own is the wrong instruction.
        if vm.selection.activeCount > 0 || !vm.selection.query.isEmpty {
            EmptyState(
                icon: "line.3.horizontal.decrease",
                title: "Nothing matches",
                subtitle: "No books match the filters you have on.",
                action: {
                    vm.selection.clear()
                    vm.selection.query = ""
                    reload()
                },
                actionLabel: "Clear filters"
            )
            .padding(.top, 40)
        } else {
            EmptyState(
                icon: "books.vertical",
                title: "No books yet",
                subtitle: "Books you add to any library show up here."
            )
            .padding(.top, 40)
        }
    }

    // MARK: - Actions

    private func reload() {
        searchTask?.cancel()
        Task { await vm.load(appState: appState) }
    }

    /// Opens the book the scanner just found.
    ///
    /// Fetched by work rather than looked up in the grid: the scanner answers
    /// with a book, and waiting for that book to turn up on whatever page of
    /// whatever filter is currently applied would mean it usually never does.
    private func pushScannedBook() {
        guard let bookID = openBookID.wrappedValue else { return }
        openBookID.wrappedValue = nil
        Task {
            await loadLibraries()
            for library in libraries.values {
                let client = appState.makeClient(serverURL: library.serverURL)
                if let book = try? await BookService(client: client).get(bookId: bookID) {
                    selected = BookOpenRequest(book: book, library: library)
                    return
                }
            }
        }
    }

    /// The saved view matching what is on screen, if one does. Compared on the
    /// query string rather than by remembering which chip was tapped, so
    /// changing one filter after opening a view unticks it honestly.
    private var activeViewID: String? {
        let current = vm.selection.queryString()
        return views.first(where: { $0.filterQuery == current })?.id
    }

    private func open(_ view: SavedList) {
        vm.selection = BrowseSelection(query: view.filterQuery)
        reload()
    }

    /// Views live on one server. With several accounts the primary one is
    /// where a new view goes, matching every other global preference in the
    /// app rather than inventing a picker for it.
    @discardableResult
    private func loadViews() async -> [SavedList] {
        let client = appState.makePrimaryClient()
        let loaded = (try? await ListService(client: client).savedViews(surface: "books")) ?? []
        views = loaded
        return loaded
    }

    private func saveView() {
        let name = newViewName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let query = vm.selection.queryString()
        Task {
            let client = appState.makePrimaryClient()
            try? await ListService(client: client)
                .saveView(name: name, surface: "books", query: query)
            await loadViews()
        }
    }

    /// Every library on every account, so a book can be opened without another
    /// round trip and the library facet can be named before its counts arrive.
    private func loadLibraries() async {
        var found: [String: Library] = [:]
        for account in appState.accounts where account.kind != .local {
            let client = appState.makeClient(serverURL: account.url)
            guard let list = try? await LibraryService(client: client).list() else { continue }
            for var library in list {
                library.serverURL = account.url
                library.serverName = account.name
                found[library.id] = library
            }
        }
        if !found.isEmpty { libraries = found }
    }

    /// The detail view is built around a library, so opening from a grid that
    /// has none has to pick one. The book's own `library_id` is the server's
    /// answer to the same question, and falling back to any library on the
    /// right server keeps a book that sits in several from being unopenable.
    private func open(_ book: Book) {
        let server = vm.serverURL[book.id] ?? ""
        let library = libraries[book.libraryId]
            ?? libraries.values.first(where: { $0.serverURL == server })
        guard let library else { return }
        selected = BookOpenRequest(book: book, library: library)
    }
}

/// A book and the library to open it in.
struct BookOpenRequest: Identifiable, Hashable {
    let book: Book
    let library: Library
    var id: String { library.clientKey + "/" + book.id }
}
