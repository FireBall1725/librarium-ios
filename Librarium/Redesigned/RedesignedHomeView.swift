// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftData
import SwiftUI

/// Redesigned Home — mockup card #7.
///
/// Sections (top to bottom):
/// - Greeting header (date eyebrow, greeting, and a one-line shelf summary)
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
/// One server's slice of the dashboard. Aggregated by `load` into the
/// VM's merged arrays + summed stats.
private struct PerAccountDashboard {
    let serverURL: String
    let serverName: String
    let currentlyReading: [DashboardBook]
    let recentlyFinished: [DashboardBook]
    let stats: DashboardStats?
}

@Observable
final class RedesignedHomeViewModel {
    var currentlyReading: [DashboardBook] = []
    var recentlyFinished: [DashboardBook] = []
    var stats: DashboardStats?
    /// Remote-only stats, kept apart from the displayed `stats` so the
    /// Lite merge always adds to a clean remote total instead of to a
    /// number that already includes the last merge.
    private var remoteStats: DashboardStats?
    var isLoading = true
    var error: String?

    /// Fan-out load across every remote account. Each account contributes
    /// its own dashboard slice; we tag each row with the source server so
    /// covers + detail nav can route back to the right api. Lite accounts
    /// contribute a SwiftData-derived slice via `loadLite` and the
    /// results merge into the same arrays as the remote fan-out, so a
    /// mixed (remote + Lite) install sees both on one screen.
    func load(appState: AppState, modelContainer: ModelContainer) async {
        isLoading = true
        defer { isLoading = false }

        // Lite contribution — always run, no network. Computed up front so
        // both the offline and online branches can fold it in.
        let allLocal = appState.accounts.filter { $0.kind == .local }
        let liteSlice = Self.loadLite(locals: allLocal, modelContainer: modelContainer)

        // Offline / unreachable-server path runs FIRST and ignores
        // `needsReauth` — the user can't re-auth while offline, but
        // their cached dashboard tiles should still render.
        let allRemote = appState.accounts.filter { $0.kind == .remote }
        let offline = !allRemote.isEmpty && allRemote.allSatisfy { NetworkMonitor.shared.shouldSkipAPI(for: $0.url) }
        if offline {
            await loadOffline(remotes: allRemote, modelContainer: modelContainer)
            // Merge Lite into the offline result so a mixed install
            // sees its local books alongside the cached remote ones.
            mergeLite(liteSlice)
            return
        }

        let remotes = allRemote.filter { !$0.needsReauth }
        guard !remotes.isEmpty else {
            currentlyReading = liteSlice.currentlyReading
            recentlyFinished = liteSlice.recentlyFinished
            remoteStats = nil
            stats = liteSlice.stats
            // Don't surface an error for a Lite-only install — the empty
            // home screen is the expected state, not a failure.
            error = appState.accounts.isEmpty ? "No servers signed in." : nil
            return
        }

        var aggregatedReading: [DashboardBook] = []
        var aggregatedFinished: [DashboardBook] = []
        var aggregatedStats: DashboardStats? = nil
        var anySucceeded = false

        await withTaskGroup(of: PerAccountDashboard?.self) { group in
            for account in remotes {
                let url = account.url
                let name = account.name
                group.addTask {
                    let client = await appState.makeClient(serverURL: url)
                    let svc = DashboardService(client: client)
                    async let cr = svc.currentlyReading()
                    async let rf = svc.recentlyFinished()
                    async let st = svc.stats()
                    let crVal = try? await cr
                    let rfVal = try? await rf
                    let stVal = try? await st
                    if crVal == nil && rfVal == nil && stVal == nil {
                        return nil
                    }
                    return PerAccountDashboard(
                        serverURL: url,
                        serverName: name,
                        currentlyReading: crVal ?? [],
                        recentlyFinished: rfVal ?? [],
                        stats: stVal
                    )
                }
            }
            for await chunk in group {
                guard let chunk else { continue }
                anySucceeded = true
                aggregatedReading.append(contentsOf: chunk.currentlyReading.map { stamp($0, serverURL: chunk.serverURL, serverName: chunk.serverName) })
                aggregatedFinished.append(contentsOf: chunk.recentlyFinished.map { stamp($0, serverURL: chunk.serverURL, serverName: chunk.serverName) })
                aggregatedStats = Self.merge(aggregatedStats, chunk.stats)
            }
        }

        // Sort by updatedAt descending so the most-recently-touched book
        // wins the hero slot regardless of which server it lives on.
        aggregatedReading.sort { $0.updatedAt > $1.updatedAt }
        aggregatedFinished.sort { $0.updatedAt > $1.updatedAt }

        if anySucceeded {
            currentlyReading = aggregatedReading
            recentlyFinished = aggregatedFinished
            remoteStats = aggregatedStats
            stats = aggregatedStats
        }
        // Always fold in the Lite slice — even when no remote came back
        // we still want local books on the home screen.
        mergeLite(liteSlice)
    }

    /// Compute the Lite contribution to the home dashboard from
    /// `PersistedBook`. Reads `reading` and `read` rows per Lite
    /// account, resolves library names via `PersistedLibrary`, and
    /// counts up basic stats so a Lite-only install gets meaningful
    /// numbers in the stats card.
    private static func loadLite(locals: [ServerAccount], modelContainer: ModelContainer) -> DashboardSlice {
        guard !locals.isEmpty else {
            return DashboardSlice(currentlyReading: [], recentlyFinished: [], stats: nil)
        }
        let cache = BookCache(modelContainer: modelContainer)
        var reading: [DashboardBook] = []
        var finished: [DashboardBook] = []
        var totalBooks = 0
        var booksRead = 0
        var booksReading = 0

        for account in locals {
            let serverURL = ServerAccount.localURL(for: account.id)
            let context = ModelContext(modelContainer)
            let accountID = account.id
            let libDescriptor = FetchDescriptor<PersistedLibrary>(
                predicate: #Predicate { $0.serverAccountID == accountID && $0.deletedAt == nil }
            )
            let libs = (try? context.fetch(libDescriptor)) ?? []
            let libsByID = Dictionary(uniqueKeysWithValues: libs.map { ($0.id.uuidString, $0.name) })

            let readingBooks = cache.booksByReadStatus(serverURL: serverURL, statuses: ["reading"], limit: 20)
            let finishedBooks = cache.booksByReadStatus(serverURL: serverURL, statuses: ["read"], limit: 20)

            reading.append(contentsOf: readingBooks.map {
                makeLiteDashboardBook($0, libsByID: libsByID, account: account)
            })
            finished.append(contentsOf: finishedBooks.map {
                makeLiteDashboardBook($0, libsByID: libsByID, account: account)
            })

            // Counts come from a fresh fetch so they aren't capped at the
            // 20-row limit above. Cheap — Lite catalogs are small.
            let bookDescriptor = FetchDescriptor<PersistedBook>(
                predicate: #Predicate { $0.serverURL == serverURL }
            )
            let allLocalBooks = (try? context.fetch(bookDescriptor)) ?? []
            totalBooks += allLocalBooks.count
            booksRead += allLocalBooks.filter { $0.readStatus == "read" }.count
            booksReading += allLocalBooks.filter { $0.readStatus == "reading" }.count
        }

        let stats: DashboardStats? = totalBooks == 0 ? nil : DashboardStats(
            totalBooks: totalBooks,
            booksRead: booksRead,
            booksReading: booksReading,
            booksAddedThisYear: 0,
            booksReadThisYear: 0,
            favoritesCount: 0,
            monthlyReads: []
        )
        return DashboardSlice(currentlyReading: reading, recentlyFinished: finished, stats: stats)
    }

    private static func makeLiteDashboardBook(_ book: Book, libsByID: [String: String], account: ServerAccount) -> DashboardBook {
        let primaryAuthor = book.contributors
            .first(where: { $0.role.caseInsensitiveCompare("author") == .orderedSame })?.name
            ?? book.contributors.first?.name
            ?? ""
        let libraryName = libsByID[book.libraryId] ?? "Library"
        return DashboardBook(
            bookId: book.id,
            libraryId: book.libraryId,
            libraryName: libraryName,
            title: book.title,
            coverUrl: book.coverUrl,
            authors: primaryAuthor,
            readStatus: book.userReadStatus ?? "unread",
            updatedAt: "",
            serverURL: ServerAccount.localURL(for: account.id),
            serverName: account.name
        )
    }

    /// Merge a pre-computed Lite slice into the currently displayed
    /// dashboard. Keeps Lite books at the end of the reading/finished
    /// lists (remote results sort by `updatedAt`; Lite doesn't carry
    /// that field so just append), and sums the stats counters when
    /// both halves have data.
    /// Fold the Lite rows into whatever the remote paths produced.
    ///
    /// Drops any Lite rows already present before appending. The remote
    /// paths only overwrite `currentlyReading` when a server actually
    /// answered, so on a Lite-only install, or any refresh where no
    /// remote came back, the arrays still hold the previous run's rows
    /// and a plain append added a second copy of every local book. Same
    /// for stats, which were being merged into an already-merged total
    /// and so climbed on every refresh.
    private func mergeLite(_ slice: DashboardSlice) {
        currentlyReading.removeAll { $0.serverURL.hasPrefix("local://") }
        recentlyFinished.removeAll { $0.serverURL.hasPrefix("local://") }
        currentlyReading.append(contentsOf: slice.currentlyReading)
        recentlyFinished.append(contentsOf: slice.recentlyFinished)
        // Always rebuilt from the remote total rather than the current
        // displayed value, so re-merging cannot double-count.
        stats = Self.merge(remoteStats, slice.stats)
    }

    private struct DashboardSlice {
        let currentlyReading: [DashboardBook]
        let recentlyFinished: [DashboardBook]
        let stats: DashboardStats?
    }

    /// Build the dashboard from cached PersistedBook rows. Per remote
    /// account, pull up to 20 books in `reading` and `read` status sorted
    /// by recency; convert each `Book` into the `DashboardBook` shape the
    /// rest of the view consumes. Stats stay nil — they're a server-side
    /// aggregation and we don't have the data to recompute locally.
    private func loadOffline(remotes: [ServerAccount], modelContainer: ModelContainer) async {
        let cache = BookCache(modelContainer: modelContainer)
        var reading: [DashboardBook] = []
        var finished: [DashboardBook] = []

        for account in remotes {
            let libsByID = Dictionary(
                uniqueKeysWithValues: LibraryOfflineStore.shared.cachedLibraries()
                    .filter { $0.serverURL == account.url }
                    .map { ($0.id, $0.name) }
            )
            let readingBooks = cache.booksByReadStatus(
                serverURL: account.url, statuses: ["reading"], limit: 20
            )
            let finishedBooks = cache.booksByReadStatus(
                serverURL: account.url, statuses: ["read"], limit: 20
            )
            reading.append(contentsOf: readingBooks.map {
                makeDashboardBook($0, libsByID: libsByID, account: account)
            })
            finished.append(contentsOf: finishedBooks.map {
                makeDashboardBook($0, libsByID: libsByID, account: account)
            })
        }

        currentlyReading = reading
        recentlyFinished = finished
        // Cache-only path has no server aggregation to show.
        remoteStats = nil
        stats = nil
        error = nil
    }

    /// Convert a cached `Book` row into the `DashboardBook` summary
    /// shape. Author string is the primary contributor; everything else
    /// is straight pass-through from the Book payload.
    private func makeDashboardBook(_ book: Book, libsByID: [String: String], account: ServerAccount) -> DashboardBook {
        let primaryAuthor = book.contributors
            .first(where: { $0.role.caseInsensitiveCompare("author") == .orderedSame })?.name
            ?? book.contributors.first?.name
            ?? ""
        let libraryName = libsByID[book.libraryId] ?? "Library"
        return DashboardBook(
            bookId: book.id,
            libraryId: book.libraryId,
            libraryName: libraryName,
            title: book.title,
            coverUrl: book.coverUrl,
            authors: primaryAuthor,
            readStatus: book.userReadStatus ?? "unread",
            updatedAt: "",
            serverURL: account.url,
            serverName: account.name
        )
    }

    private func stamp(_ book: DashboardBook, serverURL: String, serverName: String) -> DashboardBook {
        var copy = book
        copy.serverURL = serverURL
        copy.serverName = serverName
        return copy
    }

    /// Combine two `DashboardStats` payloads by summing every counter and
    /// merging the monthly-reads series by month key. Nil acts as zero, so
    /// the first chunk through becomes the running total.
    private static func merge(_ acc: DashboardStats?, _ next: DashboardStats?) -> DashboardStats? {
        switch (acc, next) {
        case (nil, nil): return nil
        case (let a?, nil): return a
        case (nil, let b?): return b
        case (let a?, let b?):
            var months: [String: Int] = [:]
            for row in a.monthlyReads { months[row.month, default: 0] += row.count }
            for row in b.monthlyReads { months[row.month, default: 0] += row.count }
            let merged = months
                .map { MonthlyRead(month: $0.key, count: $0.value) }
                .sorted { $0.month < $1.month }
            return DashboardStats(
                totalBooks: a.totalBooks + b.totalBooks,
                booksRead: a.booksRead + b.booksRead,
                booksReading: a.booksReading + b.booksReading,
                booksAddedThisYear: a.booksAddedThisYear + b.booksAddedThisYear,
                booksReadThisYear: a.booksReadThisYear + b.booksReadThisYear,
                favoritesCount: a.favoritesCount + b.favoritesCount,
                monthlyReads: merged
            )
        }
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
    @Environment(\.modelContext) private var modelContext

    @State private var vm = RedesignedHomeViewModel()
    @State private var pendingDetail: BookDetailRequest?
    @State private var loadedDetail: BookDetailLoaded?
    @State private var showProfile = false
    /// Coalesces bursts of Lite write notifications into one reload.
    @State private var liteReloadTask: Task<Void, Never>?
    @State private var reauthAccount: ServerAccount?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        ReauthBannerStack(
                            accounts: appState.accounts.filter { $0.needsReauth },
                            onTap: { reauthAccount = $0 }
                        )
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

                // Loading overlay while a tile-tap is waiting on its
                // api round-trip. Tile taps blast through this view's
                // own load path; without an indicator the user sees
                // nothing happen until the network resolves. Once the
                // detail navigates, the overlay disappears with it.
                if pendingDetail != nil {
                    detailLoadingOverlay
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $reauthAccount) { account in
                ReauthSheet(account: account)
            }
            .task(id: appState.accounts.map(\.id)) { await vm.load(appState: appState, modelContainer: modelContext.container) }
            .refreshable { await vm.load(appState: appState, modelContainer: modelContext.container) }
            // Lite writes (scan or manual add) bump the home dashboard so
            // a freshly-added "reading" book lands on the tile row without
            // a manual pull-to-refresh.
            // Coalesced: a rating drag or a run of status taps posts
            // this on every write, and vm.load fans out to the remote
            // dashboard APIs. Without the delay one slider gesture fired
            // a burst of full network reloads.
            .onReceive(NotificationCenter.default.publisher(for: .liteLibraryDidChange)) { _ in
                liteReloadTask?.cancel()
                liteReloadTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    await vm.load(appState: appState, modelContainer: modelContext.container)
                }
            }
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
                greetingLockup
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
        // Seeded on the account id, not the name: renaming yourself
        // should not repaint your avatar.
        GeneratedAvatar(
            seed: primary?.id.uuidString ?? "librarium",
            initial: String(display.prefix(1)).uppercased(),
            size: 40
        )
    }

    private var dateEyebrow: String {
        let df = DateFormatter()
        df.dateFormat = "EEEE · MMMM d"
        return df.string(from: Date())
    }

    /// Greeting as a two-line lockup rather than one sentence.
    ///
    /// "Good afternoon, Konstantinos" on one line either wrapped at a
    /// comma or ran into the avatar, and both looked like an accident.
    /// Splitting it puts the fixed half on a small line and the name on
    /// a large one, so the width that varies is the width that has a
    /// line to itself.
    ///
    /// The two sit tight together on purpose: negative spacing overlaps
    /// the serif's generous line box so they read as one lockup instead
    /// of two stacked labels.
    /// Greeting plus a line of substance.
    ///
    /// The name is gone. It was the only part whose width varied, so it
    /// was the only part that could wrap badly or run into the avatar,
    /// and it was decoration rather than information. What replaces it
    /// says something true about the shelf, which is what the app is
    /// for.
    @ViewBuilder
    private var greetingLockup: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(timeOfDayGreeting)
                .font(Theme.Fonts.pageTitle)
                .foregroundStyle(Theme.Colors.appText)

            if let line = shelfSummary {
                Text(line)
                    .font(Theme.Fonts.ui(13, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText3)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The stat line under the greeting, or nil when there is nothing
    /// worth saying.
    ///
    /// Counts come from whatever the dashboard already loaded, so this
    /// costs no extra work. A brand-new library has no numbers to show
    /// and gets a prompt instead of a row of zeros, which would read as
    /// the app being broken rather than the shelf being empty.
    private var shelfSummary: String? {
        guard let stats = vm.stats else { return nil }

        var parts: [String] = []
        if stats.booksReadThisYear > 0 {
            parts.append("\(stats.booksReadThisYear) read this year")
        }
        if stats.booksReading > 0 {
            parts.append("\(stats.booksReading) in progress")
        }

        if parts.isEmpty {
            // Nothing read and nothing started. Say what the shelf holds
            // if it holds anything, otherwise point at the next step.
            return stats.totalBooks > 0
                ? "\(stats.totalBooks) \(stats.totalBooks == 1 ? "book" : "books") on the shelf"
                : "Scan a barcode to add your first book"
        }
        return parts.joined(separator: " · ")
    }

    private var timeOfDayGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Good night"
        }
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
        guard let path = book.coverUrl, !path.isEmpty else { return nil }
        // Lite-mode and Open-Library-sourced books carry absolute URLs;
        // server-emitted covers are relative paths that need joining
        // with the source server URL. Falling back to primary would
        // silently cross-render covers when the user has multiple
        // servers signed in.
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        let base = book.serverURL.isEmpty
            ? RedesignedHomeViewModel.primaryAccount(appState: appState)?.url ?? ""
            : book.serverURL
        guard !base.isEmpty else { return nil }
        return URL(string: base + path)
    }

    // MARK: - Detail navigation

    private func openDetail(for book: DashboardBook) {
        pendingDetail = BookDetailRequest(
            serverURL: book.serverURL,
            serverName: book.serverName,
            libraryId: book.libraryId,
            libraryName: book.libraryName,
            bookId: book.bookId
        )
    }

    @ViewBuilder
    private var detailLoadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                Text("Opening book…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText2)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.Colors.appCard.opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.Colors.appLine, lineWidth: 0.5)
            )
        }
        .transition(.opacity)
    }

    private func loadDetail(request: BookDetailRequest) async {
        defer { pendingDetail = nil }
        let resolvedURL = request.serverURL.isEmpty
            ? RedesignedHomeViewModel.primaryAccount(appState: appState)?.url
            : request.serverURL
        guard let url = resolvedURL,
              let account = appState.accounts.first(where: { $0.url == url }) else {
            vm.error = "Couldn't find the server for this book."
            return
        }

        // Short-circuit straight to cache when there's no network OR
        // this server failed an api call within the last minute — one
        // timeout teaches us the server's down so the next dozen book
        // taps don't each cost 10 seconds.
        if NetworkMonitor.shared.shouldSkipAPI(for: account.url) {
            loadDetailFromCache(account: account, request: request)
            return
        }

        let client = appState.makeClient(serverURL: account.url)
        do {
            let fetched: Book = try await BookService(client: client).get(libraryId: request.libraryId, bookId: request.bookId)
            var lib = try await LibraryService(client: client).get(request.libraryId)
            lib.serverURL = account.url
            lib.serverName = account.name
            NetworkMonitor.shared.markServerReachable(account.url)
            loadedDetail = BookDetailLoaded(library: lib, book: fetched)
        } catch {
            NetworkMonitor.shared.markServerUnreachable(account.url)
            // Server unreachable mid-flight — try the on-device cache.
            // If nothing's there either, surface the original error.
            if !loadDetailFromCache(account: account, request: request) {
                vm.error = error.localizedDescription
            }
        }
    }

    /// Populate `loadedDetail` from the on-device caches. Returns true
    /// when something was found (so the api-failure path knows whether
    /// to surface the network error or quietly swap in the cached view).
    @discardableResult
    private func loadDetailFromCache(account: ServerAccount, request: BookDetailRequest) -> Bool {
        let cache = BookCache(modelContainer: modelContext.container)
        guard let cachedBook = cache.book(
            serverURL: account.url,
            libraryId: request.libraryId,
            bookId: request.bookId
        ) else { return false }
        var lib = LibraryOfflineStore.shared.cachedLibraries()
            .first(where: { $0.id == request.libraryId && $0.serverURL == account.url })
            ?? Library(
                id: request.libraryId,
                name: request.libraryName,
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
        lib.serverURL = account.url
        lib.serverName = account.name
        loadedDetail = BookDetailLoaded(library: lib, book: cachedBook)
        return true
    }
}

/// Cross-tab navigation glue: a deferred request from a tile/row tap to
/// open a book detail. The view fetches the full Book + Library via
/// these IDs, then drives `loadedDetail` to push the redesigned detail.
/// Lives at file scope (internal) so Home, Search, and any future
/// jumping-from-Profile flow can share the navigation pattern.
struct BookDetailRequest: Equatable, Hashable {
    /// Source server's URL — empty for navigation paths that already know
    /// the active server (older call sites). `loadDetail` falls back to
    /// the preferred-account URL when this is empty so we don't regress
    /// single-server installs.
    var serverURL: String = ""
    var serverName: String = ""
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
