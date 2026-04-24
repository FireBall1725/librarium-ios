import SwiftUI

/// Pushed detail for editing a user's interaction with one edition of one
/// book in one library. Cancel / Save in the nav bar. Layout patterned
/// after Calendar's new-event and Contacts edit screens: one compact
/// header, then dense rows grouped by meaning — not one item per section.
struct InteractionDetailView: View {
    let account: ServerAccount
    let library: Library
    let bookID: String
    let editions: [BookEdition]
    let initialEditionIndex: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var editionIndex: Int = 0
    @State private var loadedInteractions: [String: Draft] = [:]
    @State private var originalInteractions: [String: Draft] = [:]
    @State private var loadingEditionIDs: Set<String> = []
    @State private var saving = false
    @State private var error: String?
    @State private var showDiscardConfirm = false

    var onSaved: ((String /* editionID */, UserBookInteraction) -> Void)?

    var body: some View {
        Form {
            if editions.count > 1 {
                Section {
                    TabView(selection: $editionIndex) {
                        ForEach(Array(editions.enumerated()), id: \.offset) { idx, edition in
                            EditionRow(edition: edition).tag(idx)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .never))
                    .frame(height: 70)
                } footer: {
                    Text("Swipe between editions — each has its own status, rating, and notes.")
                }
            } else if let only = editions.first {
                Section {
                    EditionRow(edition: only)
                }
            }

            Section {
                Picker("Status", selection: readStatusBinding) {
                    Text("Unread").tag("unread")
                    Text("Reading").tag("reading")
                    Text("Read").tag("read")
                    Text("Did not finish").tag("did_not_finish")
                }
                HStack {
                    Text("Rating")
                    Spacer()
                    RatingStars(value: ratingBinding, starSize: 22, spacing: 2)
                        .layoutPriority(1)
                }
                Toggle(isOn: favouriteBinding) {
                    Label("Favourite", systemImage: draft.isFavorite ? "heart.fill" : "heart")
                        .labelStyle(.titleAndIcon)
                }
            }

            Section {
                TextField("", text: notesBinding,
                          prompt: Text("Jot-downs, quotes, pages to revisit."),
                          axis: .vertical)
                    .lineLimit(3...8)
            } header: { Text("Notes") }
              footer: { Text("Private — only you.") }

            Section {
                TextField("", text: reviewBinding,
                          prompt: Text("Share your take with other members of this library."),
                          axis: .vertical)
                    .lineLimit(3...10)
            } header: { Text("Review") }
              footer: { Text("Shared with members of this library.") }

            if let error {
                Section { Text(error).font(.footnote).foregroundStyle(.red) }
            }
        }
        .navigationTitle(library.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if isDirty { showDiscardConfirm = true } else { dismiss() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.backward").fontWeight(.semibold)
                        Text("Back")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(saving ? "Saving…" : "Save") { Task { await save() } }
                    .fontWeight(.semibold)
                    .disabled(saving || !isDirty)
            }
        }
        .confirmationDialog("Discard changes?",
                            isPresented: $showDiscardConfirm,
                            titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .onAppear {
            editionIndex = initialEditionIndex
            Task { await ensureLoaded(editionID: selectedEditionID) }
        }
        .onChange(of: editionIndex) { _, _ in
            Task { await ensureLoaded(editionID: selectedEditionID) }
        }
    }

    // MARK: - Bindings

    private var readStatusBinding: Binding<String> {
        Binding(get: { draft.readStatus },
                set: { loadedInteractions[selectedEditionID] = draft.with(readStatus: $0) })
    }
    private var ratingBinding: Binding<Int?> {
        Binding(get: { draft.rating },
                set: { loadedInteractions[selectedEditionID] = draft.with(rating: $0) })
    }
    private var notesBinding: Binding<String> {
        Binding(get: { draft.notes },
                set: { loadedInteractions[selectedEditionID] = draft.with(notes: $0) })
    }
    private var reviewBinding: Binding<String> {
        Binding(get: { draft.review },
                set: { loadedInteractions[selectedEditionID] = draft.with(review: $0) })
    }
    private var favouriteBinding: Binding<Bool> {
        Binding(get: { draft.isFavorite },
                set: { loadedInteractions[selectedEditionID] = draft.with(isFavorite: $0) })
    }

    private var selectedEditionID: String {
        guard editions.indices.contains(editionIndex) else { return "" }
        return editions[editionIndex].id
    }
    private var draft: Draft { loadedInteractions[selectedEditionID] ?? Draft() }
    private var isDirty: Bool {
        guard !selectedEditionID.isEmpty else { return false }
        return loadedInteractions[selectedEditionID] != originalInteractions[selectedEditionID]
    }

    // MARK: - Load + save

    private func ensureLoaded(editionID: String) async {
        guard !editionID.isEmpty else { return }
        if loadedInteractions[editionID] != nil { return }
        if loadingEditionIDs.contains(editionID) { return }
        loadingEditionIDs.insert(editionID)
        defer { loadingEditionIDs.remove(editionID) }

        let client = makeClient()
        let d: Draft
        do {
            if let existing = try await BookService(client: client)
                .interaction(libraryId: library.id, bookId: bookID, editionId: editionID)
            {
                d = Draft(from: existing)
            } else {
                d = Draft()
            }
        } catch {
            d = Draft()
        }
        loadedInteractions[editionID] = d
        originalInteractions[editionID] = d
    }

    private func save() async {
        guard !selectedEditionID.isEmpty else { return }
        saving = true; error = nil; defer { saving = false }
        let payload = UpdateInteractionRequest(
            readStatus: draft.readStatus,
            rating: draft.rating.map { Double($0) },
            notes: draft.notes,
            review: draft.review,
            dateStarted: nil,
            dateFinished: nil,
            isFavorite: draft.isFavorite
        )
        do {
            let saved = try await BookService(client: makeClient())
                .updateInteraction(libraryId: library.id, bookId: bookID,
                                   editionId: selectedEditionID, body: payload)
            originalInteractions[selectedEditionID] = draft
            onSaved?(selectedEditionID, saved)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func makeClient() -> APIClient {
        appState.makeClient(serverURL: library.serverURL)
    }
}

// MARK: - Edition row

private struct EditionRow: View {
    let edition: BookEdition

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(formatName).font(.body.weight(.semibold))
                    if edition.isPrimary {
                        Text("PRIMARY")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(.tint)
                    }
                }
                Text(metaLine)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var formatName: String {
        switch edition.format.lowercased() {
        case "hardcover", "hardback":  return "Hardcover"
        case "paperback":              return "Paperback"
        case "ebook", "e-book":        return "E-book"
        case "audiobook", "audio":     return "Audiobook"
        case "physical":               return "Physical"
        case let other where !other.isEmpty: return other.capitalized
        default:                        return "Edition"
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if !edition.publisher.isEmpty { parts.append(edition.publisher) }
        if let s = edition.publishDate, s.count >= 4 { parts.append(String(s.prefix(4))) }
        let isbn = edition.isbn13.isEmpty ? edition.isbn10 : edition.isbn13
        if !isbn.isEmpty { parts.append(isbn) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Draft

private struct Draft: Equatable {
    var readStatus: String = "unread"
    var rating: Int? = nil
    var notes: String = ""
    var review: String = ""
    var isFavorite: Bool = false

    init() {}
    init(from i: UserBookInteraction) {
        readStatus = i.readStatus.isEmpty ? "unread" : i.readStatus
        rating = i.rating.map { Int($0.rounded()) }
        notes = i.notes
        review = i.review
        isFavorite = i.isFavorite
    }

    func with(readStatus s: String? = nil,
              rating r: Int?? = nil,
              notes n: String? = nil,
              review rv: String? = nil,
              isFavorite f: Bool? = nil) -> Draft {
        var d = self
        if let s { d.readStatus = s }
        if let r { d.rating = r }
        if let n { d.notes = n }
        if let rv { d.review = rv }
        if let f { d.isFavorite = f }
        return d
    }
}
