// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// Redesigned book detail — mockup card #4.
///
/// Editorial hero (cover + title + author + status pills + rating stars)
/// over a quick-actions row, then conditionally a currently-lent panel,
/// description, edition stats, series, and reading-history snapshot.
///
/// The Rate / Review / Re-read sheets in the mockup are deferred to a
/// later pass (mockup card 29 + 30); the quick-action buttons are shown
/// for visual completeness with a stub alert for v1. The Loan button
/// wires into the existing `AddEditLoanSheet` until that gets its own
/// rebuild (card 33).
struct RedesignedBookDetailView: View {
    let library: Library
    let book: Book
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var currentBook: Book
    @State private var editions: [BookEdition] = []
    @State private var selectedEditionID: String?
    @State private var interaction: UserBookInteraction?
    @State private var shelves: [Shelf] = []
    @State private var seriesRefs: [BookSeriesRef] = []
    @State private var activeLoan: Loan?
    @State private var coverCacheBuster: Int = 0

    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var showClearCoverConfirm = false
    @State private var showScanner = false
    @State private var showActionStub = false
    @State private var actionStubLabel = ""
    @State private var pendingSeriesID: String?
    @State private var loadedSeries: Series?

    init(library: Library, book: Book) {
        self.library = library
        self.book = book
        self._currentBook = State(initialValue: book)
    }

    /// The primary edition — drives the hero meta line, the favorite
    /// toggle, and the user interaction (rating / status). Stable across
    /// edition-picker changes so the user-state shown above the picker
    /// doesn't shift when they're just inspecting another edition's
    /// stats below.
    private var primaryEdition: BookEdition? {
        editions.first(where: { $0.isPrimary }) ?? editions.first
    }

    /// The edition currently chosen in the picker — drives the stat grid
    /// only. Falls back to primary while the picker initialises.
    private var selectedEdition: BookEdition? {
        editions.first(where: { $0.id == selectedEditionID }) ?? primaryEdition
    }

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topNav
                    hero
                    quickActions
                    if let loan = activeLoan {
                        currentlyLentPanel(loan: loan)
                    }
                    if !currentBook.description.isEmpty {
                        section(label: "Description") {
                            Text(currentBook.description)
                                .font(Theme.Fonts.bodyPara)
                                .foregroundStyle(Theme.Colors.appText2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let edition = selectedEdition {
                        section(label: "Edition") {
                            if editions.count > 1 {
                                editionPicker
                            }
                            editionGrid(for: edition)
                        }
                    }
                    if !seriesRefs.isEmpty {
                        section(label: "Series") {
                            seriesList
                        }
                    }
                    if !shelves.isEmpty {
                        section(label: "Shelves") {
                            shelvesList
                        }
                    }
                    if let i = interaction, i.dateFinished != nil {
                        section(label: "Reading history") {
                            readingHistoryRow(interaction: i)
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        // Light up the Library tab on the floating bar regardless of
        // which tab the user navigated from (Search results, Home
        // strip, Library books grid, etc).
        .preference(key: LogicalTabPreferenceKey.self, value: AppTab.library)
        .task { await loadDetail() }
        .sheet(isPresented: $showEdit) {
            AddEditBookSheet(library: library, book: currentBook) { updated in
                currentBook = updated
            }
        }
        .alert(actionStubLabel, isPresented: $showActionStub) {
            Button("OK") { }
        } message: {
            Text("This action gets its own redesigned sheet in a later pass.")
        }
        .confirmationDialog("Delete \"\(currentBook.title)\"?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    let client = appState.makeClient(serverURL: library.serverURL)
                    try? await BookService(client: client).delete(libraryId: library.id, bookId: currentBook.id)
                    dismiss()
                }
            }
        }
        .navigationDestination(item: $loadedSeries) { series in
            RedesignedSeriesDetailView(library: library, series: series)
        }
        .onChange(of: pendingSeriesID) { _, id in
            guard let id else { return }
            Task { await loadSeries(id: id) }
        }
    }

    /// Series rows store only `seriesId` + `seriesName`; fetching the
    /// full `Series` is needed so the redesigned detail can render the
    /// hero / progress / volumes list.
    private func loadSeries(id: String) async {
        defer { pendingSeriesID = nil }
        let client = appState.makeClient(serverURL: library.serverURL)
        do {
            let series = try await SeriesService(client: client)
                .get(libraryId: library.id, seriesId: id)
            loadedSeries = series
        } catch {
            // Silently ignore — tapping a series shouldn't block detail.
        }
    }

    // MARK: - Top nav

    @ViewBuilder
    private var topNav: some View {
        HStack(spacing: 6) {
            navIconButton(systemName: "chevron.left") { dismiss() }
            Spacer()
            // Bookmark = toggle favorite. Filled when on, outline when
            // off. Disabled until the primary edition (and therefore the
            // interaction) has loaded so the optimistic toggle has a
            // record to write to.
            navIconButton(
                systemName: (interaction?.isFavorite == true) ? "bookmark.fill" : "bookmark",
                tint: (interaction?.isFavorite == true) ? Theme.Colors.gold : Theme.Colors.appText
            ) {
                Task { await toggleFavorite() }
            }
            .disabled(primaryEdition == nil)
            .opacity(primaryEdition == nil ? 0.4 : 1.0)

            Menu {
                Button { showEdit = true } label: { Label("Edit", systemImage: "pencil") }
                Button { showScanner = true } label: { Label("Scan cover", systemImage: "camera.viewfinder") }
                if let p = currentBook.coverUrl, !p.isEmpty {
                    Button("Clear cover", role: .destructive) { showClearCoverConfirm = true }
                }
                Divider()
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.06), in: Circle())
                    .overlay(Circle().stroke(Theme.Colors.appLine, lineWidth: 0.5))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func navIconButton(systemName: String, tint: Color = Theme.Colors.appText, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.06), in: Circle())
                .overlay(Circle().stroke(Theme.Colors.appLine, lineWidth: 0.5))
        }
    }

    /// Toggle the favorite flag on the primary edition's interaction.
    /// The api requires the full UpdateInteractionRequest body (no PATCH
    /// semantics yet), so we round-trip every field. UserBookInteraction
    /// has no memberwise init so we can't optimistically construct a
    /// flipped local copy — accept the network round-trip latency.
    private func toggleFavorite() async {
        guard let edition = primaryEdition, let i = interaction else { return }
        let body = UpdateInteractionRequest(
            readStatus: i.readStatus, rating: i.rating,
            notes: i.notes, review: i.review,
            dateStarted: i.dateStarted, dateFinished: i.dateFinished,
            isFavorite: !i.isFavorite
        )
        let client = appState.makeClient(serverURL: library.serverURL)
        do {
            interaction = try await BookService(client: client)
                .updateInteraction(libraryId: library.id, bookId: currentBook.id, editionId: edition.id, body: body)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            // No-op — the UI is unchanged because we didn't optimistically flip.
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        HStack(alignment: .top, spacing: 16) {
            BookCoverImage(
                url: coverURL,
                width: 130,
                height: 195,
                title: currentBook.title,
                author: primaryAuthor,
                readStatus: interaction?.readStatus
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.4), radius: 12, y: 6)

            VStack(alignment: .leading, spacing: 6) {
                Text(currentBook.title)
                    .font(Theme.Fonts.heroTitle)
                    .foregroundStyle(Theme.Colors.appText)
                    .lineLimit(3)
                Text(authorMetaLine)
                    .font(Theme.Fonts.ui(13, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText2)
                    .lineLimit(2)
                metaPills
                    .padding(.top, 6)
                if let rating = displayRating {
                    ratingLine(rating: rating)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .background(heroSplash)
    }

    /// Two blurred radial blobs (purple + indigo) bled behind the hero,
    /// matching the mockup's `.detail-hero::before` pseudo-element. The
    /// colour is title-derived so each book gets a stable splash — same
    /// hash → same palette as the generated cover fallback, so detail
    /// and grid stay visually consistent.
    @ViewBuilder
    private var heroSplash: some View {
        let palette = Self.splashPalette(for: currentBook.title)
        GeometryReader { geo in
            ZStack {
                Ellipse()
                    .fill(palette.first.opacity(0.35))
                    .frame(width: geo.size.width * 1.05, height: geo.size.height * 1.4)
                    .blur(radius: 60)
                    .offset(x: -geo.size.width * 0.2, y: -50)
                Ellipse()
                    .fill(palette.second.opacity(0.28))
                    .frame(width: geo.size.width * 0.95, height: geo.size.height * 1.2)
                    .blur(radius: 60)
                    .offset(x: geo.size.width * 0.3, y: 20)
            }
        }
        // Don't let the blur clip awkwardly at the hero's bottom — let
        // it bleed into the next section so the falloff is gradual.
        .padding(.top, -60)
        .padding(.bottom, -40)
        .allowsHitTesting(false)
    }

    private struct SplashPalette { let first: Color; let second: Color }

    private static func splashPalette(for title: String) -> SplashPalette {
        var hash: UInt32 = 5381
        for byte in title.utf8 { hash = (hash &* 33) &+ UInt32(byte) }
        let palettes: [SplashPalette] = [
            // Mockup default: violet + indigo
            SplashPalette(first: Color(hex: 0x8c50c8), second: Color(hex: 0x5064dc)),
            // Forest + teal
            SplashPalette(first: Color(hex: 0x3a8c5a), second: Color(hex: 0x2c8a96)),
            // Rose + amber
            SplashPalette(first: Color(hex: 0xc8508c), second: Color(hex: 0xdc8a50)),
            // Cobalt + violet
            SplashPalette(first: Color(hex: 0x5064dc), second: Color(hex: 0x8c50c8)),
            // Crimson + rust
            SplashPalette(first: Color(hex: 0xc85050), second: Color(hex: 0xa0623a)),
            // Gold + olive
            SplashPalette(first: Color(hex: 0xdcb850), second: Color(hex: 0x8a8c3a))
        ]
        return palettes[Int(hash % UInt32(palettes.count))]
    }

    private var coverURL: URL? {
        guard let path = currentBook.coverUrl, !path.isEmpty else { return nil }
        let base = library.serverURL + path
        return URL(string: coverCacheBuster == 0 ? base : "\(base)?v=\(coverCacheBuster)")
    }

    private var primaryAuthor: String? {
        currentBook.contributors
            .first(where: { $0.role.caseInsensitiveCompare("author") == .orderedSame })?.name
            ?? currentBook.contributors.first?.name
    }

    /// "John Grisham · 1998 · Doubleday" — author + year + publisher,
    /// pulled from the primary edition once it loads. Falls back to just
    /// the author until then.
    private var authorMetaLine: String {
        var parts: [String] = []
        if let a = primaryAuthor, !a.isEmpty { parts.append(a) }
        if let pub = primaryEdition?.publishDate, !pub.isEmpty {
            parts.append(String(pub.prefix(4)))
        }
        if let publisher = primaryEdition?.publisher, !publisher.isEmpty {
            parts.append(publisher)
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var metaPills: some View {
        HStack(spacing: 6) {
            if let pill = statusPill {
                pillView(text: pill.text, fg: pill.fg, bg: pill.bg, dot: pill.dot)
            }
            if !currentBook.genres.isEmpty {
                pillView(
                    text: currentBook.genres.first!.name,
                    fg: Theme.Colors.accentStrong,
                    bg: Theme.Colors.accentSoft,
                    dot: nil
                )
            }
            if let format = primaryEdition?.format, !format.isEmpty, format != "physical" {
                pillView(
                    text: format.capitalized,
                    fg: Theme.Colors.gold,
                    bg: Color(hex: 0xf3c971, opacity: 0.18),
                    dot: nil
                )
            }
        }
    }

    @ViewBuilder
    private func pillView(text: String, fg: Color, bg: Color, dot: Color?) -> some View {
        HStack(spacing: 5) {
            if let dot {
                Circle().fill(dot).frame(width: 6, height: 6)
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(fg)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(bg, in: Capsule())
    }

    private struct StatusPill { let text: String; let fg: Color; let bg: Color; let dot: Color? }

    /// Status pill driven by the loaded interaction. Currently `Read`
    /// (green dot), `Reading` (indigo dot), `Want to read` (gold dot),
    /// `Unread` (subtle). No interaction → nothing surfaces.
    private var statusPill: StatusPill? {
        guard let i = interaction else { return nil }
        switch i.readStatus {
        case "read":
            return StatusPill(text: "Read", fg: Theme.Colors.good, bg: Color(hex: 0x7bd6a8, opacity: 0.18), dot: Theme.Colors.good)
        case "reading":
            return StatusPill(text: "Reading", fg: Theme.Colors.accentStrong, bg: Theme.Colors.accentSoft, dot: Theme.Colors.accent)
        case "want_to_read", "want-to-read":
            return StatusPill(text: "Want to read", fg: Theme.Colors.gold, bg: Color(hex: 0xf3c971, opacity: 0.18), dot: Theme.Colors.gold)
        default:
            return nil
        }
    }

    /// Display rating pulled from the loaded interaction. The api stores
    /// the half-star integer (1–10); divide by 2 for a 0.0–5.0 display.
    private var displayRating: Double? {
        guard let raw = interaction?.rating, raw > 0 else { return nil }
        return Double(raw) / 2.0
    }

    @ViewBuilder
    private func ratingLine(rating: Double) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 1) {
                ForEach(0..<5, id: \.self) { i in
                    let filled = Double(i) < rating
                    Image(systemName: filled ? "star.fill" : "star")
                        .font(.system(size: 12))
                }
            }
            .foregroundStyle(Theme.Colors.gold)
            Text(rating.formatted(.number.precision(.fractionLength(1))))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.Colors.gold)
            Text("· your rating")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Colors.appText3)
        }
    }

    // MARK: - Quick actions

    @ViewBuilder
    private var quickActions: some View {
        HStack(spacing: 10) {
            qa(icon: "book.fill", label: "Re-read") { stub("Re-read") }
            qa(icon: "star.fill", label: "Rate")    { stub("Rate") }
            qa(icon: "bubble.left.fill", label: "Review") { stub("Review") }
            qa(icon: "arrow.up.arrow.down.circle.fill", label: "Loan") {
                stub("Loan")
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private func qa(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.06), in: Circle())
                    .overlay(Circle().stroke(Theme.Colors.appLine, lineWidth: 0.5))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func stub(_ label: String) {
        actionStubLabel = label
        showActionStub = true
    }

    // MARK: - Currently lent panel

    @ViewBuilder
    private func currentlyLentPanel(loan: Loan) -> some View {
        section(label: "Currently lent") {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(Color(hex: 0xf59e0b, opacity: 0.18))
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xf59e0b))
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Lent to \(loan.loanedTo)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.appText)
                    Text(loanDateLine(loan: loan))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Colors.appText3)
                }
                Spacer()
                Button("Mark returned") {
                    Task {
                        let client = appState.makeClient(serverURL: library.serverURL)
                        _ = try? await LoanService(client: client).markReturned(libraryId: library.id, loanId: loan.id)
                        await loadActiveLoan()
                    }
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Colors.appText2)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.clear, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.Colors.appLineStrong, lineWidth: 0.5))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(hex: 0xf59e0b, opacity: 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(hex: 0xf59e0b, opacity: 0.3), lineWidth: 0.5)
                    )
            )
        }
    }

    private func loanDateLine(loan: Loan) -> String {
        let loanedAt = formatShortDate(loan.loanedAt) ?? "?"
        if let due = loan.dueDate, let dueDate = parseISODate(due) {
            let daysOverdue = Int(Date().timeIntervalSince(dueDate) / 86400)
            if daysOverdue > 0 {
                return "Loaned \(loanedAt) · Overdue \(daysOverdue) day\(daysOverdue == 1 ? "" : "s")"
            }
        }
        return "Loaned \(loanedAt)"
    }

    // MARK: - Edition stats

    @ViewBuilder
    private func editionGrid(for edition: BookEdition) -> some View {
        // Per mockup `.stat-grid`: 2-column grid where each cell sits on
        // the card colour, separated by 0.5pt hairline dividers (the
        // app-line colour shows through the gaps), rounded outer with
        // overflow clip. Pad to even number of cells so the bottom row
        // doesn't have a gap.
        let cells = editionCells(for: edition)
        let padded = cells.count.isMultiple(of: 2) ? cells : cells + [(nil, nil)]
        VStack(spacing: 0.5) {
            ForEach(0..<(padded.count / 2), id: \.self) { row in
                HStack(spacing: 0.5) {
                    statCell(label: padded[row * 2].0,     value: padded[row * 2].1)
                    statCell(label: padded[row * 2 + 1].0, value: padded[row * 2 + 1].1)
                }
            }
        }
        .background(Theme.Colors.appLine)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func statCell(label: String?, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label {
                Text(label.uppercased())
                    .font(Theme.Fonts.label(11))
                    .tracking(1.4)
                    .foregroundStyle(Theme.Colors.appText3)
            }
            if let value {
                Text(value)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.Colors.appCard)
    }

    private func editionCells(for edition: BookEdition) -> [(String?, String?)] {
        var out: [(String?, String?)] = []
        if let p = edition.pageCount, p > 0 { out.append(("Pages", String(p))) }
        if !edition.language.isEmpty { out.append(("Language", edition.language)) }
        if !edition.isbn13.isEmpty { out.append(("ISBN-13", edition.isbn13)) }
        if !edition.isbn10.isEmpty && edition.isbn13.isEmpty {
            out.append(("ISBN-10", edition.isbn10))
        }
        if let shelf = shelves.first {
            out.append(("Shelf", shelf.name))
        }
        return out
    }

    /// Horizontal scrollable picker chips, one per edition. Active chip
    /// uses accent-soft fill; others use the neutral chip background.
    /// Label combines format + year for disambiguation when the user has
    /// e.g. two paperbacks from different printings.
    @ViewBuilder
    private var editionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(editions) { edition in
                    let active = selectedEditionID == edition.id
                    Button {
                        selectedEditionID = edition.id
                    } label: {
                        Text(editionChipLabel(for: edition))
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
            }
            // Hairline padding so chip outlines aren't clipped by the
            // ScrollView's edge.
            .padding(.horizontal, 1)
        }
        .padding(.bottom, 4)
    }

    /// Chip label: "Hardcover · 1998" if both present, otherwise whichever
    /// piece exists. Falls back to "Edition" if format is empty too.
    private func editionChipLabel(for edition: BookEdition) -> String {
        var parts: [String] = []
        if !edition.format.isEmpty {
            parts.append(edition.format.capitalized)
        }
        if let pub = edition.publishDate, !pub.isEmpty {
            parts.append(String(pub.prefix(4)))
        }
        return parts.isEmpty ? "Edition" : parts.joined(separator: " · ")
    }

    // MARK: - Series + shelves

    @ViewBuilder
    private var seriesList: some View {
        VStack(spacing: 0) {
            ForEach(seriesRefs, id: \.seriesId) { ref in
                Button { pendingSeriesID = ref.seriesId } label: {
                    HStack {
                        Image(systemName: "list.number")
                            .foregroundStyle(Theme.Colors.accent)
                        Text(ref.seriesName)
                            .font(Theme.Fonts.ui(14, weight: .medium))
                            .foregroundStyle(Theme.Colors.appText)
                        Spacer()
                        Text(volumeLabel(for: ref.position))
                            .font(Theme.Fonts.ui(12, weight: .medium))
                            .foregroundStyle(Theme.Colors.appText3)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.Colors.appText3)
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if ref.seriesId != seriesRefs.last?.seriesId {
                    Divider().background(Theme.Colors.appLine)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.Colors.appCard)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.Colors.appLine, lineWidth: 0.5))
        )
    }

    private func volumeLabel(for position: Double) -> String {
        let isWhole = position.truncatingRemainder(dividingBy: 1) == 0
        return "Vol. \(isWhole ? String(Int(position)) : String(format: "%.1f", position))"
    }

    @ViewBuilder
    private var shelvesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(shelves) { shelf in
                HStack {
                    Text(shelf.icon)
                        .font(.system(size: 18))
                    Text(shelf.name)
                        .font(Theme.Fonts.ui(14, weight: .medium))
                        .foregroundStyle(Theme.Colors.appText)
                    Spacer()
                }
                .padding(14)
                if shelf.id != shelves.last?.id {
                    Divider().background(Theme.Colors.appLine)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.Colors.appCard)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.Colors.appLine, lineWidth: 0.5))
        )
    }

    // MARK: - Reading history

    @ViewBuilder
    private func readingHistoryRow(interaction: UserBookInteraction) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Theme.Colors.accentSoft)
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Colors.accentStrong)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text("Finished reading")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText)
                Text(readingHistoryDateLine(interaction: interaction))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText3)
            }
            Spacer()
            if let rating = displayRating {
                Text("★ \(rating.formatted(.number.precision(.fractionLength(1))))")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Colors.gold)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.Colors.appCard)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.Colors.appLine, lineWidth: 0.5))
        )
    }

    private func readingHistoryDateLine(interaction: UserBookInteraction) -> String {
        let finished = interaction.dateFinished.flatMap(formatShortDate) ?? "—"
        if let started = interaction.dateStarted,
           let s = parseISODate(started),
           let e = interaction.dateFinished.flatMap(parseISODate) {
            let days = max(1, Int(e.timeIntervalSince(s) / 86400))
            return "\(finished) · \(days) day\(days == 1 ? "" : "s")"
        }
        return finished
    }

    // MARK: - Section helper

    @ViewBuilder
    private func section<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(Theme.Fonts.label(11))
                .tracking(1.2)
                .foregroundStyle(Theme.Colors.appText3)
            content()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
    }

    // MARK: - Date helpers

    private static let isoDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    private static let shortDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

    private func parseISODate(_ s: String) -> Date? {
        Self.isoDateFormatter.date(from: String(s.prefix(10)))
    }

    private func formatShortDate(_ s: String) -> String? {
        guard let d = parseISODate(s) else { return nil }
        return Self.shortDateFormatter.string(from: d)
    }

    // MARK: - Loading

    private func loadDetail() async {
        let client = appState.makeClient(serverURL: library.serverURL)
        async let e  = BookService(client: client).editions(libraryId: library.id, bookId: currentBook.id)
        async let s  = BookService(client: client).shelves(libraryId: library.id, bookId: currentBook.id)
        async let sr = BookService(client: client).seriesRefs(libraryId: library.id, bookId: currentBook.id)

        editions   = (try? await e) ?? []
        shelves    = (try? await s) ?? []
        seriesRefs = (try? await sr) ?? []

        // Default the picker to the primary edition (or first available).
        // The interaction we load for the hero / favourite toggle / status
        // pill is always the primary's — switching the picker only swaps
        // the stat-grid contents below, not the user-state shown above.
        let primary = editions.first(where: { $0.isPrimary }) ?? editions.first
        selectedEditionID = primary?.id

        if let pe = primary {
            interaction = try? await BookService(client: client)
                .interaction(libraryId: library.id, bookId: currentBook.id, editionId: pe.id)
        }

        await loadActiveLoan()
    }

    private func loadActiveLoan() async {
        let client = appState.makeClient(serverURL: library.serverURL)
        let loans = (try? await LoanService(client: client).list(libraryId: library.id)) ?? []
        activeLoan = loans.first(where: { $0.bookId == currentBook.id && $0.isActive })
    }
}
