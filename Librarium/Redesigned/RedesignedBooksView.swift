// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

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

    @State private var vm = BooksViewModel()
    @State private var searchTask: Task<Void, Never>?
    @State private var showAdd = false
    @State private var selectedBook: Book?

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    header
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
            guard vm.books.isEmpty else { return }
            if appState.isOffline {
                vm.loadFromCache(offlineKey: library.clientKey)
            } else {
                await vm.load(client: appState.makeClient(serverURL: library.serverURL), libraryId: library.id)
            }
        }
        .refreshable {
            if !appState.isOffline {
                await vm.load(client: appState.makeClient(serverURL: library.serverURL), libraryId: library.id)
            }
        }
        .onChange(of: vm.searchText) { _, _ in
            guard !appState.isOffline else { return }
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await vm.search(client: appState.makeClient(serverURL: library.serverURL), libraryId: library.id)
            }
        }
        .onChange(of: vm.sortOption) { _, _ in
            guard !appState.isOffline else { return }
            Task { await vm.search(client: appState.makeClient(serverURL: library.serverURL), libraryId: library.id) }
        }
        .onChange(of: vm.selectedMediaType) { _, _ in
            guard !appState.isOffline else { return }
            Task { await vm.search(client: appState.makeClient(serverURL: library.serverURL), libraryId: library.id) }
        }
        .sheet(isPresented: $showAdd) {
            AddEditBookSheet(library: library) { _ in
                Task { await vm.load(client: appState.makeClient(serverURL: library.serverURL), libraryId: library.id) }
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

            sortMenu
                .padding(.bottom, 4)

            Button(action: { showAdd = true }) {
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
            Image(systemName: "books.vertical")
                .font(.system(size: 32))
                .foregroundStyle(Theme.Colors.appText3)
            Text(vm.hasActiveFilters ? "No matches" : "No books yet")
                .font(Theme.Fonts.cardTitle)
                .foregroundStyle(Theme.Colors.appText)
            Text(vm.hasActiveFilters
                 ? "Try a different search or filter."
                 : "Add your first book to get started.")
                .font(Theme.Fonts.rowMeta)
                .foregroundStyle(Theme.Colors.appText3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(.horizontal, 18)
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
        guard let path = book.coverUrl, !path.isEmpty else { return nil }
        return URL(string: library.serverURL + path)
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

