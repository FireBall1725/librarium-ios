// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// Redesigned series detail — mockup card #11.
///
/// Hero (3-cover stack + title + author + pills) → progress bar +
/// "Continue reading" hint when applicable → volumes list (cover thumb +
/// title + status text + check/dot/ghost indicator).
///
/// `SeriesEntry` doesn't carry `user_read_status` / progress / rating, so
/// for v1 we fetch each entry's full Book in parallel via `BookService.get`
/// to enrich the row indicators. Arc headers and ghost rows for missing
/// volumes are mockup features deferred to a later pass; the AI-suggest
/// button in the top nav is a stub for now.
struct RedesignedSeriesDetailView: View {
    let library: Library
    let series: Series
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var vm = RedesignedSeriesDetailViewModel()
    @State private var selectedBook: Book?

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topNav
                    hero
                    if vm.totalForProgress > 0 {
                        progressCard
                    }
                    if let book = vm.continueReading {
                        continueCTA(book: book)
                    }
                    volumesList
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        // Light up the Series tab on the floating bar regardless of
        // which tab the user navigated from.
        .preference(key: LogicalTabPreferenceKey.self, value: AppTab.series)
        .task { await vm.load(library: library, series: series, appState: appState) }
        .refreshable { await vm.load(library: library, series: series, appState: appState) }
        .navigationDestination(item: $selectedBook) { book in
            RedesignedBookDetailView(library: library, book: book)
        }
    }

    // MARK: - Top nav

    @ViewBuilder
    private var topNav: some View {
        HStack(spacing: 6) {
            navIcon("chevron.left") { dismiss() }
            Spacer()
            navIcon("ellipsis") { /* TODO: edit / delete menu */ }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func navIcon(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Colors.appText)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.06), in: Circle())
                .overlay(Circle().stroke(Theme.Colors.appLine, lineWidth: 0.5))
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        VStack(alignment: .center, spacing: 14) {
            coverStack
                .frame(height: 200)

            VStack(spacing: 6) {
                Text(series.name)
                    .font(Theme.Fonts.heroTitle)
                    .foregroundStyle(Theme.Colors.appText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(authorMetaLine)
                    .font(Theme.Fonts.ui(13, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText2)
                    .lineLimit(1)
            }
            .padding(.horizontal, 22)

            heroPills
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .background(heroSplash)
    }

    /// Three covers fanned out from the centre, similar to the libraries
    /// card stack. Picks the first three entries with cover URLs (or
    /// generated jackets when missing).
    @ViewBuilder
    private var coverStack: some View {
        let books = Array(vm.books.prefix(3))
        ZStack {
            // Left card (back, rotated -8°)
            if books.count > 2 {
                heroCover(book: books[2])
                    .rotationEffect(.degrees(-8))
                    .offset(x: -50, y: 8)
                    .zIndex(0)
            }
            // Right card (back, rotated +8°)
            if books.count > 1 {
                heroCover(book: books[1])
                    .rotationEffect(.degrees(8))
                    .offset(x: 50, y: 8)
                    .zIndex(1)
            }
            // Front card (centre)
            if let first = books.first {
                heroCover(book: first)
                    .zIndex(2)
            } else {
                // Empty placeholder when entries haven't loaded yet.
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.Colors.appCard)
                    .frame(width: 120, height: 180)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Theme.Colors.appLine, lineWidth: 0.5)
                    )
            }
        }
    }

    @ViewBuilder
    private func heroCover(book: Book) -> some View {
        let primaryAuthor = book.contributors
            .first(where: { $0.role.caseInsensitiveCompare("author") == .orderedSame })?.name
            ?? book.contributors.first?.name
        BookCoverImage(
            url: coverURL(for: book),
            width: 120,
            height: 180,
            title: book.title,
            author: primaryAuthor,
            readStatus: book.userReadStatus
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
    }

    private var authorMetaLine: String {
        var parts: [String] = []
        if let author = vm.primaryAuthor, !author.isEmpty {
            parts.append(author)
        }
        if let year = series.publicationYear {
            parts.append(String(year))
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var heroPills: some View {
        HStack(spacing: 6) {
            if let genre = series.genres.first, !genre.isEmpty {
                pillView(text: genre.capitalized, fg: Theme.Colors.accentStrong, bg: Theme.Colors.accentSoft)
            }
            pillView(text: volumesPillText, fg: Theme.Colors.gold, bg: Color(hex: 0xf3c971, opacity: 0.18))
        }
    }

    private var volumesPillText: String {
        let count = series.totalCount ?? series.bookCount
        let unit = count == 1 ? "vol" : "vols"
        let status = series.isComplete ? "complete" : (series.status.isEmpty ? "ongoing" : series.status)
        return "\(count) \(unit) · \(status)"
    }

    @ViewBuilder
    private func pillView(text: String, fg: Color, bg: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(bg, in: Capsule())
    }

    /// Same blurred radial blobs as the book detail hero, palette derived
    /// from the series title so the splash stays stable per series.
    @ViewBuilder
    private var heroSplash: some View {
        let palette = Self.splashPalette(for: series.name)
        GeometryReader { geo in
            ZStack {
                Ellipse()
                    .fill(palette.first.opacity(0.30))
                    .frame(width: geo.size.width * 1.0, height: geo.size.height * 1.2)
                    .blur(radius: 60)
                    .offset(x: -geo.size.width * 0.2, y: -50)
                Ellipse()
                    .fill(palette.second.opacity(0.22))
                    .frame(width: geo.size.width * 0.9, height: geo.size.height * 1.0)
                    .blur(radius: 60)
                    .offset(x: geo.size.width * 0.3, y: 20)
            }
        }
        .padding(.top, -60)
        .padding(.bottom, -40)
        .allowsHitTesting(false)
    }

    private struct SplashPalette { let first: Color; let second: Color }

    private static func splashPalette(for title: String) -> SplashPalette {
        var hash: UInt32 = 5381
        for byte in title.utf8 { hash = (hash &* 33) &+ UInt32(byte) }
        let palettes: [SplashPalette] = [
            SplashPalette(first: Color(hex: 0x8c50c8), second: Color(hex: 0x5064dc)),
            SplashPalette(first: Color(hex: 0x3a8c5a), second: Color(hex: 0x2c8a96)),
            SplashPalette(first: Color(hex: 0xc8508c), second: Color(hex: 0xdc8a50)),
            SplashPalette(first: Color(hex: 0x5064dc), second: Color(hex: 0x8c50c8)),
            SplashPalette(first: Color(hex: 0xc85050), second: Color(hex: 0xa0623a)),
            SplashPalette(first: Color(hex: 0xdcb850), second: Color(hex: 0x8a8c3a))
        ]
        return palettes[Int(hash % UInt32(palettes.count))]
    }

    // MARK: - Progress card

    @ViewBuilder
    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("YOUR PROGRESS")
                    .font(Theme.Fonts.label(11))
                    .tracking(1.2)
                    .foregroundStyle(Theme.Colors.appText3)
                Spacer()
                Text("\(vm.readCount + vm.readingCount) / \(vm.totalForProgress)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText2)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 99)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 99)
                        .fill(LinearGradient(
                            colors: [Theme.Colors.accent, Theme.Colors.accentStrong],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * CGFloat(vm.progressFraction))
                }
            }
            .frame(height: 6)

            Text(progressMetaLine)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Colors.appText3)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.Colors.appCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Theme.Colors.appLine, lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
    }

    private var progressMetaLine: String {
        let pct = Int(vm.progressFraction * 100)
        var parts: [String] = ["\(pct)%"]
        if vm.readCount > 0 { parts.append("\(vm.readCount) read") }
        if vm.readingCount > 0 { parts.append("\(vm.readingCount) reading") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Continue CTA

    @ViewBuilder
    private func continueCTA(book: Book) -> some View {
        let primaryAuthor = book.contributors
            .first(where: { $0.role.caseInsensitiveCompare("author") == .orderedSame })?.name
            ?? book.contributors.first?.name
        Button { selectedBook = book } label: {
            HStack(spacing: 12) {
                BookCoverImage(
                    url: coverURL(for: book),
                    width: 42,
                    height: 63,
                    title: book.title,
                    author: primaryAuthor,
                    readStatus: book.userReadStatus
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 3) {
                    Text("CURRENTLY READING")
                        .font(Theme.Fonts.label(10))
                        .tracking(1.2)
                        .foregroundStyle(Theme.Colors.accentStrong)
                    Text(book.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.appText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText3)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.Colors.accentSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Theme.Colors.accent.opacity(0.3), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
    }

    // MARK: - Volumes list

    @ViewBuilder
    private var volumesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("VOLUMES")
                    .font(Theme.Fonts.label(11))
                    .tracking(1.2)
                    .foregroundStyle(Theme.Colors.appText3)
                Spacer()
                if !vm.books.isEmpty {
                    Text("\(vm.books.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Colors.appText3)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 8)

            if vm.isLoading && vm.books.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .tint(Theme.Colors.appText2)
            } else if vm.books.isEmpty {
                Text("No volumes in this series yet.")
                    .font(Theme.Fonts.ui(13, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText3)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(vm.arcGroups) { group in
                    if let arc = group.arc {
                        arcHeader(arc: arc, books: group.books)
                    } else if !vm.arcs.isEmpty {
                        // Catch-all bucket label for unassigned volumes
                        // when the series otherwise has named arcs.
                        otherArcHeader(count: group.books.count)
                    }
                    volumesGroup(books: group.books)
                }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func arcHeader(arc: SeriesArc, books: [Book]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(arc.name)
                    .font(Theme.Fonts.display(17, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText)
                if let range = arcRangeLabel(arc: arc) {
                    Text(range)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Colors.appText3)
                }
            }
            Spacer()
            Text(arcStatusLabel(books: books))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Colors.appText3)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func otherArcHeader(count: Int) -> some View {
        HStack {
            Text("Other volumes")
                .font(Theme.Fonts.display(17, weight: .semibold))
                .foregroundStyle(Theme.Colors.appText)
            Spacer()
            Text(count == 1 ? "1 vol" : "\(count) vols")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Colors.appText3)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func volumesGroup(books: [Book]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(books.enumerated()), id: \.element.id) { idx, book in
                let position = vm.positions[book.id] ?? 0
                Button { selectedBook = book } label: {
                    volumeRow(book: book, position: position)
                }
                .buttonStyle(.plain)
                if idx != books.count - 1 {
                    Divider().background(Theme.Colors.appLine).padding(.leading, 22 + 36 + 12)
                }
            }
        }
    }

    private func arcRangeLabel(arc: SeriesArc) -> String? {
        guard let start = arc.volStart, let end = arc.volEnd else { return nil }
        let s = formatVol(start)
        let e = formatVol(end)
        return s == e ? "vol \(s)" : "vols \(s)–\(e)"
    }

    private func formatVol(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
    }

    private func arcStatusLabel(books: [Book]) -> String {
        let read = books.filter { $0.userReadStatus == "read" }.count
        let reading = books.filter { $0.userReadStatus == "reading" }.count
        var parts: [String] = []
        if read > 0 { parts.append("\(read) read") }
        if reading > 0 { parts.append("\(reading) reading") }
        if parts.isEmpty { parts.append(books.count == 1 ? "1 vol" : "\(books.count) vols") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func volumeRow(book: Book, position: Double) -> some View {
        let primaryAuthor = book.contributors
            .first(where: { $0.role.caseInsensitiveCompare("author") == .orderedSame })?.name
            ?? book.contributors.first?.name
        HStack(spacing: 12) {
            BookCoverImage(
                url: coverURL(for: book),
                width: 36,
                height: 54,
                title: book.title,
                author: primaryAuthor,
                readStatus: book.userReadStatus
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 3) {
                Text(volumeRowTitle(book: book, position: position))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(volumeRowSubtitle(book: book))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            statusIndicator(for: book)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func volumeRowTitle(book: Book, position: Double) -> String {
        let isWhole = position.truncatingRemainder(dividingBy: 1) == 0
        let posLabel = isWhole ? "Vol. \(Int(position))" : "Vol. \(String(format: "%.1f", position))"
        return "\(posLabel) — \(book.title)"
    }

    private func volumeRowSubtitle(book: Book) -> String {
        switch book.userReadStatus {
        case "read":            return "Read"
        case "reading":         return "Reading"
        case "did_not_finish":  return "Did not finish"
        case "want_to_read":    return "Want to read"
        default:                return book.contributors.first?.name ?? ""
        }
    }

    @ViewBuilder
    private func statusIndicator(for book: Book) -> some View {
        switch book.userReadStatus {
        case "read":
            ZStack {
                Circle().fill(Theme.Colors.good.opacity(0.18))
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.Colors.good)
            }
            .frame(width: 24, height: 24)
        case "reading":
            Circle()
                .fill(Theme.Colors.accent)
                .frame(width: 10, height: 10)
                .padding(7)
        case "did_not_finish":
            ZStack {
                Circle().fill(Theme.Colors.warn.opacity(0.18))
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.Colors.warn)
            }
            .frame(width: 24, height: 24)
        default:
            Color.clear.frame(width: 24, height: 24)
        }
    }

    // MARK: - Helpers

    private func coverURL(for book: Book) -> URL? {
        guard let path = book.coverUrl, !path.isEmpty else { return nil }
        return URL(string: library.serverURL + path)
    }
}

// MARK: - View model

@Observable
final class RedesignedSeriesDetailViewModel {
    /// Books in the series, sorted by position. Each book is the full
    /// `Book` payload (fetched per entry) so we have user_read_status,
    /// rating, etc. for the row indicators.
    var books: [Book] = []
    /// Position keyed by bookId — we lose the position when we replace
    /// `SeriesEntry` with `Book` so cache it on load.
    var positions: [String: Double] = [:]
    /// Arc id keyed by bookId. nil = book isn't assigned to any arc.
    var arcAssignments: [String: String] = [:]
    /// Arc metadata, sorted by position. Empty when the series has no arcs.
    var arcs: [SeriesArc] = []
    var isLoading = true

    func load(library: Library, series: Series, appState: AppState) async {
        isLoading = true
        defer { isLoading = false }
        let client = appState.makeClient(serverURL: library.serverURL)

        // 1. Entries (positions + arc assignments) and arcs in parallel.
        async let entriesTask = SeriesService(client: client)
            .books(libraryId: library.id, seriesId: series.id)
        async let arcsTask = SeriesService(client: client)
            .arcs(libraryId: library.id, seriesId: series.id)

        let entries: [SeriesEntry]
        do {
            entries = try await entriesTask
        } catch {
            return
        }
        positions = Dictionary(uniqueKeysWithValues: entries.map { ($0.bookId, $0.position) })
        arcAssignments = Dictionary(uniqueKeysWithValues: entries.compactMap { entry in
            entry.arcId.map { (entry.bookId, $0) }
        })

        if let loadedArcs = try? await arcsTask {
            arcs = loadedArcs.sorted { $0.position < $1.position }
        }

        // 2. Fetch each entry's full Book in parallel — required to get
        //    user_read_status and progress for the row indicator.
        var fetched: [Book] = []
        await withTaskGroup(of: Book?.self) { group in
            for entry in entries {
                group.addTask {
                    try? await BookService(client: client)
                        .get(libraryId: library.id, bookId: entry.bookId)
                }
            }
            for await book in group {
                if let book { fetched.append(book) }
            }
        }
        // Only replace if we actually got data — protects against the
        // `.refreshable`-cancellation path hosing the rendered list.
        if !fetched.isEmpty || entries.isEmpty {
            books = fetched.sorted { (positions[$0.id] ?? 0) < (positions[$1.id] ?? 0) }
        }
    }

    /// Book + position pairs for the volume rows, sorted ascending.
    var entriesByPosition: [(book: Book, position: Double)] {
        books.map { (book: $0, position: positions[$0.id] ?? 0) }
    }

    /// Volumes grouped by arc for rendering. Order: arc 1, arc 2, ...
    /// then "Other volumes" for entries without an arc assignment. When
    /// the series has no arcs at all, returns a single anonymous group.
    struct ArcGroup: Identifiable {
        let id: String              // arc id, or "__none__"
        let arc: SeriesArc?         // nil for the "no arc" bucket
        let books: [Book]
    }

    var arcGroups: [ArcGroup] {
        guard !arcs.isEmpty else {
            // No arcs: single flat group, id is sentinel so the view still has
            // something to ForEach over without rendering an arc header.
            return [ArcGroup(id: "__none__", arc: nil, books: books)]
        }
        var byArc: [String: [Book]] = [:]
        var unassigned: [Book] = []
        for book in books {
            if let arcId = arcAssignments[book.id] {
                byArc[arcId, default: []].append(book)
            } else {
                unassigned.append(book)
            }
        }
        var groups: [ArcGroup] = arcs.compactMap { arc in
            let arcBooks = (byArc[arc.id] ?? []).sorted {
                (positions[$0.id] ?? 0) < (positions[$1.id] ?? 0)
            }
            // Skip arcs with no books in the user's library — surfacing a
            // header for an empty arc would just be visual noise.
            guard !arcBooks.isEmpty else { return nil }
            return ArcGroup(id: arc.id, arc: arc, books: arcBooks)
        }
        if !unassigned.isEmpty {
            groups.append(ArcGroup(
                id: "__none__",
                arc: nil,
                books: unassigned.sorted { (positions[$0.id] ?? 0) < (positions[$1.id] ?? 0) }
            ))
        }
        return groups
    }

    /// First book the user hasn't finished — drives the "Currently
    /// reading" CTA. Picks `reading` first, then falls back to the
    /// earliest unread/unstarted volume.
    var continueReading: Book? {
        if let active = books.first(where: { $0.userReadStatus == "reading" }) {
            return active
        }
        return nil
    }

    var readCount: Int    { books.filter { $0.userReadStatus == "read" }.count }
    var readingCount: Int { books.filter { $0.userReadStatus == "reading" }.count }

    /// Denominator: `series.totalCount` if known, otherwise we use the
    /// owned-volume count as a proxy. Without a known total a half-loaded
    /// series would otherwise jump to 100% prematurely.
    var totalForProgress: Int { books.count }

    var progressFraction: Double {
        guard totalForProgress > 0 else { return 0 }
        return Double(readCount) / Double(totalForProgress)
    }

    /// Pulled from the first entry's first author — series doesn't carry
    /// author metadata directly, so we derive it from the books.
    var primaryAuthor: String? {
        for book in books {
            if let a = book.contributors
                .first(where: { $0.role.caseInsensitiveCompare("author") == .orderedSame })?.name {
                return a
            }
            if let a = book.contributors.first?.name {
                return a
            }
        }
        return nil
    }
}
