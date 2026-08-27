// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftData
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
    @Environment(\.modelContext) private var modelContext

    @State private var currentBook: Book
    @State private var editions: [BookEdition] = []
    @State private var selectedEditionID: String?
    @State private var interaction: UserBookInteraction?
    /// The work-keyed answer, when this server has one. Held alongside rather
    /// than instead of `interaction`: it carries `inherited`, which the
    /// per-edition shape has no field for and which the view wants to say out
    /// loud when a status came from an omnibus rather than from this book.
    @State private var myBook: MyBook?
    /// Local SwiftData mirror of the primary edition's interaction.
    /// Source of truth for fields covered by the sync protocol
    /// (`isFavorite`, `rating`); other fields still come from
    /// `interaction` until they get their own sync columns.
    @State private var persisted: PersistedInteraction?
    @State private var shelves: [Shelf] = []
    /// The lists holding this book, which is what the section renders.
    ///
    /// Separate from `shelves` rather than replacing it: shelves still feed the
    /// offline cache, and a server too old for lists answers with those, folded
    /// into the same shape.
    @State private var bookLists: [SavedList] = []
    /// The physical objects this book exists as. Empty on a server without
    /// copies, which is why the section is hidden rather than shown as none.
    @State private var copies: [Copy] = []
    @State private var seriesRefs: [BookSeriesRef] = []
    /// Volumes bound into this book, and books this one is bound into.
    @State private var contents: [BookContentLink] = []
    @State private var containers: [BookContentLink] = []
    /// Another book pushed from this one: a volume inside this omnibus, or the
    /// omnibus this volume sits in.
    @State private var pushedBook: Book?
    /// The reader's wishlist entry for this book, when they have one. A wish is
    /// a row of its own rather than a flag on the book, because most wishes are
    /// for books no catalogue has heard of.
    @State private var wishEntry: WishlistEntry?
    @State private var wishBusy = false
    @State private var activeLoan: Loan?
    @State private var coverCacheBuster: Int = 0

    @State private var showEdit = false
    @State private var showRefreshMetadata = false
    @State private var showDeleteConfirm = false
    @State private var showClearCoverConfirm = false
    @State private var showScanner = false
    @State private var showActionStub = false
    @State private var actionStubLabel = ""
    @State private var showRateSheet = false
    @State private var showStatusSheet = false
    @State private var showProgressSheet = false
    @State private var pendingSeriesID: String?
    @State private var loadedSeries: Series?

    init(library: Library, book: Book) {
        self.library = library
        self.book = book
        self._currentBook = State(initialValue: book)
    }

    /// The primary edition — drives the hero meta line, the favourite
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

    /// Lite libraries carry a synthetic `local://` URL and have no api
    /// behind them, so every write has to go through SwiftData instead.
    private var isLocalLibrary: Bool {
        library.serverURL.hasPrefix("local://")
    }

    /// The account this library belongs to, matched the same way
    /// `writeLocal` does. Every SwiftData row is keyed on it, so a write
    /// without it would land under the wrong account.
    private var localAccountID: UUID? {
        appState.accounts.first(where: { $0.url == library.serverURL })?.id
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
                    if !contents.isEmpty {
                        section(label: contents.count == 1 ? "Contains" : "Contains (\(contents.count))") {
                            containmentList(contents, positionKnown: true)
                        }
                    }
                    if !containers.isEmpty {
                        section(label: containers.count == 1 ? "Bound into" : "Bound into (\(containers.count))") {
                            containmentList(containers, positionKnown: false)
                        }
                    }
                    if !copies.isEmpty {
                        section(label: copies.count == 1 ? "Copy" : "Copies (\(copies.count))") {
                            copiesList
                        }
                    }
                    if !bookLists.isEmpty {
                        section(label: "Lists") {
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
        .navigationDestination(item: $pushedBook) { book in
            RedesignedBookDetailView(library: library, book: book)
        }
        // Light up the Library tab on the floating bar regardless of
        // which tab the user navigated from (Search results, Home
        // strip, Library books grid, etc).
        .preference(key: LogicalTabPreferenceKey.self, value: AppTab.books)
        .task { await loadDetail() }
        .sheet(isPresented: $showEdit) {
            if isLocalLibrary, let accountID = localAccountID {
                LiteEditBookSheet(
                    library: library,
                    book: currentBook,
                    serverAccountID: accountID
                ) { updated in
                    currentBook = updated
                    // The book row is state we hold directly, but
                    // editions are not: they load in .task, which does
                    // not re-fire when a sheet dismisses. Without this,
                    // an edited ISBN or publisher stays stale until the
                    // user backs out and reopens the book.
                    Task { await loadDetail() }
                }
            } else {
                AddEditBookSheet(library: library, book: currentBook) { updated in
                    currentBook = updated
                    Task { await loadDetail() }
                }
            }
        }
        .sheet(isPresented: $showRefreshMetadata) {
            if let accountID = localAccountID {
                LiteRefreshMetadataSheet(
                    library: library,
                    book: currentBook,
                    serverAccountID: accountID
                ) { updated in
                    currentBook = updated
                    // The cover is an AsyncImage keyed on the URL, and a
                    // refresh often keeps the same URL while pointing at
                    // a different image. Bump the buster so it re-reads.
                    coverCacheBuster += 1
                    // Refresh writes edition fields too (ISBN, publisher,
                    // pages), which live in `editions` rather than on the
                    // book row.
                    Task { await loadDetail() }
                }
            }
        }
        // Deliberately no `.liteLibraryDidChange` listener here. This
        // view posts that notification itself on every favourite,
        // rating, status and progress write, so listening made it
        // reload in response to its own writes — re-firing the
        // `book_detail_opened` telemetry event each time and inflating
        // that metric. The edit and refresh sheets reload explicitly
        // through their callbacks, which is the only case that needs it.
        .sheet(isPresented: $showRateSheet) {
            RedesignedRateSheet(
                initialRawRating: displayRawRating
            ) { newRawRating in
                Task { await applyRating(newRawRating) }
            }
        }
        .sheet(isPresented: $showStatusSheet) {
            RedesignedStatusSheet(
                initialStatus: displayReadStatus
            ) { newStatus in
                Task { await applyReadStatus(newStatus) }
            }
        }
        .sheet(isPresented: $showProgressSheet) {
            RedesignedProgressSheet(
                pageCount: primaryEdition?.pageCount,
                initialPagesRead: currentPagesRead,
                onSavePages: { newPages in
                    Task { await applyProgress(pagesRead: newPages) }
                },
                onMarkFinished: {
                    Task { await applyReadStatus("read") }
                },
                onSetPageCount: { newPageCount in
                    await setEditionPageCount(newPageCount)
                }
            )
        }
        .alert(actionStubLabel, isPresented: $showActionStub) {
            Button("OK") { }
        } message: {
            Text("This action gets its own redesigned sheet in a later pass.")
        }
        .confirmationDialog("Delete \"\(currentBook.title)\"?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await deleteBook() }
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
            // Bookmark = toggle favourite. Filled when on, outline when
            // off. Disabled until the primary edition (and therefore the
            // interaction) has loaded so the optimistic toggle has a
            // record to write to.
            navIconButton(
                systemName: displayIsFavorite ? "bookmark.fill" : "bookmark",
                tint: displayIsFavorite ? Theme.Colors.gold : Theme.Colors.appText
            ) {
                Task { await toggleFavorite() }
            }
            // A bare bookmark is a guess, and on a touch screen there is no
            // hover to reveal what it does. The icon stays, because the nav bar
            // is where iOS puts icons; the meaning goes to VoiceOver, which is
            // the only reader that had no way to find it.
            .accessibilityLabel(displayIsFavorite ? "Remove from favourites" : "Add to favourites")
            .accessibilityAddTraits(displayIsFavorite ? [.isSelected] : [])
            .disabled(primaryEdition == nil)
            .opacity(primaryEdition == nil ? 0.4 : 1.0)

            Menu {
                // Only against a real server. A Lite library has no wishlist
                // route behind it, and a menu item that always fails is worse
                // than one that is not there.
                if !isLocalLibrary {
                    Button {
                        Task { await toggleWish() }
                    } label: {
                        Label(
                            wishEntry == nil ? "Add to wishlist" : "Remove from wishlist",
                            systemImage: wishEntry == nil ? "heart" : "heart.slash"
                        )
                    }
                    .disabled(wishBusy)
                }
                // Edit routes to whichever sheet can actually write:
                // AddEditBookSheet saves through the api, LiteEditBookSheet
                // through SwiftData. Scan-cover and clear-cover stay
                // api-only — a Lite cover needs local image storage that
                // does not exist yet.
                Button { showEdit = true } label: { Label("Edit", systemImage: "pencil") }
                if isLocalLibrary {
                    // Lite has no server-side enrichment, so this is the
                    // only way a local book ever gains a description or
                    // a cover it did not arrive with. With every source
                    // switched off there is nowhere to look, so say that
                    // rather than opening a sheet that can only fail.
                    if LiteMetadataSettings.hasActiveProvider {
                        Button { showRefreshMetadata = true } label: {
                            Label("Refresh metadata", systemImage: "arrow.clockwise")
                        }
                    } else {
                        Button {} label: {
                            Label("No metadata sources enabled", systemImage: "arrow.clockwise")
                        }
                        .disabled(true)
                    }
                } else {
                    Button { showScanner = true } label: { Label("Scan cover", systemImage: "camera.viewfinder") }
                    if let p = currentBook.coverUrl, !p.isEmpty {
                        Button("Clear cover", role: .destructive) { showClearCoverConfirm = true }
                    }
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

    /// Mutate the local PersistedInteraction (creating it on the fly
    /// if the row doesn't exist yet) and enqueue an outbox op. Returns
    /// the account ID so the caller can kick a drain. Returns nil only
    /// when the edition/account refs can't be resolved.
    ///
    /// Works without an api `interaction` DTO — required for Lite
    /// books, where there's no server-side row to fetch first. Falls
    /// back to sensible defaults (unread / not favourite / no rating)
    /// when synthesising a new PersistedInteraction.
    private func writeLocal(_ mutate: (PersistedInteraction, Date) -> Void) -> UUID? {
        guard let editionID = (primaryEdition.flatMap { UUID(uuidString: $0.id) }),
              let account = appState.accounts.first(where: { $0.url == library.serverURL })
        else { return nil }

        // Synthesising defaults is a Lite-only affordance: there is no
        // server row to fetch first, so "no interaction yet" genuinely
        // means unread/unrated. On a remote book the same state means
        // the fetch has not landed (offline, server down, or a tap
        // during loadDetail), and inventing an unread row would both
        // show the wrong status and never reach the outbox, since there
        // is no api interaction id to enqueue against.
        guard isLocalLibrary || interaction != nil || persisted != nil else { return nil }

        let now = Date()
        let row: PersistedInteraction
        if let p = persisted {
            row = p
        } else {
            // Prefer the api DTO's id when we have one (online flow);
            // generate fresh otherwise (Lite or no-api-yet flow). The
            // id only matters as a stable PersistedInteraction primary
            // key; subsequent writes find the row by editionID anyway.
            let entityID: UUID
            if let i = interaction, let parsed = UUID(uuidString: i.id) {
                entityID = parsed
            } else {
                entityID = UUID()
            }
            let baseUpdatedAt = interaction
                .flatMap { SyncTimestampFormatter.shared.date(from: $0.updatedAt) }
                ?? now
            row = PersistedInteraction(
                id: entityID,
                serverAccountID: account.id,
                bookEditionID: editionID,
                readStatus: interaction?.readStatus ?? "unread",
                isFavorite: interaction?.isFavorite ?? false,
                updatedAt: baseUpdatedAt
            )
            row.rating = interaction?.rating.map { Int($0) }
            modelContext.insert(row)
            persisted = row
        }

        mutate(row, now)
        row.updatedAt = now

        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("📤 [writeLocal] save failed: \(error)")
            #endif
            return nil
        }

        // For Lite there's no remote sync to round-trip the change back
        // into `PersistedBook`, so the denormalised columns the home
        // dashboard / libraries grid query on would stay stale. Mirror
        // the interaction state onto the PersistedBook row directly,
        // then ping any open Lite-aware view so it re-reads.
        if account.kind == .local {
            mirrorInteractionToPersistedBook(row: row)
            NotificationCenter.default.post(
                name: .liteLibraryDidChange,
                object: nil,
                userInfo: ["libraryID": library.id]
            )
        }

        return account.id
    }

    /// Copy interaction state onto the book's denormalised columns +
    /// JSON payload so list views (home dashboard, libraries grid,
    /// books grid) see the up-to-date status/rating/favourite/progress
    /// without waiting on a sync. Lite-only path — for remote, the
    /// `BookCache.upsert` after the next sync handles this.
    private func mirrorInteractionToPersistedBook(row: PersistedInteraction) {
        let compositeID = PersistedBook.compositeID(
            serverURL: library.serverURL,
            libraryId: library.id,
            bookId: currentBook.id
        )
        var descriptor = FetchDescriptor<PersistedBook>(
            predicate: #Predicate { $0.id == compositeID }
        )
        descriptor.fetchLimit = 1
        guard let bookRow = try? modelContext.fetch(descriptor).first else { return }

        bookRow.readStatus = row.readStatus
        bookRow.rating = row.rating
        bookRow.isFavorite = row.isFavorite
        bookRow.updatedAt = row.updatedAt

        // Decode pages_read out of the progressJSON blob and convert to
        // percentage using the primary edition's pageCount. Without a
        // pageCount we can't compute a meaningful pct, so leave it nil.
        if let data = row.progressJSON,
           let dict = try? JSONDecoder().decode([String: Int].self, from: data),
           let pages = dict["pages_read"],
           let total = primaryEdition?.pageCount, total > 0 {
            bookRow.progressPct = Double(pages) / Double(total) * 100.0
        } else if row.progressJSON == nil {
            bookRow.progressPct = nil
        }

        // Re-encode the embedded Book payload so anyone decoding it
        // (home loadLite passes the decoded Book to DashboardBook) sees
        // the same state as the columns. Book's fields are `let`, so we
        // patch the JSON dict directly rather than mutating a struct.
        if var dict = (try? JSONSerialization.jsonObject(with: bookRow.payload)) as? [String: Any] {
            dict["userReadStatus"] = row.readStatus
            if let r = row.rating {
                dict["userRating"] = r
            } else {
                dict["userRating"] = NSNull()
            }
            if let pct = bookRow.progressPct {
                dict["userProgressPct"] = pct
            } else {
                dict["userProgressPct"] = NSNull()
            }
            if let reencoded = try? JSONSerialization.data(withJSONObject: dict) {
                bookRow.payload = reencoded
            }
        }

        try? modelContext.save()
    }

    /// Enqueue a sync op + kick a drain. No-op for local (Lite)
    /// accounts since there's nothing to drain to — the SwiftData
    /// write done in `writeLocal` is already the source of truth.
    /// Caller passes the same `accountID` returned from writeLocal.
    private func enqueueAndKick(op: PendingSyncOp, accountID: UUID) {
        guard let account = appState.accounts.first(where: { $0.id == accountID }),
              account.kind == .remote else { return }
        modelContext.insert(op)
        try? modelContext.save()
        kickDrain(accountID: accountID)
    }

    private func kickDrain(accountID: UUID) {
        let api = appState.makeClient(serverURL: library.serverURL)
        let service = SyncService(
            api: api,
            serverAccountID: accountID,
            modelContainer: modelContext.container
        )
        Task { try? await service.drainOutbox() }
    }

    /// Save a new page_count onto the primary edition. Carries every
    /// other edition field through unchanged because the api uses
    /// CreateEditionRequest as a full-replacement body. Returns true
    /// on success so the Progress sheet can swap from the page-count
    /// entry field to the slider.
    private func setEditionPageCount(_ newPageCount: Int) async -> Bool {
        guard let edition = primaryEdition else { return false }
        let client = appState.makeClient(serverURL: library.serverURL)
        let body = CreateEditionRequest(
            format: edition.format,
            language: edition.language,
            editionName: edition.editionName,
            narrator: edition.narrator,
            publisher: edition.publisher,
            publishDate: edition.publishDate,
            isbn10: edition.isbn10,
            isbn13: edition.isbn13,
            description: edition.description,
            pageCount: newPageCount,
            copyCount: edition.copyCount,
            isPrimary: edition.isPrimary
        )
        do {
            let updated = try await BookService(client: client).updateEdition(
                libraryId: library.id,
                bookId: currentBook.id,
                editionId: edition.id,
                body: body
            )
            if let idx = editions.firstIndex(where: { $0.id == updated.id }) {
                editions[idx] = updated
            }
            return true
        } catch {
            #if DEBUG
            print("📝 [setEditionPageCount] failed: \(error)")
            #endif
            return false
        }
    }

    /// Apply a new reading-progress value through the outbox. The
    /// progress field is a JSONB blob (`{pages_read?, percent?,
    /// position?}` per the sync protocol); v1 only writes pages_read.
    /// Pass nil to clear progress entirely.
    private func applyProgress(pagesRead: Int?) async {
        let opValue: SyncJSONValue?
        let progressData: Data?
        if let pages = pagesRead {
            let dict: [String: SyncJSONValue] = ["pages_read": .int(pages)]
            let value = SyncJSONValue.object(dict)
            opValue = value
            progressData = value.encodedJSON()
        } else {
            opValue = .null
            progressData = nil
        }

        let accountID = writeLocal { row, now in
            row.progressJSON = progressData
            row.progressUpdatedAt = now
        }
        guard let accountID else { return }

        // Only enqueue an outbox op when there's an api `interaction.id`
        // to address it to. Lite books never have one — writeLocal above
        // is already the source of truth, so we just skip the enqueue.
        if let entityID = interaction.flatMap({ UUID(uuidString: $0.id) }) {
            let op = PendingSyncOp.progress(
                serverAccountID: accountID,
                entityID: entityID,
                value: opValue
            )
            enqueueAndKick(op: op, accountID: accountID)
        }

        if let pages = pagesRead, let totalPages = primaryEdition?.pageCount, totalPages > 0 {
            let pct = Int((Double(pages) / Double(totalPages) * 100.0).rounded())
            TelemetryService.shared.send(
                "progress_updated",
                payload: ["pct_bucket": progressBucket(forPercent: pct)]
            )
        } else if pagesRead == nil {
            TelemetryService.shared.send("progress_cleared")
        }
    }

    /// Bucket the reading-progress percentage so the dashboard sees
    /// engagement without inferring anything about a specific book.
    private func progressBucket(forPercent pct: Int) -> String {
        switch pct {
        case ..<11: return "0-10"
        case 11...25: return "11-25"
        case 26...50: return "26-50"
        case 51...75: return "51-75"
        case 76...99: return "76-99"
        default: return "100"
        }
    }

    /// The local row for this work.
    ///
    /// Prefers the book key and falls back to the edition. A row written before
    /// reading state moved to the work has no book until a read fills it in, so
    /// during that window the edition is the only way to find it, and losing
    /// track of it would mean an offline edit sitting in the outbox against a
    /// row the view no longer believes exists.
    private func fetchPersisted(bookID: UUID, editionID: UUID?) -> PersistedInteraction? {
        let byBook = FetchDescriptor<PersistedInteraction>(
            predicate: #Predicate { $0.bookID == bookID }
        )
        if let row = (try? modelContext.fetch(byBook))?.first { return row }

        guard let editionID else { return nil }
        let byEdition = FetchDescriptor<PersistedInteraction>(
            predicate: #Predicate { $0.bookEditionID == editionID }
        )
        guard let row = (try? modelContext.fetch(byEdition))?.first else { return nil }
        // Found the old way, so record the answer rather than looking it up
        // again on every open.
        if row.bookID == nil {
            row.bookID = bookID
            try? modelContext.save()
        }
        return row
    }

    /// Apply a new read-status through the outbox. Same pattern as
    /// toggleFavorite / applyRating: mutate PersistedInteraction first
    /// (source of truth), enqueue a PendingSyncOp, kick a background
    /// drain. Direct PUT to /my-interaction for this field is gone.
    private func applyReadStatus(_ newStatus: String) async {
        let accountID = writeLocal { row, now in
            row.readStatus = newStatus
            row.readStatusUpdatedAt = now
        }
        guard let accountID else { return }

        if let entityID = interaction.flatMap({ UUID(uuidString: $0.id) }) {
            let op = PendingSyncOp.readStatus(
                serverAccountID: accountID,
                entityID: entityID,
                value: newStatus
            )
            enqueueAndKick(op: op, accountID: accountID)
        }

        TelemetryService.shared.send(
            "status_set",
            payload: ["status": newStatus]
        )
    }

    /// Apply a new rating (or clear it) through the outbox.
    /// Writes to PersistedInteraction first (source of truth), queues
    /// a PendingSyncOp, then kicks a background drain.
    private func applyRating(_ newRawRating: Int?) async {
        let accountID = writeLocal { row, now in
            row.rating = newRawRating
            row.ratingUpdatedAt = now
        }
        guard let accountID else { return }

        if let entityID = interaction.flatMap({ UUID(uuidString: $0.id) }) {
            let op = PendingSyncOp.rating(
                serverAccountID: accountID,
                entityID: entityID,
                value: newRawRating
            )
            enqueueAndKick(op: op, accountID: accountID)
        }

        if let raw = newRawRating {
            TelemetryService.shared.send(
                "rating_set",
                payload: ["stars_half": String(raw)]
            )
        } else {
            TelemetryService.shared.send("rating_cleared")
        }
    }

    /// Toggle the favourite flag through the outbox. PersistedInteraction
    /// is the source of truth; @Observable makes the UI update when we
    /// mutate it. `BookService.updateInteraction` PUT is gone for this
    /// field; other fields still use it pending their own rewires.
    private func toggleFavorite() async {
        let newFavorite = !displayIsFavorite

        let accountID = writeLocal { row, now in
            row.isFavorite = newFavorite
            row.isFavoriteUpdatedAt = now
        }
        guard let accountID else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if let entityID = interaction.flatMap({ UUID(uuidString: $0.id) }) {
            let op = PendingSyncOp.isFavorite(
                serverAccountID: accountID,
                entityID: entityID,
                value: newFavorite
            )
            enqueueAndKick(op: op, accountID: accountID)
        }

        TelemetryService.shared.send(
            "favourite_toggled",
            payload: ["enabled": newFavorite ? "true" : "false"]
        )
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
                readStatus: displayReadStatus
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
        // Use the library's resolver so absolute Open Library covers on
        // Lite books work alongside the relative `/covers/...` paths the
        // self-hosted api emits. Cache-buster is reapplied after the
        // resolver picks the right base.
        guard let base = library.coverURL(for: currentBook.coverUrl) else { return nil }
        if coverCacheBuster == 0 { return base }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        items.append(URLQueryItem(name: "v", value: String(coverCacheBuster)))
        components?.queryItems = items
        return components?.url ?? base
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
            Button {
                showStatusSheet = true
            } label: {
                pillView(text: statusPill.text, fg: statusPill.fg, bg: statusPill.bg, dot: statusPill.dot)
            }
            .buttonStyle(.plain)
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

    /// Status pill driven by the local source of truth (PersistedInteraction
    /// first, then the api-loaded DTO). Always renders a pill so the user
    /// has a tap target; the muted "Unread" variant covers the not-yet-rated
    /// case.
    private var statusPill: StatusPill {
        switch displayReadStatus {
        case "read":
            // Said so rather than left to look like a mistake. A volume inside
            // an omnibus the reader finished reads as Read without anyone
            // having opened this book, and "Read in a collection" is the
            // difference between that and a wrong answer.
            let text = readStatusIsInherited ? "Read in a collection" : "Read"
            return StatusPill(text: text, fg: Theme.Colors.good, bg: Color(hex: 0x7bd6a8, opacity: 0.18), dot: Theme.Colors.good)
        case "reading":
            return StatusPill(text: "Reading", fg: Theme.Colors.accentStrong, bg: Theme.Colors.accentSoft, dot: Theme.Colors.accent)
        case "want_to_read", "want-to-read":
            return StatusPill(text: "Want to read", fg: Theme.Colors.gold, bg: Color(hex: 0xf3c971, opacity: 0.18), dot: Theme.Colors.gold)
        case "did_not_finish":
            return StatusPill(text: "Did not finish", fg: Theme.Colors.bad, bg: Color(hex: 0xff8a8a, opacity: 0.18), dot: Theme.Colors.bad)
        default:
            return StatusPill(text: "Unread", fg: Theme.Colors.appText3, bg: Color.white.opacity(0.05), dot: nil)
        }
    }

    /// Raw (1-10) rating from the local source of truth: SwiftData
    /// first, fall back to the api-loaded interaction. Returns nil
    /// when nothing has been rated yet.
    private var displayRawRating: Int? {
        if let p = persisted, let r = p.rating, r > 0 { return r }
        if let raw = interaction?.rating, raw > 0 { return Int(raw) }
        return nil
    }

    /// Display rating (0.0-5.0). Half-star scale, derived from the
    /// raw 1-10 value the api stores.
    private var displayRating: Double? {
        guard let raw = displayRawRating else { return nil }
        return Double(raw) / 2.0
    }

    /// Favourite state from the local source of truth.
    private var displayIsFavorite: Bool {
        if let p = persisted { return p.isFavorite }
        return interaction?.isFavorite ?? false
    }

    /// Read-status from the local source of truth. Defaults to
    /// "unread" so the pill always has something to render.
    private var displayReadStatus: String {
        if let p = persisted { return p.readStatus }
        return interaction?.readStatus ?? "unread"
    }

    /// Whether the status came from a collection holding this book rather than
    /// from anything said about the book itself.
    ///
    /// Only a server that keys reading state to the work can answer this, and
    /// only until the reader says something of their own: a local row means
    /// they have, so it wins. Worth surfacing rather than hiding, because
    /// "read" on a volume nobody opened otherwise looks like a mistake.
    private var readStatusIsInherited: Bool {
        guard persisted == nil else { return false }
        return myBook?.inherited ?? false
    }

    /// Pages read pulled from the local progress JSON blob. nil when
    /// nothing's been tracked yet or the stored shape doesn't carry
    /// a pages_read key (e.g., percent-only ebook readers).
    private var currentPagesRead: Int? {
        guard let p = persisted, let data = p.progressJSON else { return nil }
        guard let parsed = try? JSONDecoder().decode(SyncJSONValue.self, from: data),
              case .object(let dict) = parsed,
              let pagesValue = dict["pages_read"],
              case .int(let pages) = pagesValue else { return nil }
        return pages
    }

    @ViewBuilder
    private func ratingLine(rating: Double) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 1) {
                ForEach(1...5, id: \.self) { i in
                    let halfValue = Double(i) - 0.5
                    let fullValue = Double(i)
                    let iconName: String = {
                        if rating >= fullValue { return "star.fill" }
                        if rating >= halfValue { return "star.leadinghalf.filled" }
                        return "star"
                    }()
                    Image(systemName: iconName)
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
            qa(icon: "book.pages.fill", label: "Progress") { showProgressSheet = true }
            qa(icon: "star.fill", label: "Rate")    { showRateSheet = true }
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

    // MARK: - Containment

    /// What this book holds, or what holds it.
    ///
    /// Worth its own section rather than a line in the series list: it is the
    /// answer to "I own the three-in-one, so do I have volume two", and it is
    /// what stops a shelf full of omnibuses reporting a run full of gaps.
    @ViewBuilder
    private func containmentList(_ links: [BookContentLink], positionKnown: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(links.enumerated()), id: \.element.id) { idx, link in
                Button { openContained(link) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: positionKnown ? "square.stack.3d.down.right" : "shippingbox")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(width: 28, height: 28)
                            .background(Theme.Colors.accentSoft, in: RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(link.title.isEmpty ? "Untitled" : link.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.Colors.appText)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            if positionKnown {
                                Text("Vol. " + link.positionLabel)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.Colors.appText3)
                            }
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.Colors.appText3)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if idx != links.count - 1 {
                    Divider().background(Theme.Colors.appLine)
                }
            }
        }
    }

    /// Want it, or stop wanting it.
    ///
    /// Refreshed from the server afterwards rather than assumed: the add route
    /// returns the entry, but the id is what the remove needs and guessing it
    /// would leave a wish nobody can take back.
    private func toggleWish() async {
        guard !isLocalLibrary else { return }
        wishBusy = true
        defer { wishBusy = false }
        let client = appState.makeClient(serverURL: library.serverURL)
        let service = WishlistService(client: client)
        if let entry = wishEntry {
            try? await service.remove(entryId: entry.id)
        } else {
            try? await service.add(bookId: currentBook.id)
        }
        await loadWish()
    }

    private func loadWish() async {
        guard !isLocalLibrary else { return }
        let client = appState.makeClient(serverURL: library.serverURL)
        let entries = (try? await WishlistService(client: client).list()) ?? []
        wishEntry = entries.first { $0.bookId == currentBook.id }
    }

    /// The other end of the link, fetched without naming a library: a volume
    /// that exists only inside an omnibus belongs to none.
    private func openContained(_ link: BookContentLink) {
        let otherID = link.otherID(from: currentBook.id)
        Task {
            let client = appState.makeClient(serverURL: library.serverURL)
            if let book = try? await BookService(client: client).get(bookId: otherID) {
                pushedBook = book
            }
        }
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
            ForEach(bookLists) { list in
                HStack {
                    // Drawn through ListIconView because the icon field holds
                    // two different things: an emoji from before the named set,
                    // or a name like "star" written by the web client. Rendering
                    // it as text drew the literal word for the second kind.
                    ListIconView(icon: list.icon, colour: list.color)
                        .frame(width: 22)
                    Text(list.name)
                        .font(Theme.Fonts.ui(14, weight: .medium))
                        .foregroundStyle(Theme.Colors.appText)
                    Spacer()
                    if list.bookCount > 0 {
                        Text("\(list.bookCount)")
                            .font(Theme.Fonts.ui(13))
                            .foregroundStyle(Theme.Colors.appText3)
                    }
                }
                .padding(14)
                if list.id != bookLists.last?.id {
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

    /// The copies, one row each.
    ///
    /// Read-only here. Editing a copy is a form with a condition, a location
    /// and a signed flag, and putting one behind every row of a detail view
    /// would crowd out the book; the web client owns that until this app has a
    /// screen for it.
    private var copiesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(copies) { copy in
                HStack(spacing: 10) {
                    Image(systemName: copy.isSigned ? "signature" : "book.closed")
                        .font(.system(size: 15))
                        .foregroundStyle(copy.isSigned ? Theme.Colors.gold : Theme.Colors.appText3)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(CopyCondition.label(copy.condition))
                            .font(Theme.Fonts.ui(14, weight: .medium))
                            .foregroundStyle(Theme.Colors.appText)
                        if !copy.locationName.isEmpty {
                            Text(copy.locationName)
                                .font(Theme.Fonts.ui(12))
                                .foregroundStyle(Theme.Colors.appText3)
                        }
                    }

                    Spacer()

                    if copy.isLent {
                        Text("Lent to \(copy.onLoanTo)")
                            .font(Theme.Fonts.ui(12, weight: .medium))
                            .foregroundStyle(Theme.Colors.gold)
                    }
                }
                .padding(14)
                if copy.id != copies.last?.id {
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
        let editionCache = EditionCache(modelContainer: modelContext.container)
        let shelfCache = ShelfCache(modelContainer: modelContext.container)

        // Offline / unreachable-server: pull straight from cache. The
        // unified LibrarySync writes these on every kept-offline pass
        // so a fresh online sync populates editions + shelves for
        // every book in the library.
        if NetworkMonitor.shared.shouldSkipAPI(for: library.serverURL) {
            editions = editionCache.editions(for: library, bookId: currentBook.id)
            shelves = shelfCache.shelves(for: library, bookId: currentBook.id)
            // Offline shows what the cache holds, which is shelves. A private
            // list has never been cached, so it is absent rather than wrong.
            bookLists = shelves.map(\.asSavedList)
            seriesRefs = []
            contents = []
            containers = []
        } else {
            let client = appState.makeClient(serverURL: library.serverURL)
            async let e  = BookService(client: client).editions(libraryId: library.id, bookId: currentBook.id)
            async let s  = BookService(client: client).shelves(libraryId: library.id, bookId: currentBook.id)
            async let contentsTask = BookContentsService(client: client).contents(bookId: currentBook.id)
            async let containersTask = BookContentsService(client: client).containers(bookId: currentBook.id)
            async let sr = BookService(client: client).seriesRefs(libraryId: library.id, bookId: currentBook.id)

            editions = (try? await e) ?? editionCache.editions(for: library, bookId: currentBook.id)
            shelves = (try? await s) ?? shelfCache.shelves(for: library, bookId: currentBook.id)
            seriesRefs = (try? await sr) ?? []
            contents = ((try? await contentsTask) ?? []).sorted { $0.position < $1.position }
            containers = (try? await containersTask) ?? []
            await loadWish()

            // Asked per server. A shelf is a list shared with a library, so the
            // shelf read only ever returned those, and every private list a
            // reader made elsewhere was invisible here. A server without lists
            // still answers with shelves, folded into the same shape.
            if await ServerCapabilities.shared.hasWorkKeyedReadingState(serverURL: library.serverURL) {
                if let fetched = try? await ListService(client: client).listsHolding(bookId: currentBook.id) {
                    bookLists = fetched
                }
                copies = (try? await CopyService(client: client).copies(bookId: currentBook.id)) ?? []
            } else {
                bookLists = shelves.map(\.asSavedList)
                // Nothing to show rather than a wrong nothing: an older server
                // has no copies to report, and an empty section would read as
                // "you own none of this".
                copies = []
            }

            // Write through to cache so the next offline visit (or the
            // next unreachable-server tap) has fresh data without
            // requiring a full LibrarySync.
            if let account = appState.accounts.first(where: { $0.url == library.serverURL }) {
                if !editions.isEmpty {
                    editionCache.upsert(editions, for: library, bookId: currentBook.id, serverAccountID: account.id)
                }
                if !shelves.isEmpty {
                    shelfCache.upsert(shelves, for: library, bookId: currentBook.id, serverAccountID: account.id)
                }
            }
        }

        // Default the picker to the primary edition (or first available).
        // The interaction we load for the hero / favourite toggle / status
        // pill is always the primary's — switching the picker only swaps
        // the stat-grid contents below, not the user-state shown above.
        let primary = editions.first(where: { $0.isPrimary }) ?? editions.first
        selectedEditionID = primary?.id

        TelemetryService.shared.send(
            "book_detail_opened",
            payload: ["media_type": currentBook.mediaType.isEmpty ? "unknown" : currentBook.mediaType]
        )

        if let pe = primary {
            // Local-first: read whatever PersistedInteraction we already
            // have so the UI populates instantly with the last-known
            // synced state. The api fetch + backfill below refreshes it.
            if let bookID = UUID(uuidString: currentBook.id) {
                persisted = fetchPersisted(bookID: bookID, editionID: UUID(uuidString: pe.id))
            }

            // Online interaction refresh — skip when there's no api
            // path; the PersistedInteraction read above already gave
            // the UI its last-known-good state.
            let fetched: UserBookInteraction?
            if NetworkMonitor.shared.shouldSkipAPI(for: library.serverURL) {
                fetched = nil
            } else {
                let client = appState.makeClient(serverURL: library.serverURL)
                let service = BookService(client: client)

                // Asked per server, not once for the app. This install may be
                // connected to several instances on different versions, and a
                // server without the work-keyed route answers 404, which would
                // read as "you have not read this book" rather than as an old
                // server.
                if await ServerCapabilities.shared.hasWorkKeyedReadingState(serverURL: library.serverURL) {
                    myBook = try? await service.myBook(bookId: currentBook.id)
                    // The per-edition shape is what the rest of this view and
                    // the local store still speak, so the work-keyed answer is
                    // folded into it rather than duplicating every read path.
                    fetched = myBook.map { $0.asInteraction(editionID: pe.id) }
                } else {
                    myBook = nil
                    fetched = try? await service
                        .interaction(libraryId: library.id, bookId: currentBook.id, editionId: pe.id)
                }
            }
            interaction = fetched

            // Backfill into SwiftData. The helper guards against
            // clobbering newer per-field timestamps (e.g., an outbox
            // edit queued locally), so a stale api read can't undo a
            // pending local change.
            if let dto = fetched,
               let account = appState.accounts.first(where: { $0.url == library.serverURL }) {
                SyncBackfill.writeInteraction(
                    dto, serverAccountID: account.id,
                    bookID: UUID(uuidString: currentBook.id), in: modelContext)
                try? modelContext.save()

                // If persisted was nil before (first interaction with
                // this edition), backfill just created the row; pick
                // it up now so the @State holds the canonical reference.
                if persisted == nil, let bookID = UUID(uuidString: currentBook.id) {
                    persisted = fetchPersisted(bookID: bookID, editionID: UUID(uuidString: pe.id))
                }
            }
        }

        await loadActiveLoan()
    }

    /// Delete this book. Routes through the api for remote libraries
    /// and straight to SwiftData for Lite libraries — purges the book
    /// row, its editions, and its shelf membership in one pass.
    private func deleteBook() async {
        if library.serverURL.hasPrefix("local://") {
            let context = ModelContext(modelContext.container)
            let serverURL = library.serverURL
            let libraryId = library.id
            let bookId = currentBook.id

            let books = try? context.fetch(FetchDescriptor<PersistedBook>(
                predicate: #Predicate {
                    $0.serverURL == serverURL && $0.libraryId == libraryId && $0.bookId == bookId
                }
            ))
            books?.forEach { context.delete($0) }

            let editionRows = try? context.fetch(FetchDescriptor<PersistedBookEditions>(
                predicate: #Predicate {
                    $0.serverURL == serverURL && $0.libraryId == libraryId && $0.bookId == bookId
                }
            ))
            editionRows?.forEach { context.delete($0) }

            let shelfRows = try? context.fetch(FetchDescriptor<PersistedBookShelves>(
                predicate: #Predicate {
                    $0.serverURL == serverURL && $0.libraryId == libraryId && $0.bookId == bookId
                }
            ))
            shelfRows?.forEach { context.delete($0) }

            // The interaction row is keyed on the edition, not the book,
            // so it survives the deletes above and would sit orphaned
            // forever. `editions` is already loaded on this view, and
            // PersistedBookEditions stores one payload blob rather than
            // per-edition rows, so this is the cheapest source of ids.
            //
            // Matched on the book as well as the editions: reading state is
            // keyed to the work now, so a row rekeyed by a read would survive
            // an edition-only sweep and sit orphaned forever, which is the
            // exact bug this block exists to prevent.
            let editionIDs = Set(editions.compactMap { UUID(uuidString: $0.id) })
            let bookUUID = UUID(uuidString: book.id)
            if !editionIDs.isEmpty || bookUUID != nil {
                let interactions = try? context.fetch(FetchDescriptor<PersistedInteraction>(
                    predicate: #Predicate<PersistedInteraction> {
                        editionIDs.contains($0.bookEditionID) || $0.bookID == bookUUID
                    }
                ))
                interactions?.forEach { context.delete($0) }
            }
            try? context.save()

            // Nothing else re-reads SwiftData on its own: popping back
            // does not re-fire the books grid's .task, so without this
            // the deleted book stays on the grid, the home dashboard,
            // and the libraries card count until the app restarts.
            NotificationCenter.default.post(
                name: .liteLibraryDidChange,
                object: nil,
                userInfo: ["libraryID": library.id]
            )
        } else {
            let client = appState.makeClient(serverURL: library.serverURL)
            try? await BookService(client: client).delete(libraryId: library.id, bookId: currentBook.id)
        }
        dismiss()
    }

    private func loadActiveLoan() async {
        // Loans are transient state we don't cache. When offline / unreachable,
        // skip the call and leave `activeLoan` nil — the detail view's "Lent"
        // badge just won't show, which matches the "no fresh data" expectation.
        guard !NetworkMonitor.shared.shouldSkipAPI(for: library.serverURL) else {
            activeLoan = nil
            return
        }
        let client = appState.makeClient(serverURL: library.serverURL)
        let loans = (try? await LoanService(client: client).list(libraryId: library.id)) ?? []
        activeLoan = loans.first(where: { $0.bookId == currentBook.id && $0.isActive })
    }
}
