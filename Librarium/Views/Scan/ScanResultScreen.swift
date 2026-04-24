import SwiftUI

/// Full-screen control centre for a scanned (or manually-entered) ISBN.
///
/// Top half: book metadata (cover, title, authors, description) from the
/// primary server's merged ISBN lookup. Bottom half: one row per library
/// across every connected server, each showing either an Add button (unowned)
/// or a Status · Rating pill (owned) that pushes the interaction editor.
struct ScanResultScreen: View {
    let isbn: String
    let libraries: [Library]
    let onClose: () -> Void

    @Environment(AppState.self) private var appState

    @State private var lookup: ISBNLookupResult?
    @State private var lookupLoading = true
    @State private var lookupError: String?

    /// Ownership state keyed by library.clientKey. nil means "still loading";
    /// .none means "confirmed not in this library"; .owned carries the hydrated
    /// ids we need for the interaction editor.
    @State private var ownership: [String: OwnershipState] = [:]
    @State private var pushTarget: PushTarget?

    /// Media types keyed by server URL — we can't POST a book without one,
    /// and they're server-specific (manga/novel/comic on one server may have
    /// different UUIDs on another). Fetched lazily per server on first need.
    @State private var mediaTypes: [String: [MediaType]] = [:]

    /// The library the user just tapped "Add" on — drives the Add-to-library
    /// sheet presentation. Sheet dismisses itself on save or cancel.
    @State private var addSheetTarget: Library?

    /// Guards `.task` from re-running the lookup + per-library ownership when
    /// the user returns from the pushed interaction detail. State is already
    /// hydrated; a re-fetch would just thrash the network and flash loading UI.
    @State private var didInitialLoad = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    librariesSection
                    detailsLink
                }
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .navigationTitle("Scanned book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                }
            }
            .sheet(item: $addSheetTarget) { library in
                AddToLibrarySheet(
                    library: library,
                    mediaTypes: mediaTypes[library.serverURL] ?? [],
                    initialMediaTypeID: defaultMediaTypeID(for: library),
                    initialFormat: "paperback",
                    onAdd: { mediaTypeID, format in
                        Task {
                            await addToLibrary(library,
                                               mediaTypeID: mediaTypeID,
                                               format: format)
                        }
                    }
                )
            }
            .navigationDestination(item: $pushTarget) { target in
                InteractionDetailView(
                    account: target.account,
                    library: target.library,
                    bookID: target.bookID,
                    editions: target.editions,
                    initialEditionIndex: target.initialIndex,
                    onSaved: { editionID, saved in
                        updatePillAfterSave(clientKey: target.library.clientKey,
                                            editionID: editionID,
                                            saved: saved)
                    }
                )
            }
            .task {
                guard !didInitialLoad else { return }
                didInitialLoad = true
                await loadAll()
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if lookupLoading {
            HStack { ProgressView(); Text("Looking up \(isbn)…").foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 40)
        } else if let r = lookup {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    cover(url: r.coverUrl)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(r.title).font(.title3.weight(.semibold))
                        if !r.subtitle.isEmpty {
                            Text(r.subtitle).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if !r.authors.isEmpty {
                            Text(bylineText(r))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        let displayISBN = r.isbn13.isEmpty ? r.isbn10 : r.isbn13
                        if !displayISBN.isEmpty {
                            Text("ISBN \(displayISBN)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if !r.description.isEmpty {
                    Text(r.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
        } else if let msg = lookupError {
            VStack(spacing: 8) {
                Text("ISBN not found").font(.headline)
                Text(msg).font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private func cover(url: String) -> some View {
        Group {
            if let u = URL(string: url), !url.isEmpty {
                AsyncImage(url: u) { phase in
                    if let img = phase.image {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 6).fill(Color(.quaternarySystemFill))
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Color(.quaternarySystemFill))
            }
        }
        .frame(width: 76, height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(radius: 3, y: 2)
    }

    private func bylineText(_ r: ISBNLookupResult) -> String {
        var parts: [String] = [r.authors.joined(separator: ", ")]
        if !r.publisher.isEmpty { parts.append(r.publisher) }
        if let year = yearFrom(r.publishDate) { parts.append(year) }
        return parts.joined(separator: " · ")
    }

    private func yearFrom(_ s: String) -> String? {
        guard s.count >= 4 else { return nil }
        return String(s.prefix(4))
    }

    // MARK: - Libraries

    @ViewBuilder
    private var librariesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LIBRARIES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                ForEach(sortedLibraries) { library in
                    LibraryScanRow(
                        library: library,
                        showServerName: appState.accounts.count > 1,
                        state: ownership[library.clientKey] ?? .loading,
                        onAdd: { addSheetTarget = library },
                        onTap: {
                            if case .owned(let info) = (ownership[library.clientKey] ?? .loading) {
                                guard let account = accountFor(library) else { return }
                                pushTarget = PushTarget(
                                    account: account,
                                    library: library,
                                    bookID: info.bookID,
                                    editions: info.editions,
                                    initialIndex: info.matchedIndex
                                )
                            }
                        }
                    )
                    if library.id != sortedLibraries.last?.id {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
    }

    /// Primary-server libraries first, then alphabetical within each server.
    private var sortedLibraries: [Library] {
        let primaryURL = appState.primaryAccount?.url
        return libraries.sorted { a, b in
            let aPrimary = a.serverURL == primaryURL
            let bPrimary = b.serverURL == primaryURL
            if aPrimary != bPrimary { return aPrimary }
            if a.serverURL != b.serverURL { return a.serverURL < b.serverURL }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    @ViewBuilder
    private var detailsLink: some View {
        // Future: push BookDetailView for whichever library the user picks.
        // Out of scope for this pass.
        EmptyView()
    }

    // MARK: - Load

    private func loadAll() async {
        async let lookupTask: Void = loadLookup()
        async let ownershipTask: Void = loadOwnership()
        async let mediaTypesTask: Void = loadMediaTypes()
        _ = await (lookupTask, ownershipTask, mediaTypesTask)
    }

    private func loadMediaTypes() async {
        let uniqueServers = Set(libraries.map(\.serverURL))
        await withTaskGroup(of: (String, [MediaType]).self) { group in
            for serverURL in uniqueServers {
                let client = appState.makeClient(serverURL: serverURL)
                group.addTask {
                    let types = (try? await MediaTypeService(client: client).list()) ?? []
                    return (serverURL, types)
                }
            }
            for await (url, types) in group {
                mediaTypes[url] = types
            }
        }
    }

    private func loadLookup() async {
        lookupLoading = true; defer { lookupLoading = false }
        let client = appState.makePrimaryClient()
        do {
            let results = try await LookupService(client: client).isbn(isbn)
            lookup = results.first
            if lookup == nil { lookupError = "No results for \(isbn)." }
        } catch {
            lookupError = error.localizedDescription
        }
    }

    private func loadOwnership() async {
        for lib in libraries { ownership[lib.clientKey] = .loading }
        // Build clients on the main actor so they pick up the token-refresh
        // handler from AppState — bare APIClient(baseURL:token:) instances
        // miss onUnauthorized, making expired tokens silently 401 and get
        // caught as "not owned". Sequential instead of task-group because
        // the 1–5 library common case doesn't need the parallelism and
        // APIClient isn't Sendable.
        for library in libraries {
            let key = library.clientKey
            let client = appState.makeClient(serverURL: library.serverURL)
            let state = await resolveOwnership(client: client, library: library, isbn: isbn)
            ownership[key] = state
        }
    }

    private func resolveOwnership(client: APIClient,
                                  library: Library,
                                  isbn: String) async -> OwnershipState {
        let bookSvc = BookService(client: client)
        let book: Book
        do {
            book = try await bookSvc.byISBN(libraryId: library.id, isbn: isbn)
        } catch APIError.notFound {
            // Try the ISBN-13 ↔ ISBN-10 alternate form. Books imported before
            // barcode scanning was common often only carry one of the two,
            // and the server's book-by-isbn matches on exact equality.
            if let alt = alternateISBN(isbn),
               let b = try? await bookSvc.byISBN(libraryId: library.id, isbn: alt) {
                book = b
            } else {
                return .unowned
            }
        } catch {
            #if DEBUG
            print("⚠️ resolveOwnership: byISBN failed for \(library.name) @ \(library.serverURL): \(error)")
            #endif
            return .unowned
        }
        do {
            let editions = try await bookSvc.editions(libraryId: library.id, bookId: book.id)
            let matched = editions.firstIndex { e in
                e.isbn13 == isbn || e.isbn10 == isbn
            } ?? editions.firstIndex { $0.isPrimary } ?? 0
            return .owned(.init(bookID: book.id, editions: editions, matchedIndex: matched))
        } catch {
            #if DEBUG
            print("⚠️ resolveOwnership: editions fetch failed for \(library.name): \(error)")
            #endif
            return .owned(.init(bookID: book.id, editions: [], matchedIndex: 0))
        }
    }

    /// ISBN-13 ↔ ISBN-10 cross-form, for books whose library row was stored
    /// with only one of the two.
    ///
    /// - ISBN-13 starting with `978` → strip prefix, recompute check digit.
    /// - ISBN-10 → prepend `978`, recompute check digit.
    /// - Anything else (including `979…` prefix, which has no ISBN-10 form) → nil.
    private func alternateISBN(_ isbn: String) -> String? {
        let digits = isbn.filter { $0.isNumber || $0 == "X" || $0 == "x" }.uppercased()
        switch digits.count {
        case 13:
            guard digits.hasPrefix("978") else { return nil }
            let body9 = String(digits.dropFirst(3).prefix(9))
            return body9 + isbn10CheckDigit(body9)
        case 10:
            let body12 = "978" + String(digits.prefix(9))
            return body12 + isbn13CheckDigit(body12)
        default:
            return nil
        }
    }

    private func isbn10CheckDigit(_ body9: String) -> String {
        var sum = 0
        for (i, ch) in body9.enumerated() {
            sum += (Int(String(ch)) ?? 0) * (10 - i)
        }
        let check = (11 - (sum % 11)) % 11
        return check == 10 ? "X" : String(check)
    }

    private func isbn13CheckDigit(_ body12: String) -> String {
        var sum = 0
        for (i, ch) in body12.enumerated() {
            let d = Int(String(ch)) ?? 0
            sum += i.isMultiple(of: 2) ? d : d * 3
        }
        let check = (10 - (sum % 10)) % 10
        return String(check)
    }

    // MARK: - Add

    private func addToLibrary(_ library: Library, mediaTypeID: String, format: String) async {
        ownership[library.clientKey] = .adding
        guard let r = lookup else {
            ownership[library.clientKey] = .unowned
            return
        }
        let client = appState.makeClient(serverURL: library.serverURL)
        let body = CreateBookRequest(
            title: r.title,
            subtitle: r.subtitle,
            mediaTypeId: mediaTypeID,
            description: r.description,
            contributors: [],
            tagIds: [],
            genreIds: [],
            edition: CreateEditionRequest(
                format: format,
                language: r.language,
                editionName: "",
                narrator: "",
                publisher: r.publisher,
                publishDate: r.publishDate.isEmpty ? nil : r.publishDate,
                isbn10: r.isbn10,
                isbn13: r.isbn13,
                description: r.description,
                pageCount: r.pageCount,
                copyCount: nil,
                isPrimary: true
            )
        )
        do {
            _ = try await BookService(client: client).create(libraryId: library.id, body: body)
            // Re-resolve ownership so we pick up the new bookID + editionID.
            let state = await resolveOwnership(client: client, library: library, isbn: isbn)
            ownership[library.clientKey] = state

            // Kick off a metadata + cover enrichment so the freshly-added book
            // gets proper data filled in asynchronously. Fire-and-forget — we
            // don't want to block the UI on the enrichment job starting, and
            // a failure here shouldn't un-add the book.
            if case .owned(let info) = state {
                Task {
                    do {
                        try await BookService(client: client).enrich(bookId: info.bookID)
                    } catch {
                        #if DEBUG
                        print("⚠️ post-add enrich for \(info.bookID) failed: \(error)")
                        #endif
                    }
                }
            }
        } catch {
            #if DEBUG
            print("⚠️ addToLibrary(\(library.name) @ \(library.serverURL)) failed: \(error)")
            #endif
            ownership[library.clientKey] = .addError(error.localizedDescription)
        }
    }

    // MARK: - Save rollup

    private func updatePillAfterSave(clientKey: String, editionID: String, saved: UserBookInteraction) {
        // Pill rendering on the row doesn't yet reflect saved status/rating
        // (MVP — the row just shows "Unread" until refresh). Future pass can
        // cache interaction snapshots here so the pill updates in place.
        _ = (editionID, saved, clientKey)
    }

    // MARK: - Helpers

    private func accountFor(_ library: Library) -> ServerAccount? {
        appState.accounts.first(where: { $0.url == library.serverURL })
    }

    /// Guess a reasonable default media type for the Add sheet based on the
    /// ISBN lookup result. Mangadex results default to a type named "manga"
    /// (if the server has one); otherwise we fall back to "novel" and then
    /// to the first available type.
    private func defaultMediaTypeID(for library: Library) -> String? {
        let types = mediaTypes[library.serverURL] ?? []
        guard !types.isEmpty else { return nil }

        let provider = (lookup?.provider ?? "").lowercased()
        let categories = (lookup?.categories ?? []).map { $0.lowercased() }

        let prefersManga = provider.contains("manga")
            || categories.contains(where: { $0.contains("manga") })
        let prefersComic = categories.contains(where: { $0.contains("comic") || $0.contains("graphic novel") })

        func find(_ names: [String]) -> MediaType? {
            for n in names {
                if let t = types.first(where: { $0.name.lowercased() == n }) { return t }
            }
            return nil
        }

        if prefersManga, let t = find(["manga"]) { return t.id }
        if prefersComic, let t = find(["comic"]) { return t.id }
        if let t = find(["novel", "book"]) { return t.id }
        return types.first?.id
    }
}

// MARK: - Row

private struct LibraryScanRow: View {
    let library: Library
    let showServerName: Bool
    let state: OwnershipState
    let onAdd: () -> Void
    let onTap: () -> Void

    var body: some View {
        // Owned rows: the whole row (including trailing chevron) is the push
        // target — one Button covers the entire HStack. Unowned rows leave
        // the Add button independent so it isn't buried under a parent tap.
        if case .owned = state {
            Button(action: onTap) { rowContent }
                .buttonStyle(.plain)
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            labelStack
            Spacer()
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var labelStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(library.name).font(.body).foregroundStyle(.primary)
            if showServerName, !library.serverName.isEmpty {
                Text(library.serverName)
                    .font(.caption).foregroundStyle(.tertiary)
            }
            pill
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var pill: some View {
        switch state {
        case .owned(let info):
            HStack(spacing: 6) {
                Text(statusLabel(info.firstInteractionStatus)).foregroundStyle(statusColor(info.firstInteractionStatus))
                if let r = info.firstInteractionRating {
                    Text("·").foregroundStyle(.tertiary)
                    Text(ratingGlyphs(r)).foregroundStyle(.yellow)
                }
            }
            .font(.footnote.weight(.medium))
            .padding(.top, 2)
        case .loading:
            Text("Checking…").font(.caption).foregroundStyle(.tertiary).padding(.top, 2)
        case .adding:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.6)
                Text("Adding…").font(.caption).foregroundStyle(.tertiary)
            }.padding(.top, 2)
        case .addError:
            // Keep the row quiet on failure — the trailing side surfaces a
            // "Retry" affordance and the full error is only a long-press away.
            // Stacking a raw JSON blob inline ate whole rows before.
            Text("Couldn't add to this library.")
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.top, 2)
        case .unowned:
            EmptyView()
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .unowned, .addError:
            Button("Add", action: onAdd)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        case .owned:
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        case .adding:
            ProgressView().scaleEffect(0.7)
        case .loading:
            EmptyView()
        }
    }

    private func statusLabel(_ s: String) -> String {
        switch s {
        case "reading":        return "Reading"
        case "read":           return "Read"
        case "did_not_finish": return "Did not finish"
        default:               return "Unread"
        }
    }
    private func statusColor(_ s: String) -> Color {
        switch s {
        case "reading":        return .accentColor
        case "read":           return .green
        case "did_not_finish": return .red
        default:               return .secondary
        }
    }
    private func ratingGlyphs(_ rating: Int) -> String {
        // Integer 1-10 → up to 5 ★ with a half-step using ★½.
        let full = rating / 2
        let half = rating % 2 == 1
        return String(repeating: "★", count: full) + (half ? "½" : "")
    }
}

// MARK: - State

private enum OwnershipState {
    case loading
    case unowned
    case owned(OwnershipInfo)
    case adding
    case addError(String)
}

private struct OwnershipInfo {
    let bookID: String
    let editions: [BookEdition]
    let matchedIndex: Int

    /// Placeholder until the pill is wired to fetched interactions. For the
    /// MVP we don't pre-fetch interactions on the result screen — the detail
    /// page fetches lazily when pushed. The pill shows "Unread" for freshly-
    /// resolved rows, updating once the user saves changes.
    var firstInteractionStatus: String { "unread" }
    var firstInteractionRating: Int? { nil }
}

// MARK: - Push target

private struct PushTarget: Hashable, Identifiable {
    let account: ServerAccount
    let library: Library
    let bookID: String
    let editions: [BookEdition]
    let initialIndex: Int

    // Identity is "which library row did the user tap" — the library's
    // clientKey is unique across servers. Hashable/Equatable collapse to
    // that same key so `navigationDestination(item:)` doesn't complain
    // about non-hashable payload fields (e.g. ServerAccount).
    var id: String { library.clientKey }

    static func == (lhs: PushTarget, rhs: PushTarget) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
