import SwiftUI

enum BookSortOption: String, CaseIterable, Identifiable {
    case titleAsc, titleDesc, recentlyAdded, oldestFirst, newestRelease, oldestRelease

    var id: String { rawValue }
    var label: String {
        switch self {
        case .titleAsc:       return "Title (A–Z)"
        case .titleDesc:      return "Title (Z–A)"
        case .recentlyAdded:  return "Recently added"
        case .oldestFirst:    return "Oldest added"
        case .newestRelease:  return "Newest release"
        case .oldestRelease:  return "Oldest release"
        }
    }
    var field: String {
        switch self {
        case .titleAsc, .titleDesc:              return "title"
        case .recentlyAdded, .oldestFirst:       return "created_at"
        case .newestRelease, .oldestRelease:     return "publish_date"
        }
    }
    var dir: String {
        switch self {
        case .titleAsc, .oldestFirst, .oldestRelease:      return "asc"
        case .titleDesc, .recentlyAdded, .newestRelease:   return "desc"
        }
    }
}

@Observable
final class BooksViewModel {
    var books: [Book] = []
    var total = 0
    var page = 1
    let perPage = 25
    var isLoading = false
    var isLoadingMore = false
    var error: String?

    var searchText = ""
    var selectedTag: Tag?
    var selectedMediaType: MediaType?
    var selectedLetter: String?
    var sortOption: BookSortOption = .titleAsc
    var availableTags: [Tag] = []
    var availableMediaTypes: [MediaType] = []
    var availableLetters: Set<String> = []

    var hasMore: Bool { books.count < total }
    var hasActiveFilters: Bool {
        !searchText.isEmpty || selectedTag != nil || selectedMediaType != nil || selectedLetter != nil
    }

    func load(client: APIClient, libraryId: String) async {
        isLoading = true; error = nil; page = 1
        let t0 = Date()
        print("📚 [BooksVM] load() start offline=false lib=\(libraryId)")

        let metadataTask = Task { await self.loadMetadata(client: client, libraryId: libraryId) }

        do {
            let paged = try await BookService(client: client).list(
                libraryId: libraryId, query: searchText, page: 1, perPage: perPage,
                tag: selectedTag?.name ?? "", typeFilter: selectedMediaType?.name ?? "",
                letter: selectedLetter ?? "",
                sort: sortOption.field, sortDir: sortOption.dir)
            books = paged.items; total = paged.total
            isLoading = false
            print("📚 [BooksVM] books visible after \(Int(Date().timeIntervalSince(t0)*1000))ms count=\(paged.items.count)/\(paged.total)")
            await metadataTask.value
            print("📚 [BooksVM] load() done after \(Int(Date().timeIntervalSince(t0)*1000))ms")
        } catch {
            if !Self.isCancellation(error) { self.error = error.localizedDescription }
            isLoading = false
            print("📚 [BooksVM] load() failed after \(Int(Date().timeIntervalSince(t0)*1000))ms err=\(error)")
        }
    }

    func loadMetadata(client: APIClient, libraryId: String) async {
        let letters = Task { () -> [String]? in try? await BookService(client: client).letters(libraryId: libraryId) }
        let tags    = Task { () -> [Tag]?    in try? await TagService(client: client).list(libraryId: libraryId) }
        let types   = Task { () -> Result<[MediaType], Error> in
            do { return .success(try await MediaTypeService(client: client).list()) }
            catch { return .failure(error) }
        }

        if let result = await letters.value, availableLetters.isEmpty { availableLetters = Set(result) }
        if let result = await tags.value, availableTags.isEmpty { availableTags = result }
        switch await types.value {
        case .success(let result):
            print("📚 [BooksVM] media-types decoded ok count=\(result.count) first=\(result.first?.displayName ?? "nil")")
            if availableMediaTypes.isEmpty { availableMediaTypes = result }
        case .failure(let err):
            print("🔴 [BooksVM] media-types decode failed: \(err)")
        }
    }

    func loadMore(client: APIClient, libraryId: String) async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        page += 1
        do {
            let paged = try await BookService(client: client).list(
                libraryId: libraryId, query: searchText, page: page, perPage: perPage,
                tag: selectedTag?.name ?? "", typeFilter: selectedMediaType?.name ?? "",
                letter: selectedLetter ?? "",
                sort: sortOption.field, sortDir: sortOption.dir)
            books.append(contentsOf: paged.items); total = paged.total
        } catch {
            page -= 1
            if !Self.isCancellation(error) { self.error = error.localizedDescription }
        }
    }

    func search(client: APIClient, libraryId: String) async {
        page = 1; isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let paged = try await BookService(client: client).list(
                libraryId: libraryId, query: searchText, page: 1, perPage: perPage,
                tag: selectedTag?.name ?? "", typeFilter: selectedMediaType?.name ?? "",
                letter: selectedLetter ?? "",
                sort: sortOption.field, sortDir: sortOption.dir)
            books = paged.items; total = paged.total
        } catch {
            if !Self.isCancellation(error) { self.error = error.localizedDescription }
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let underlying: Error
        if case let APIError.networkError(inner) = error { underlying = inner } else { underlying = error }
        if underlying is CancellationError { return true }
        let ns = underlying as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }
        return false
    }

    func loadFromCache(offlineKey: String) {
        if let cached = LibraryOfflineStore.shared.cachedBooks(for: offlineKey) {
            books = cached; total = cached.count
        }
    }
}

struct BooksView: View {
    let library: Library
    @Environment(AppState.self) private var appState
    @Environment(\.libraryBack) private var onBack
    @State private var vm = BooksViewModel()
    @State private var showAdd = false
    @State private var showBulkEdit = false
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var searchTask: Task<Void, Never>?
    @State private var letterTask: Task<Void, Never>?
    @State private var pendingLetter: String?
    @State private var dragLetter: String?
    @ScaledMetric(relativeTo: .largeTitle) private var dragOverlayFullSize: CGFloat = 64
    @ScaledMetric(relativeTo: .largeTitle) private var dragOverlayHashSize: CGFloat = 44

    private static let indexLetters: [String] =
        ["#"] + (65...90).map { String(UnicodeScalar($0)!) }

    var body: some View {
        content
        .navigationTitle(isSelecting ? "\(selectedIDs.count) Selected" : library.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $vm.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search books")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showAdd) {
            AddEditBookSheet(library: library) { _ in
                Task { await vm.load(client: appState.makeClient(), libraryId: library.id) }
            }
        }
        .sheet(isPresented: $showBulkEdit) {
            let selected = vm.books.filter { selectedIDs.contains($0.id) }
            BulkEditBooksSheet(
                library: library,
                books: selected,
                availableTags: vm.availableTags,
                availableMediaTypes: vm.availableMediaTypes
            ) {
                isSelecting = false
                selectedIDs = []
                Task { await vm.load(client: appState.makeClient(), libraryId: library.id) }
            }
        }
        .task {
            guard vm.books.isEmpty else { return }
            if appState.isOffline {
                vm.loadFromCache(offlineKey: library.clientKey)
            } else {
                await vm.load(client: appState.makeClient(), libraryId: library.id)
            }
        }
        .refreshable { if !appState.isOffline { await vm.load(client: appState.makeClient(), libraryId: library.id) } }
        .onChange(of: vm.searchText) { _, newValue in
            guard !appState.isOffline else { return }
            if !newValue.isEmpty && (pendingLetter != nil || vm.selectedLetter != nil) {
                letterTask?.cancel()
                pendingLetter = nil
                vm.selectedLetter = nil
            }
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await vm.search(client: appState.makeClient(), libraryId: library.id)
            }
        }
        .onChange(of: vm.selectedTag) { _, _ in
            guard !appState.isOffline else { return }
            Task { await vm.search(client: appState.makeClient(), libraryId: library.id) }
        }
        .onChange(of: vm.selectedMediaType) { _, _ in
            guard !appState.isOffline else { return }
            Task { await vm.search(client: appState.makeClient(), libraryId: library.id) }
        }
        .onChange(of: vm.sortOption) { _, _ in
            guard !appState.isOffline else { return }
            Task { await vm.search(client: appState.makeClient(), libraryId: library.id) }
        }
        .onChange(of: pendingLetter) { _, newValue in
            guard !appState.isOffline else { return }
            letterTask?.cancel()
            letterTask = Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                vm.selectedLetter = newValue
                await vm.search(client: appState.makeClient(), libraryId: library.id)
            }
        }
        .alert("Error", isPresented: Binding(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") { vm.error = nil }
        } message: { Text(vm.error ?? "") }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            mediaTypeScopeBar

            if hasPillFilters {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let tag = vm.selectedTag {
                            FilterChip(label: tag.name, color: tag.color) { vm.selectedTag = nil }
                        }
                        if let letter = vm.selectedLetter {
                            FilterChip(label: "Letter: \(letter)", color: "#6B7280") { pendingLetter = nil }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }
            }

            Divider()

            if vm.isLoading && vm.books.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.books.isEmpty {
                if appState.isOffline {
                    EmptyState(icon: "wifi.slash", title: "Offline",
                               subtitle: "This library isn't cached. Enable \"Keep offline\" in library settings to cache books.")
                } else {
                    EmptyState(icon: "book", title: "No books found",
                               subtitle: vm.hasActiveFilters ? "Try a different search." : "Add your first book to get started.",
                               action: vm.hasActiveFilters ? nil : { showAdd = true },
                               actionLabel: "Add Book")
                }
            } else {
                bookList
                    .overlay(alignment: .trailing) {
                        if shouldShowIndex {
                            AlphabetIndexBar(
                                letters: Self.indexLetters,
                                availableLetters: vm.availableLetters,
                                selected: pendingLetter ?? vm.selectedLetter,
                                dragLetter: $dragLetter
                            ) { letter in
                                pendingLetter = letter
                            }
                            .padding(.trailing, 4)
                            .padding(.vertical, 8)
                        }
                    }
                    .overlay {
                        if let letter = dragLetter {
                            Text(letter == "#" ? "All" : letter)
                                .font(.system(size: letter == "#" ? dragOverlayHashSize : dragOverlayFullSize, weight: .bold))
                                .foregroundStyle(.primary)
                                .frame(minWidth: 120, minHeight: 120)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                                .transition(.opacity.combined(with: .scale(scale: 0.85)))
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .animation(.easeOut(duration: 0.12), value: dragLetter)
            }
        }
    }

    private var mediaTypeScopeBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ScopeChip(label: "All", isSelected: vm.selectedMediaType == nil) {
                        vm.selectedMediaType = nil
                    }
                    ForEach(vm.availableMediaTypes) { type in
                        ScopeChip(label: type.displayName, isSelected: vm.selectedMediaType?.id == type.id) {
                            vm.selectedMediaType = type
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            Divider().frame(height: 20)
            sortMenu
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity)
        }
        .frame(height: 44)
    }

    private var bookList: some View {
        List {
            ForEach(vm.books) { book in
                if isSelecting {
                    Button {
                        if selectedIDs.contains(book.id) { selectedIDs.remove(book.id) }
                        else { selectedIDs.insert(book.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selectedIDs.contains(book.id)
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedIDs.contains(book.id)
                                                 ? Color.accentColor : Color.secondary.opacity(0.5))
                                .font(.title3)
                                .frame(width: 26)
                            BookRow(book: book, serverURL: library.serverURL)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    NavigationLink(destination: BookDetailView(library: library, book: book)) {
                        BookRow(book: book, serverURL: library.serverURL)
                    }
                }
            }
            if vm.hasMore && !isSelecting {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowSeparator(.hidden)
                    .task { await vm.loadMore(client: appState.makeClient(), libraryId: library.id) }
            }
        }
        .listStyle(.plain)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSelecting && !selectedIDs.isEmpty {
                BulkSelectionBar(count: selectedIDs.count) {
                    showBulkEdit = true
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    isSelecting = false
                    selectedIDs = []
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                let allSelected = selectedIDs.count == vm.books.count && !vm.books.isEmpty
                Button(allSelected ? "Deselect All" : "Select All") {
                    selectedIDs = allSelected ? [] : Set(vm.books.map(\.id))
                }
            }
        } else {
            ToolbarItem(placement: .topBarLeading) {
                LibraryBackButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 2) {
                    tagFilterMenu
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add book")
                }
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(BookSortOption.allCases) { opt in
                Button {
                    vm.sortOption = opt
                } label: {
                    if vm.sortOption == opt {
                        Label(opt.label, systemImage: "checkmark")
                    } else {
                        Text(opt.label)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort books")
        .accessibilityValue(vm.sortOption.label)
    }

    private var tagFilterMenu: some View {
        Menu {
            Button {
                vm.selectedTag = nil
            } label: {
                if vm.selectedTag == nil {
                    Label("All tags", systemImage: "checkmark")
                } else {
                    Text("All tags")
                }
            }
            if !vm.availableTags.isEmpty { Divider() }
            ForEach(vm.availableTags) { tag in
                Button {
                    vm.selectedTag = tag
                } label: {
                    if vm.selectedTag?.id == tag.id {
                        Label(tag.name, systemImage: "checkmark")
                    } else {
                        Text(tag.name)
                    }
                }
            }
        } label: {
            Image(systemName: vm.selectedTag != nil
                  ? "tag.fill"
                  : "tag")
                .foregroundStyle(vm.selectedTag != nil ? Color.accentColor : Color.primary)
        }
        .accessibilityLabel("Filter by tag")
        .accessibilityValue(vm.selectedTag?.name ?? "All tags")
    }

    // MARK: - Helpers

    private var hasPillFilters: Bool {
        vm.selectedTag != nil || vm.selectedLetter != nil
    }

    private var shouldShowIndex: Bool {
        !isSelecting && !vm.books.isEmpty && !vm.availableLetters.isEmpty
    }
}

private struct ScopeChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.15),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

private struct BulkSelectionBar: View {
    let count: Int
    let onEdit: () -> Void

    var body: some View {
        HStack {
            Text("\(count) book\(count == 1 ? "" : "s") selected")
                .font(.subheadline.weight(.medium))
            Spacer()
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

private struct FilterChip: View {
    let label: String
    let color: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.caption.weight(.medium))
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .accessibilityLabel("Remove filter \(label)")
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Color(hex: color).opacity(0.15))
        .foregroundStyle(Color(hex: color))
        .clipShape(Capsule())
    }
}

struct BookRow: View {
    let book: Book
    let serverURL: String

    private var coverURL: URL? {
        guard let path = book.coverUrl, !path.isEmpty, !serverURL.isEmpty else { return nil }
        return URL(string: serverURL + path)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            BookCoverImage(url: coverURL, width: 44, height: 64)
                .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title).font(.headline).lineLimit(2)
                if !book.subtitle.isEmpty {
                    Text(book.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let primaryContributor = book.contributors.sorted(by: { $0.displayOrder < $1.displayOrder }).first {
                        Text(primaryContributor.name)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !book.mediaType.isEmpty {
                        Text("·").font(.caption).foregroundStyle(.tertiary)
                        Text(book.mediaType).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !book.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(book.tags) { tag in TagPill(tag: tag) }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
