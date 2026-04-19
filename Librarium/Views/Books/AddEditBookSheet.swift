import SwiftUI

struct AddEditBookSheet: View {
    let library: Library
    var book: Book? = nil
    var initialLookup: ISBNLookupResult? = nil
    let onSave: (Book) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var tab: InputTab = .isbn
    @State private var req = CreateBookRequest(title: "")
    @State private var isSaving = false
    @State private var error: String?

    // ISBN lookup state
    @State private var isbnInput = ""
    @State private var isLookingUp = false
    @State private var lookupResults: [ISBNLookupResult] = []
    @State private var showScanner = false

    // Tag & media type state
    @State private var availableTags: [Tag] = []
    @State private var availableMediaTypes: [MediaType] = []
    @State private var selectedTagIds: Set<String> = []

    enum InputTab: String, CaseIterable {
        case isbn = "Scan / ISBN"
        case manual = "Manual"
    }

    var isEditing: Bool { book != nil }

    var body: some View {
        NavigationStack {
            Form {
                if !isEditing {
                    Picker("Input method", selection: $tab) {
                        ForEach(InputTab.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init())
                    .padding(.horizontal)
                }

                if tab == .isbn && !isEditing {
                    isbnSection
                }

                if !lookupResults.isEmpty {
                    Section("Results — tap to use") {
                        ForEach(lookupResults) { result in
                            Button { applyLookup(result) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title).font(.subheadline.weight(.medium))
                                    Text(result.authors.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                                    Text(result.providerDisplay).font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Details") {
                    TextField("Title *", text: $req.title)
                    TextField("Subtitle", text: $req.subtitle)
                }

                Section("Metadata") {
                    Picker("Media type", selection: $req.mediaTypeId) {
                        Text("—").tag("")
                        ForEach(availableMediaTypes) { type in
                            Text(type.displayName).tag(type.id)
                        }
                    }
                }

                Section("Description") {
                    TextField("Description", text: $req.description, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)
                }

                // Edition details — only shown when creating (inline with book creation).
                // When editing a book, editions are managed separately from BookDetailView.
                if !isEditing {
                    Section("Edition Details") {
                        TextField("ISBN-13", text: editionBinding(\.isbn13))
                            .keyboardType(.numberPad)
                        TextField("ISBN-10", text: editionBinding(\.isbn10))
                            .keyboardType(.numberPad)
                        TextField("Publisher", text: editionBinding(\.publisher))
                        TextField("Language (e.g. en)", text: editionBinding(\.language))
                            .textInputAutocapitalization(.never)
                        TextField("Publish date (YYYY-MM-DD)", text: Binding(
                            get: { req.edition?.publishDate ?? "" },
                            set: { ensureEdition(); req.edition?.publishDate = $0.isEmpty ? nil : $0 }
                        ))
                    }
                }

                Section("Tags") {
                    ForEach(availableTags) { tag in
                        Button {
                            if selectedTagIds.contains(tag.id) { selectedTagIds.remove(tag.id) }
                            else { selectedTagIds.insert(tag.id) }
                        } label: {
                            HStack {
                                TagPill(tag: tag)
                                Spacer()
                                if selectedTagIds.contains(tag.id) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if availableTags.isEmpty {
                        Text("No tags yet").foregroundStyle(.secondary)
                    }
                }

                if let err = error {
                    Section {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Book" : "Add Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(req.title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .sheet(isPresented: $showScanner) {
                BarcodeScannerView(
                    onScan: { isbn in
                        showScanner = false
                        isbnInput = isbn
                        Task { await lookupISBN(isbn) }
                    },
                    onCancel: { showScanner = false }
                )
                .ignoresSafeArea()
            }
            .task {
                await loadSupportingData()
                if let lookup = initialLookup { applyLookup(lookup) }
            }
        }
    }

    // MARK: - ISBN section

    private var isbnSection: some View {
        Section {
            HStack {
                TextField("ISBN", text: $isbnInput)
                    .keyboardType(.numberPad)
                Button {
                    Task { await lookupISBN(isbnInput) }
                } label: {
                    if isLookingUp { ProgressView().scaleEffect(0.8) }
                    else { Text("Look up") }
                }
                .disabled(isbnInput.isEmpty || isLookingUp)
            }
            Button {
                showScanner = true
            } label: {
                Label("Scan Barcode", systemImage: "barcode.viewfinder")
            }
        }
    }

    // MARK: - Helpers

    /// Returns a Binding to a String property on the inline edition,
    /// creating the edition if it doesn't exist yet.
    private func editionBinding(_ kp: WritableKeyPath<CreateEditionRequest, String>) -> Binding<String> {
        Binding(
            get: { req.edition?[keyPath: kp] ?? "" },
            set: { ensureEdition(); req.edition?[keyPath: kp] = $0 }
        )
    }

    private func ensureEdition() {
        if req.edition == nil { req.edition = CreateEditionRequest() }
    }

    // MARK: - Lookup

    private func lookupISBN(_ isbn: String) async {
        guard !isbn.isEmpty else { return }
        isLookingUp = true
        defer { isLookingUp = false }
        do {
            lookupResults = try await LookupService(client: appState.makeClient()).isbn(isbn)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func applyLookup(_ r: ISBNLookupResult) {
        req.title       = r.title
        req.subtitle    = r.subtitle
        req.description = r.description
        ensureEdition()
        req.edition?.isbn13      = r.isbn13
        req.edition?.isbn10      = r.isbn10
        req.edition?.publisher   = r.publisher
        req.edition?.publishDate = r.publishDate.isEmpty ? nil : r.publishDate
        req.edition?.language    = r.language
        if let count = r.pageCount { req.edition?.pageCount = count }
        lookupResults = []
        tab = .manual
    }

    // MARK: - Data loading

    private func loadSupportingData() async {
        let client = appState.makeClient()
        async let tagsResult  = TagService(client: client).list(libraryId: library.id)
        async let typesResult = MediaTypeService(client: client).list()
        availableTags       = (try? await tagsResult)  ?? []
        availableMediaTypes = (try? await typesResult) ?? []

        if let book {
            req = book.toUpdateRequest()
            selectedTagIds = Set(book.tags.map(\.id))
        }
    }

    // MARK: - Save

    private func save() async {
        isSaving = true; error = nil
        defer { isSaving = false }
        req.tagIds = Array(selectedTagIds)
        // Drop edition if all fields are empty (user didn't fill anything in)
        if let ed = req.edition,
           ed.isbn13.isEmpty && ed.isbn10.isEmpty && ed.publisher.isEmpty
           && ed.language.isEmpty && ed.publishDate == nil && ed.pageCount == nil {
            req.edition = nil
        }
        do {
            let saved: Book
            if let book {
                saved = try await BookService(client: appState.makeClient()).update(
                    libraryId: library.id, bookId: book.id, body: req)
            } else {
                saved = try await BookService(client: appState.makeClient()).create(
                    libraryId: library.id, body: req)
            }
            onSave(saved)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
