import SwiftUI

struct BookDetailView: View {
    let library: Library
    let book: Book
    @Environment(AppState.self) private var appState
    @State private var editions: [BookEdition] = []
    @State private var shelves: [Shelf] = []
    @State private var seriesRefs: [BookSeriesRef] = []
    @State private var isLoading = true
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var showClearCoverConfirm = false
    @State private var showScanner = false
    @State private var isUploadingCover = false
    @State private var coverCacheBuster: Int = 0
    @State private var uploadError: String?
    @State private var currentBook: Book
    @Environment(\.dismiss) private var dismiss

    init(library: Library, book: Book) {
        self.library = library
        self.book = book
        self._currentBook = State(initialValue: book)
    }

    private var coverURL: URL? {
        guard let path = currentBook.coverUrl, !path.isEmpty else { return nil }
        let base = library.serverURL + path
        // Append a cache-buster after a successful upload so BookCoverImage reloads.
        return URL(string: coverCacheBuster == 0 ? base : "\(base)?v=\(coverCacheBuster)")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Hero
                HStack(alignment: .top, spacing: 16) {
                    BookCoverImage(url: coverURL, width: 90, height: 135)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(currentBook.title).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                        if !currentBook.subtitle.isEmpty {
                            Text(currentBook.subtitle).font(.title3).foregroundStyle(.secondary)
                        }
                        if !currentBook.contributors.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(Array(currentBook.contributors.sorted { $0.displayOrder < $1.displayOrder }.enumerated()), id: \.offset) { i, c in
                                    if i > 0 { Text("·").foregroundStyle(.tertiary) }
                                    Text(c.name).foregroundStyle(.secondary)
                                }
                            }
                            .font(.subheadline)
                        }
                        if !currentBook.tags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) { ForEach(currentBook.tags) { TagPill(tag: $0) } }
                            }
                        }
                    }
                }
                .padding()

                Divider()

                // Meta
                VStack(alignment: .leading, spacing: 0) {
                    if !currentBook.mediaType.isEmpty { MetaRow(label: "Type", value: currentBook.mediaType) }
                    if !currentBook.genres.isEmpty {
                        MetaRow(label: "Genres", value: currentBook.genres.map(\.name).joined(separator: ", "))
                    }
                }

                if !currentBook.description.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description").font(.headline)
                        Text(currentBook.description).font(.body).foregroundStyle(.secondary)
                    }
                    .padding()
                }

                if !seriesRefs.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Series").font(.headline).padding(.horizontal)
                        ForEach(seriesRefs, id: \.seriesId) { ref in
                            HStack {
                                Image(systemName: "list.number").foregroundStyle(.tint)
                                Text(ref.seriesName).font(.subheadline)
                                Spacer()
                                Text("Vol. \(ref.position, specifier: ref.position.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 12)
                }

                if !shelves.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Shelves").font(.headline).padding(.horizontal)
                        ForEach(shelves) { shelf in
                            HStack {
                                Text(shelf.icon)
                                Text(shelf.name).font(.subheadline)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 12)
                }

                if !editions.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Editions").font(.headline).padding(.horizontal)
                        ForEach(editions) { edition in
                            EditionRow(edition: edition)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showEdit = true } label: { Label("Edit", systemImage: "pencil") }
                    Button { showScanner = true } label: { Label("Scan cover", systemImage: "camera.viewfinder") }
                    if let p = currentBook.coverUrl, !p.isEmpty {
                        Button("Clear cover", role: .destructive) { showClearCoverConfirm = true }
                    }
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            AddEditBookSheet(library: library, book: currentBook) { updated in
                currentBook = updated
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            BookCoverScannerView(
                onScan: { image in
                    showScanner = false
                    Task { await uploadCover(image) }
                },
                onCancel: { showScanner = false }
            )
            .ignoresSafeArea()
        }
        .overlay {
            if isUploadingCover {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    ProgressView("Uploading cover…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .alert("Upload failed", isPresented: Binding(get: { uploadError != nil }, set: { if !$0 { uploadError = nil } })) {
            Button("OK") { uploadError = nil }
        } message: { Text(uploadError ?? "") }
        .confirmationDialog("Clear cover for \"\(currentBook.title)\"?", isPresented: $showClearCoverConfirm, titleVisibility: .visible) {
            Button("Clear cover", role: .destructive) {
                Task { await clearCover() }
            }
        }
        .confirmationDialog("Delete \"\(currentBook.title)\"?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await BookService(client: appState.makeClient()).delete(libraryId: library.id, bookId: currentBook.id)
                    dismiss()
                }
            }
        }
        .task {
            await loadDetail()
        }
    }

    private func clearCover() async {
        isUploadingCover = true
        defer { isUploadingCover = false }
        let client = appState.makeClient()
        let svc = BookService(client: client)
        do {
            try await svc.deleteCover(libraryId: library.id, bookId: currentBook.id)
            let refreshed = try await svc.get(libraryId: library.id, bookId: currentBook.id)
            currentBook = refreshed
            coverCacheBuster = Int(Date().timeIntervalSince1970)
        } catch {
            uploadError = error.localizedDescription
        }
    }

    private func uploadCover(_ image: UIImage) async {
        // Cap the long edge at 2000px and compress — the server caps uploads at 10 MB
        // but a sensible resize keeps uploads fast and storage reasonable.
        let jpeg = resizedJPEG(image, maxDimension: 2000, quality: 0.85)
        guard let data = jpeg else {
            uploadError = "Couldn't encode the scanned image."
            return
        }
        isUploadingCover = true
        defer { isUploadingCover = false }

        let client = appState.makeClient()
        let svc = BookService(client: client)
        do {
            try await svc.uploadCover(libraryId: library.id, bookId: currentBook.id, jpegData: data)
            let refreshed = try await svc.get(libraryId: library.id, bookId: currentBook.id)
            currentBook = refreshed
            coverCacheBuster = Int(Date().timeIntervalSince1970)
        } catch {
            uploadError = error.localizedDescription
        }
    }

    private func resizedJPEG(_ image: UIImage, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let size = image.size
        let longEdge = max(size.width, size.height)
        let scale = longEdge > maxDimension ? maxDimension / longEdge : 1
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: quality)
    }

    private func loadDetail() async {
        isLoading = true
        defer { isLoading = false }
        let client = appState.makeClient()
        async let e = BookService(client: client).editions(libraryId: library.id, bookId: book.id)
        async let s = BookService(client: client).shelves(libraryId: library.id, bookId: book.id)
        async let sr = BookService(client: client).seriesRefs(libraryId: library.id, bookId: book.id)
        editions  = (try? await e) ?? []
        shelves   = (try? await s) ?? []
        seriesRefs = (try? await sr) ?? []
    }
}

private struct MetaRow: View {
    let label: String; let value: String
    var body: some View {
        HStack(alignment: .top) {
            Text(label).font(.subheadline).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            Text(value).font(.subheadline)
            Spacer()
        }
        .padding(.horizontal).padding(.vertical, 6)
    }
}

private struct EditionRow: View {
    let edition: BookEdition
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(edition.format.capitalized).font(.subheadline.weight(.medium))
                if edition.isPrimary {
                    Text("Primary").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.tint.opacity(0.15)).foregroundStyle(.tint).clipShape(Capsule())
                }
                Spacer()
            }
            Group {
                if !edition.publisher.isEmpty      { label("Publisher", edition.publisher) }
                if let date = edition.publishDate, !date.isEmpty { label("Published", date) }
                if !edition.language.isEmpty       { label("Language", edition.language) }
                if !edition.isbn13.isEmpty         { label("ISBN-13", edition.isbn13) }
                if !edition.isbn10.isEmpty         { label("ISBN-10", edition.isbn10) }
                if let pages = edition.pageCount   { label("Pages", "\(pages)") }
                if let secs  = edition.durationSeconds {
                    label("Duration", formatDuration(secs))
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private func label(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(key).font(.caption).foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
            Text(value).font(.caption)
            Spacer()
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
