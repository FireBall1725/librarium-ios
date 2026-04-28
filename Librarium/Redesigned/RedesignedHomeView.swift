// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// Redesigned Home — mockup card #7.
///
/// Sections (top to bottom):
/// - Greeting header (date eyebrow + "Good evening, Adaléa")
/// - Now-reading hero card (cover + title + author + progress bar)
/// - Stats card (12-month read total + sparkline)
/// - "Pick up where you left off" horizontal strip (other in-progress
///   books, or recently-finished as a fallback)
///
/// Driven by the primary account's `/api/v1/dashboard/*` endpoints. In a
/// multi-server world we surface only the primary today; the redesigned
/// profile (mockup card 8) will own switching active server, at which
/// point Home aggregates from whatever is active.
/// VM for `RedesignedHomeView`. Owns dashboard data + the load logic;
/// held in `@State` on the view so the reference is stable across body
/// recomputes. Same motivation as `RedesignedLibrariesViewModel` —
/// inline `@State` + inline `func load()` ate URL requests on
/// pull-to-refresh.
@Observable
final class RedesignedHomeViewModel {
    var currentlyReading: [DashboardBook] = []
    var recentlyFinished: [DashboardBook] = []
    var stats: DashboardStats?
    var isLoading = true
    var error: String?

    func load(appState: AppState) async {
        isLoading = true
        defer { isLoading = false }
        guard let client = Self.primaryClient(appState: appState) else {
            error = "No primary server selected."
            return
        }
        let svc = DashboardService(client: client)
        async let cr = svc.currentlyReading()
        async let rf = svc.recentlyFinished()
        async let st = svc.stats()

        // Only replace on real success — coercing CancellationError into
        // nil/[] would blank the page on every refresh-task supersession.
        if let value = try? await cr { currentlyReading = value }
        if let value = try? await rf { recentlyFinished = value }
        if let value = try? await st { stats = value }
    }

    static func primaryAccount(appState: AppState) -> ServerAccount? {
        if let id = appState.primaryAccountID,
           let primary = appState.accounts.first(where: { $0.id == id }) {
            return primary
        }
        return appState.accounts.first
    }

    static func primaryClient(appState: AppState) -> APIClient? {
        guard let account = primaryAccount(appState: appState) else { return nil }
        return appState.makeClient(serverURL: account.url)
    }
}

struct RedesignedHomeView: View {
    @Environment(AppState.self) private var appState

    @State private var vm = RedesignedHomeViewModel()
    @State private var pendingDetail: BookDetailRequest?
    @State private var loadedDetail: BookDetailLoaded?
    @State private var showProfile = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        if let book = vm.currentlyReading.first {
                            nowReadingHero(book: book)
                        } else if !vm.isLoading {
                            nowReadingEmpty
                        }
                        if let s = vm.stats {
                            statsCard(stats: s)
                        }
                        jumpBackInSection
                    }
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await vm.load(appState: appState) }
            .refreshable { await vm.load(appState: appState) }
            .navigationDestination(item: $loadedDetail) { detail in
                RedesignedBookDetailView(library: detail.library, book: detail.book)
            }
            .sheet(isPresented: $showProfile) {
                RedesignedProfileView()
                    .presentationDragIndicator(.visible)
            }
            .alert("Error", isPresented: Binding(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
                Button("OK") { vm.error = nil }
            } message: { Text(vm.error ?? "") }
        }
        .onChange(of: pendingDetail) { _, request in
            guard let request else { return }
            Task { await loadDetail(request: request) }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(dateEyebrow)
                    .font(Theme.Fonts.ui(12, weight: .medium))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.appText3)
                Text(greeting)
                    .font(Theme.Fonts.pageTitle)
                    .foregroundStyle(Theme.Colors.appText)
            }
            Spacer()
            // Profile avatar — tap to open the redesigned profile sheet.
            // We don't store user avatar images yet, so the circle is an
            // accent-gradient with the first initial of the primary
            // user's display name. When avatar uploads land, this is the
            // single place to swap to a real image.
            Button { showProfile = true } label: {
                profileAvatar
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var profileAvatar: some View {
        let primary = RedesignedHomeViewModel.primaryAccount(appState: appState)
        let display = primary?.user.displayName.isEmpty == false
            ? primary!.user.displayName
            : (primary?.user.username ?? "")
        let initial = String(display.prefix(1)).uppercased()
        ZStack {
            LinearGradient(
                colors: [Theme.Colors.accent, Color(hex: 0x5a64e8)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Text(initial.isEmpty ? "?" : initial)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: Theme.Colors.accent.opacity(0.4), radius: 6, y: 2)
    }

    private var dateEyebrow: String {
        let df = DateFormatter()
        df.dateFormat = "EEEE · MMMM d"
        return df.string(from: Date())
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay: String
        switch hour {
        case 5..<12:  timeOfDay = "morning"
        case 12..<17: timeOfDay = "afternoon"
        case 17..<22: timeOfDay = "evening"
        default:      timeOfDay = "night"
        }
        let name = appState.currentUser?.displayName.split(separator: " ").first.map(String.init)
            ?? appState.currentUser?.username
            ?? ""
        return name.isEmpty ? "Good \(timeOfDay)" : "Good \(timeOfDay), \(name)"
    }

    // MARK: - Now reading

    @ViewBuilder
    private func nowReadingHero(book: DashboardBook) -> some View {
        Button { openDetail(for: book) } label: {
            HStack(alignment: .top, spacing: 14) {
                BookCoverImage(
                    url: coverURL(for: book),
                    width: 80,
                    height: 120,
                    title: book.title,
                    author: book.authors,
                    readStatus: book.readStatus
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 0) {
                    Text("CURRENTLY READING")
                        .font(Theme.Fonts.label(10))
                        .tracking(1.4)
                        .foregroundStyle(Theme.Colors.appText3)
                    Text(book.title)
                        .font(Theme.Fonts.cardTitle)
                        .foregroundStyle(Theme.Colors.appText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 6)
                    if !book.authors.isEmpty {
                        Text(book.authors)
                            .font(Theme.Fonts.ui(13, weight: .medium))
                            .foregroundStyle(Theme.Colors.appText2)
                            .lineLimit(1)
                            .padding(.top, 2)
                    }
                    Spacer(minLength: 8)
                    // Progress bar — `user_progress_pct` isn't on the
                    // dashboard payload yet, so we render an indeterminate
                    // bar (40% accent strip) for now. When the api exposes
                    // it on currently-reading, swap for the real value.
                    progressBar(pct: 40)
                    Text("In progress")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Colors.appText3)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Theme.Colors.appCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Theme.Colors.appLine, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var nowReadingEmpty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CURRENTLY READING")
                .font(Theme.Fonts.label(10))
                .tracking(1.4)
                .foregroundStyle(Theme.Colors.appText3)
            Text("Nothing in progress")
                .font(Theme.Fonts.cardTitle)
                .foregroundStyle(Theme.Colors.appText)
            Text("Start a book to see it here.")
                .font(Theme.Fonts.ui(13, weight: .medium))
                .foregroundStyle(Theme.Colors.appText3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Theme.Colors.appCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Theme.Colors.appLine, lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
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
        .frame(height: 4)
    }

    // MARK: - Stats card

    @ViewBuilder
    private func statsCard(stats: DashboardStats) -> some View {
        // Match the web Dashboard's framing: hero number is "books read in
        // the current calendar year" (`books_read_this_year`), sparkline
        // is the api's `monthly_reads` series rendered as-is. The
        // mockup's "last 12 months" label was wrong — we use the same
        // numbers as the web so the two clients agree.
        let year = Calendar.current.component(.year, from: Date())
        let counts = stats.monthlyReads.map(\.count)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("READ IN \(String(year))")
                    .font(Theme.Fonts.label(11))
                    .tracking(1.4)
                    .foregroundStyle(Theme.Colors.appText3)
                Spacer()
                if stats.booksRead > stats.booksReadThisYear {
                    Text("\(stats.booksRead.formatted()) all time")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Colors.appText3)
                }
            }

            Text(stats.booksReadThisYear.formatted())
                .font(Theme.Fonts.display(36, weight: .bold))
                .foregroundStyle(Theme.Colors.appText)

            sparkline(counts: counts)
                .frame(height: 56)

            Text("LAST 12 MONTHS")
                .font(Theme.Fonts.label(10))
                .tracking(1.2)
                .foregroundStyle(Theme.Colors.appText3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Theme.Colors.appCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Theme.Colors.appLine, lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private func sparkline(counts: [Int]) -> some View {
        let maxCount = max(counts.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(counts.enumerated()), id: \.offset) { _, count in
                let frac = Double(count) / Double(maxCount)
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(
                        colors: [Theme.Colors.accentStrong, Theme.Colors.accent],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(4, 56 * CGFloat(frac)))
            }
        }
    }

    // MARK: - Jump back in

    @ViewBuilder
    private var jumpBackInSection: some View {
        let strip = jumpBackInBooks
        if !strip.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text("Pick up where you left off")
                    .font(Theme.Fonts.display(20, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText)
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(strip) { book in
                        Button { openDetail(for: book) } label: {
                            jumpBackTile(book: book)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
            }
        }
    }

    /// Strip content: other in-progress books (after the hero) — falls
    /// back to recently-finished if the user has at most one in-progress.
    private var jumpBackInBooks: [DashboardBook] {
        if vm.currentlyReading.count > 1 {
            return Array(vm.currentlyReading.dropFirst().prefix(8))
        }
        return Array(vm.recentlyFinished.prefix(8))
    }

    @ViewBuilder
    private func jumpBackTile(book: DashboardBook) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            BookCoverImage(
                url: coverURL(for: book),
                width: 100,
                height: 150,
                title: book.title,
                author: book.authors,
                readStatus: book.readStatus
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(0.4), radius: 6, y: 3)

            Text(book.title)
                .font(Theme.Fonts.ui(12, weight: .semibold))
                .foregroundStyle(Theme.Colors.appText)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .frame(width: 100, alignment: .leading)
            if !book.authors.isEmpty {
                Text(book.authors)
                    .font(Theme.Fonts.ui(11, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText3)
                    .lineLimit(1)
                    .frame(width: 100, alignment: .leading)
            }
        }
        .frame(width: 100, alignment: .leading)
    }

    // MARK: - Helpers

    private func coverURL(for book: DashboardBook) -> URL? {
        guard let path = book.coverUrl, !path.isEmpty,
              let account = RedesignedHomeViewModel.primaryAccount(appState: appState) else { return nil }
        return URL(string: account.url + path)
    }

    // MARK: - Detail navigation

    private func openDetail(for book: DashboardBook) {
        pendingDetail = BookDetailRequest(libraryId: book.libraryId, libraryName: book.libraryName, bookId: book.bookId)
    }

    private func loadDetail(request: BookDetailRequest) async {
        defer { pendingDetail = nil }
        guard let account = RedesignedHomeViewModel.primaryAccount(appState: appState) else {
            vm.error = "No primary server selected."
            return
        }
        let client = appState.makeClient(serverURL: account.url)
        do {
            let fetched: Book = try await BookService(client: client).get(libraryId: request.libraryId, bookId: request.bookId)
            // Construct a minimal Library — RedesignedBookDetailView only
            // needs id, name, and serverURL to wire its lookups.
            var lib = try await LibraryService(client: client).get(request.libraryId)
            lib.serverURL = account.url
            lib.serverName = account.name
            loadedDetail = BookDetailLoaded(library: lib, book: fetched)
        } catch {
            vm.error = error.localizedDescription
        }
    }
}

/// Cross-tab navigation glue: a deferred request from a tile/row tap to
/// open a book detail. The view fetches the full Book + Library via
/// these IDs, then drives `loadedDetail` to push the redesigned detail.
/// Lives at file scope (internal) so Home, Search, and any future
/// jumping-from-Profile flow can share the navigation pattern.
struct BookDetailRequest: Equatable, Hashable {
    let libraryId: String
    let libraryName: String
    let bookId: String
}

struct BookDetailLoaded: Hashable {
    let library: Library
    let book: Book

    static func == (lhs: BookDetailLoaded, rhs: BookDetailLoaded) -> Bool {
        lhs.library.id == rhs.library.id && lhs.book.id == rhs.book.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(library.id)
        hasher.combine(book.id)
    }
}
