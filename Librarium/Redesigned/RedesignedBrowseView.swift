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

    @Environment(AppState.self) private var appState

    @State private var vm = BrowseViewModel()
    @State private var libraries: [String: Library] = [:]
    @State private var searchTask: Task<Void, Never>?
    @State private var showFilters = false
    @State private var showSearch = false
    @State private var selected: BookOpenRequest?
    @State private var reauthAccount: ServerAccount?

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
            .task {
                guard vm.books.isEmpty else { return }
                if let initialSelection { vm.selection = initialSelection }
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
            .navigationDestination(item: $selected) { request in
                RedesignedBookDetailView(library: request.library, book: request.book)
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

            // Authors sits here rather than in the tab bar. It is a way into
            // the same books by a different axis, and the bar already carries
            // four tabs and a scanner.
            if initialSelection == nil {
                NavigationLink { RedesignedAuthorsView() } label: {
                    Image(systemName: "person.2")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Colors.appText2)
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.06), in: Circle())
                        .overlay(Circle().stroke(Theme.Colors.appLine, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Authors")
                .padding(.bottom, 4)
                iconButton("magnifyingglass", label: "Search everything") { showSearch = true }
            }
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
        if vm.isLoading && vm.books.isEmpty { return "Loading…" }
        let count = vm.total
        if count == 0 { return "No books" }
        return "\(count.formatted()) book\(count == 1 ? "" : "s")"
    }

    @ViewBuilder
    private func iconButton(_ system: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Colors.appText2)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.06), in: Circle())
                .overlay(Circle().stroke(Theme.Colors.appLine, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .padding(.bottom, 4)
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
    private var sortMenu: some View {
        Menu {
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
