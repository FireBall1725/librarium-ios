// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

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

    @State private var vm = RedesignedSeriesListViewModel()
    @State private var searchText = ""
    @State private var selectedSeries: SeriesListEntry?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        searchPill
                        listContent
                    }
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await vm.load(appState: appState) }
            .refreshable { await vm.load(appState: appState) }
            .navigationDestination(item: $selectedSeries) { entry in
                RedesignedSeriesDetailView(library: entry.library, series: entry.series)
            }
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
            HStack(alignment: .firstTextBaseline) {
                Text("Series")
                    .font(Theme.Fonts.pageTitle)
                    .foregroundStyle(Theme.Colors.appText)
                Spacer()
                if !vm.entries.isEmpty {
                    Text(vm.entries.count == 1 ? "1 series" : "\(vm.entries.count) series")
                        .font(Theme.Fonts.ui(13, weight: .medium))
                        .foregroundStyle(Theme.Colors.appText3)
                }
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
            TextField("Filter series", text: $searchText)
                .font(Theme.Fonts.ui(14, weight: .medium))
                .foregroundStyle(Theme.Colors.appText)
                .tint(Theme.Colors.accent)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
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

    @ViewBuilder
    private var listContent: some View {
        let filtered = filteredEntries
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
                Text("Try a different search.")
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

    private var filteredEntries: [SeriesListEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return vm.entries }
        return vm.entries.filter { $0.series.name.lowercased().contains(q) }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "list.number")
                .font(.system(size: 32))
                .foregroundStyle(Theme.Colors.appText3)
            Text("No series yet")
                .font(Theme.Fonts.cardTitle)
                .foregroundStyle(Theme.Colors.appText)
            Text("Group books together by adding them to a series.")
                .font(Theme.Fonts.ui(13, weight: .medium))
                .foregroundStyle(Theme.Colors.appText3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(.horizontal, 22)
    }

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
        let count = entry.series.totalCount ?? entry.series.bookCount
        let unit = count == 1 ? "vol" : "vols"
        let status = entry.series.isComplete
            ? "complete"
            : (entry.series.status.isEmpty ? "ongoing" : entry.series.status)
        var parts = ["\(count) \(unit) · \(status)"]
        if vm.showLibraryBadge, !entry.library.name.isEmpty {
            parts.append(entry.library.name)
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - View model

struct SeriesListEntry: Identifiable, Hashable {
    let series: Series
    let library: Library

    var id: String { "\(library.id)|\(series.id)" }

    static func == (lhs: SeriesListEntry, rhs: SeriesListEntry) -> Bool {
        lhs.series.id == rhs.series.id && lhs.library.id == rhs.library.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(series.id)
        hasher.combine(library.id)
    }
}

@Observable
final class RedesignedSeriesListViewModel {
    var entries: [SeriesListEntry] = []
    var isLoading = true
    /// True when the user has more than one library on the primary
    /// account — otherwise the per-row library badge is redundant.
    var showLibraryBadge = false

    func load(appState: AppState) async {
        isLoading = true
        defer { isLoading = false }
        guard let account = primaryAccount(appState: appState) else { return }
        let client = appState.makeClient(serverURL: account.url)

        // Per-library list — fanned out so a slow library doesn't block
        // the rest. Each library hit lists its series; we then flatten
        // everything into a single sorted list keyed by series name.
        var libs: [Library]
        do {
            libs = try await LibraryService(client: client).list()
            for i in libs.indices {
                libs[i].serverURL = account.url
                libs[i].serverName = account.name
            }
        } catch {
            return
        }
        showLibraryBadge = libs.count > 1

        var collected: [SeriesListEntry] = []
        await withTaskGroup(of: (Library, [Series]).self) { group in
            for lib in libs {
                group.addTask {
                    let s = (try? await SeriesService(client: client).list(libraryId: lib.id)) ?? []
                    return (lib, s)
                }
            }
            for await (lib, list) in group {
                collected.append(contentsOf: list.map { SeriesListEntry(series: $0, library: lib) })
            }
        }
        entries = collected.sorted {
            $0.series.name.localizedStandardCompare($1.series.name) == .orderedAscending
        }
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
        guard let path = book.coverUrl, !path.isEmpty else { return nil }
        return URL(string: library.serverURL + path)
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
