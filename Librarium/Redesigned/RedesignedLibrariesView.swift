// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// Redesigned post-auth library picker — mockup card #2.
///
/// Layout: editorial dark surface, 2-column grid where the first library
/// is rendered as a "full" card spanning both columns and the rest fall
/// into 4:5 tiles. Each card carries a themed gradient + a fanned cover
/// stack tucked in the upper-right corner so libraries read as distinct
/// even before real cover thumbnails are wired in.
///
/// v1 keeps it simple: load from every signed-in account, no offline
/// merge yet. The legacy LibrariesView retains the rich offline / reauth
/// / drag-reorder UX; we'll layer those back on this view as the redesign
/// matures.
/// VM for `RedesignedLibrariesView`. Held in `@State` on the view; the
/// reference is stable across body recomputes so closures captured by
/// `.task` / `.refreshable` keep their identity. That sidesteps the
/// cancel-on-body-recompute issue we hit with inline `@State` + inline
/// `func load()`, where pull-to-refresh would silently cancel its own
/// URL requests.
@Observable
final class RedesignedLibrariesViewModel {
    var libraries: [Library] = []
    var isLoading = true
    var error: String?
    /// First 3 books per library, keyed by clientKey. Loaded after the
    /// library list arrives — empty until then, so cards render with
    /// placeholder rectangles initially.
    var libraryCovers: [String: [CoverBook]] = [:]
    /// Per-server URL → "this server failed to load". Populated for
    /// non-cancellation errors only so the libraries grid can surface a
    /// banner ("Server X is offline") above the cards instead of
    /// silently dropping that server's libraries.
    var unreachableServerURLs: Set<String> = []

    func load(appState: AppState) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let accounts = appState.accounts
        guard !accounts.isEmpty else {
            libraries = []
            return
        }

        var collected: [Library] = []
        var firstError: String?
        var anySucceeded = false
        var anyCancelled = false
        var unreachable: Set<String> = []

        await withTaskGroup(of: (String, [Library]?, Error?).self) { group in
            for account in accounts {
                group.addTask {
                    do {
                        let client = await appState.makeClient(serverURL: account.url)
                        var libs = try await LibraryService(client: client).list()
                        for i in libs.indices {
                            libs[i].serverURL = account.url
                            libs[i].serverName = account.name
                        }
                        return (account.url, libs, nil)
                    } catch {
                        #if DEBUG
                        print("⚠️ [LibrariesVM] fetch failed for \(account.url): \(error)")
                        #endif
                        return (account.url, nil, error)
                    }
                }
            }
            for await (url, libs, err) in group {
                if let libs {
                    anySucceeded = true
                    collected.append(contentsOf: libs)
                } else if let err {
                    if Self.isCancellation(err) {
                        anyCancelled = true
                    } else {
                        unreachable.insert(url)
                        if firstError == nil {
                            firstError = err.localizedDescription
                        }
                    }
                }
            }
        }

        // Only update the unreachable set when the call wasn't a noop
        // (cancellation everywhere). Otherwise a refresh that gets
        // wholly cancelled would clear the offline indicators.
        if anySucceeded || !unreachable.isEmpty {
            unreachableServerURLs = unreachable
        }

        // Only replace on success. Cancellation isn't surfaced as an
        // error (it's noise from refresh-task supersession) — see
        // `plans/ios-redesign/PLAN.md` for context on why this VM
        // refactor exists in the first place.
        if anySucceeded {
            libraries = collected.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        if !anySucceeded, !anyCancelled, let firstError {
            error = firstError
        }

        await loadCovers(appState: appState)
    }

    /// Per-library `?per_page=3` fan-out for the fanned cover stack on
    /// each card. Best-effort — failures leave that library's stack
    /// rendering placeholder rectangles. Title + author are captured so
    /// missing covers fall back to a generated jacket.
    private func loadCovers(appState: AppState) async {
        let libs = libraries
        await withTaskGroup(of: (String, [CoverBook]).self) { group in
            for lib in libs {
                group.addTask {
                    let client = await appState.makeClient(serverURL: lib.serverURL)
                    do {
                        let page = try await BookService(client: client).list(libraryId: lib.id, perPage: 3)
                        let books = page.items.map { book -> CoverBook in
                            let url: URL? = {
                                guard let path = book.coverUrl, !path.isEmpty else { return nil }
                                return URL(string: lib.serverURL + path)
                            }()
                            let primaryAuthor = book.contributors
                                .first(where: { $0.role.caseInsensitiveCompare("author") == .orderedSame })?.name
                                ?? book.contributors.first?.name
                            return CoverBook(url: url, title: book.title, author: primaryAuthor)
                        }
                        return (lib.clientKey, books)
                    } catch {
                        return (lib.clientKey, [])
                    }
                }
            }
            for await (key, books) in group where !books.isEmpty {
                libraryCovers[key] = books
            }
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if case let APIError.networkError(inner) = error {
            return isCancellation(inner)
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }
        return false
    }
}

struct RedesignedLibrariesView: View {
    let onSelect: (Library) -> Void
    @Environment(AppState.self) private var appState

    @State private var vm = RedesignedLibrariesViewModel()
    @State private var reauthAccount: ServerAccount?
    @State private var showCreateLibrary = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        serverStatusBanners
                        gridContent
                    }
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await vm.load(appState: appState) }
            .refreshable { await vm.load(appState: appState) }
            .sheet(item: $reauthAccount) { account in
                ReauthSheet(account: account)
            }
            .sheet(isPresented: $showCreateLibrary) {
                CreateLibrarySheet { _ in
                    Task { await vm.load(appState: appState) }
                }
            }
        }
    }

    // MARK: - Server status banners

    /// Surface servers that need attention above the libraries grid:
    /// expired refresh tokens (`needsReauth`) and unreachable servers
    /// (`unreachableServerURLs`). Tapping a re-auth banner opens the
    /// existing `ReauthSheet`; offline banners get a Retry that re-runs
    /// the load.
    @ViewBuilder
    private var serverStatusBanners: some View {
        let needsReauth = appState.accounts.filter { $0.needsReauth }
        let offline = appState.accounts.filter {
            !$0.needsReauth && vm.unreachableServerURLs.contains($0.url)
        }
        if !needsReauth.isEmpty || !offline.isEmpty {
            VStack(spacing: 8) {
                ForEach(needsReauth) { account in
                    statusBanner(
                        title: "\(account.name) — sign in again",
                        subtitle: "Your session expired.",
                        tint: Theme.Colors.warn,
                        bg: Color(hex: 0xffb866, opacity: 0.12),
                        actionLabel: "Sign in"
                    ) {
                        reauthAccount = account
                    }
                }
                ForEach(offline) { account in
                    statusBanner(
                        title: "\(account.name) is unreachable",
                        subtitle: "Pull to refresh once it's back, or tap Retry.",
                        tint: Theme.Colors.bad,
                        bg: Color(hex: 0xff8a8a, opacity: 0.10),
                        actionLabel: "Retry"
                    ) {
                        Task { await vm.load(appState: appState) }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
    }

    @ViewBuilder
    private func statusBanner(
        title: String,
        subtitle: String,
        tint: Color,
        bg: Color,
        actionLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(Color.black.opacity(0.2), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(actionLabel, action: action)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.08), in: Capsule())
                .overlay(Capsule().stroke(tint.opacity(0.4), lineWidth: 0.5))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(tint.opacity(0.3), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Header (matches .nav-large)

    @ViewBuilder
    private var header: some View {
        // HStack with bottom alignment so the "+" button sits aligned with
        // the H1 baseline, matching the mockup's nav-large layout. Profile
        // lives in the bottom tab bar (per mockup) — wired up when the new
        // 5-tab bar lands.
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Librarium · Home")
                    .font(Theme.Fonts.ui(12, weight: .medium))
                    .tracking(1.0)
                    .foregroundStyle(Theme.Colors.appText3)
                    .textCase(.uppercase)
                Text("Libraries")
                    .font(Theme.Fonts.pageTitle)
                    .foregroundStyle(Theme.Colors.appText)
            }
            Spacer()

            // Mockup .nav-icon-btn — 38pt glass circle, indigo accent.
            // Single action: create a new library on the active server.
            // Server management lives on the redesigned Profile (card 8).
            Button { showCreateLibrary = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
            }
            .disabled(appState.accounts.isEmpty)
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    // MARK: - Grid

    @ViewBuilder
    private var gridContent: some View {
        if vm.isLoading && vm.libraries.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 240)
                .tint(Theme.Colors.appText2)
        } else if vm.libraries.isEmpty {
            emptyState
        } else {
            // First card spans both columns; the rest go into a 2-col grid.
            VStack(spacing: 14) {
                Button { onSelect(vm.libraries[0]) } label: {
                    LibraryCard(
                        library: vm.libraries[0],
                        isPrimary: appState.primaryAccountID == account(for: vm.libraries[0])?.id,
                        showServerName: appState.accounts.count > 1,
                        layout: .full,
                        theme: theme(for: 0),
                        covers: vm.libraryCovers[vm.libraries[0].clientKey] ?? []
                    )
                }
                .buttonStyle(.plain)

                if vm.libraries.count > 1 {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                        spacing: 14
                    ) {
                        ForEach(Array(vm.libraries.dropFirst().enumerated()), id: \.element.clientKey) { idx, lib in
                            Button { onSelect(lib) } label: {
                                LibraryCard(
                                    library: lib,
                                    isPrimary: appState.primaryAccountID == account(for: lib)?.id,
                                    showServerName: appState.accounts.count > 1,
                                    layout: .compact,
                                    theme: theme(for: idx + 1),
                                    covers: vm.libraryCovers[lib.clientKey] ?? []
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)

            if let error = vm.error {
                Text(error)
                    .font(Theme.Fonts.rowMeta)
                    .foregroundStyle(Theme.Colors.bad)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "books.vertical")
                .font(.system(size: 32))
                .foregroundStyle(Theme.Colors.appText3)
            Text("No libraries yet")
                .font(Theme.Fonts.cardTitle)
                .foregroundStyle(Theme.Colors.appText)
            Text("Create one to start cataloguing your collection.")
                .font(Theme.Fonts.rowMeta)
                .foregroundStyle(Theme.Colors.appText3)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    // MARK: - Helpers

    private func account(for library: Library) -> ServerAccount? {
        appState.accounts.first(where: { $0.url == library.serverURL })
    }

    /// Cycle through 3 themes by card index, matching the mockup's
    /// theme-1 / theme-2 alternation.
    private func theme(for index: Int) -> LibraryCardTheme {
        switch index % 3 {
        case 0: return .purple
        case 1: return .green
        default: return .rose
        }
    }

}

/// Cover-stack input: a URL plus the book metadata needed to render a
/// generated jacket if the URL is missing or fails to load.
struct CoverBook: Equatable {
    let url: URL?
    let title: String
    let author: String?
}

// MARK: - Card layout + theme

enum LibraryCardLayout {
    case full       // first row, spans both columns
    case compact    // 4:5 tile
}

enum LibraryCardTheme {
    case purple, green, rose

    var gradient: LinearGradient {
        switch self {
        case .purple:
            return LinearGradient(
                colors: [Color(hex: 0x1d1f2c), Color(hex: 0x2a1d3a)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .green:
            return LinearGradient(
                colors: [Color(hex: 0x1f2a1f), Color(hex: 0x1a2e35)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .rose:
            return LinearGradient(
                colors: [Color(hex: 0x2a1d24), Color(hex: 0x1f1c2e)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

}

// MARK: - Library card

private struct LibraryCard: View {
    let library: Library
    let isPrimary: Bool
    let showServerName: Bool
    let layout: LibraryCardLayout
    let theme: LibraryCardTheme
    let covers: [CoverBook]

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Fanned cover stack — sits in the top-right corner, behind
            // text. Real covers when available, generated jackets when
            // we have a title but no image, themed placeholder rects
            // otherwise.
            CoverStack(covers: covers)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            // Foreground content
            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                Text(library.name)
                    .font(layout == .full
                          ? Theme.Fonts.display(22, weight: .semibold)
                          : Theme.Fonts.display(18, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText)
                    .lineLimit(2)
                Text(countLine)
                    .font(Theme.Fonts.ui(13, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText2)
                    .monospacedDigit()
                if showServerName, !library.serverName.isEmpty {
                    Text(library.serverName)
                        .font(Theme.Fonts.label(9))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Colors.appText3)
                        .padding(.top, 2)
                }
                pills
                    .padding(.top, 8)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(layout == .full ? 16.0/7.0 : 4.0/5.0, contentMode: .fit)
        .background(theme.gradient)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Theme.Colors.appLine, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var pills: some View {
        HStack(spacing: 6) {
            if isPrimary {
                pill(text: "Primary", textColor: Theme.Colors.accentStrong, bg: Theme.Colors.accentSoft)
            }
            if library.isPublic {
                pill(text: "Public", textColor: Theme.Colors.gold, bg: Color(hex: 0xf3c971, opacity: 0.15))
            }
        }
    }

    @ViewBuilder
    private func pill(text: String, textColor: Color, bg: Color) -> some View {
        Text(text)
            .font(Theme.Fonts.label(9))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(bg, in: Capsule())
    }

    private var countLine: String {
        let book = library.bookCount ?? 0
        let reading = library.readingCount ?? 0
        let read = library.readCount ?? 0
        if book == 0 { return "Empty library" }
        var parts = ["\(book.formatted()) book\(book == 1 ? "" : "s")"]
        if reading > 0 { parts.append("\(reading) reading") }
        if read > 0 { parts.append("\(read.formatted()) read") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Fanned cover stack

private struct CoverStack: View {
    let covers: [CoverBook]

    var body: some View {
        // Render exactly N cards in a fanned stack — empty libraries get
        // no stack at all; 1 book gets a single centered card; 2 books
        // get a small fan; 3+ books get the full three-card composition.
        GeometryReader { geo in
            let w = geo.size.width
            let coverW = w * 0.42
            let coverH = coverW * 1.5
            let count = min(covers.count, 3)

            ZStack {
                if count >= 3 {
                    cover(at: 2, w: coverW, h: coverH)
                        .rotationEffect(.degrees(-12))
                        .offset(x: -coverW * 0.55, y: coverH * 0.18)
                }
                if count >= 2 {
                    cover(at: count == 2 ? 1 : 0, w: coverW, h: coverH)
                        .rotationEffect(.degrees(8))
                        .offset(x: 0, y: coverH * 0.12)
                }
                if count >= 1 {
                    // Front card: index 0 when only one cover, index 1
                    // (the middle of the stack) when 2+ — keeps the
                    // visually-emphasised slot showing the first book.
                    cover(at: count >= 3 ? 1 : 0, w: coverW, h: coverH)
                        .rotationEffect(.degrees(-3))
                        .offset(x: -coverW * 0.28, y: 0)
                }
            }
            .frame(width: w * 0.65, height: coverH * 1.3, alignment: .topTrailing)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .padding(12)
    }

    @ViewBuilder
    private func cover(at idx: Int, w: CGFloat, h: CGFloat) -> some View {
        let book = covers[idx]
        BookCoverImage(url: book.url, width: w, height: h, title: book.title, author: book.author)
            .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
    }
}
