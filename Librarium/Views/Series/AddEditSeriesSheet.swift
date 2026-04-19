import SwiftUI

struct AddEditSeriesSheet: View {
    let library: Library
    var series: Series? = nil
    let onSave: (Series) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var body_ = SeriesBody(name: "")
    @State private var availableTags: [Tag] = []
    @State private var selectedTagIds: Set<String> = []
    @State private var isSaving = false
    @State private var error: String?

    // Metadata search
    @State private var lookupQuery = ""
    @State private var isLookingUp = false
    @State private var lookupResults: [SeriesLookupResult] = []
    @State private var showLookup = false

    var isEditing: Bool { series != nil }

    var body: some View {
        NavigationStack {
            Form {
                if !isEditing {
                    Section {
                        HStack {
                            TextField("Search series providers…", text: $lookupQuery)
                                .autocorrectionDisabled()
                            Button {
                                Task { await lookupSeries() }
                            } label: {
                                if isLookingUp { ProgressView().scaleEffect(0.8) }
                                else { Text("Search") }
                            }
                            .disabled(lookupQuery.isEmpty || isLookingUp)
                        }
                    } header: { Text("Metadata Lookup (optional)") }

                    if !lookupResults.isEmpty {
                        Section("Results — tap to use") {
                            ForEach(lookupResults) { r in
                                Button { applyLookup(r) } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.name).font(.subheadline.weight(.medium))
                                        HStack {
                                            if let year = r.publicationYear { Text("\(year)").font(.caption).foregroundStyle(.secondary) }
                                            Text(r.providerDisplay).font(.caption2).foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section("Details") {
                    TextField("Name *", text: $body_.name)
                    TextField("Description", text: $body_.description, axis: .vertical).lineLimit(3, reservesSpace: true)
                    TextField("Status (ongoing, completed, hiatus)", text: $body_.status)
                    TextField("Original language", text: $body_.originalLanguage)
                }

                Section("Publication") {
                    TextField("Publication year", value: $body_.publicationYear, format: .number)
                        .keyboardType(.numberPad)
                    TextField("Total volumes", value: $body_.totalCount, format: .number)
                        .keyboardType(.numberPad)
                    Toggle("Complete", isOn: $body_.isComplete)
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
                                if selectedTagIds.contains(tag.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let err = error {
                    Section { Text(err).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle(isEditing ? "Edit Series" : "Add Series")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(body_.name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .task { await loadTags() }
        }
    }

    private func lookupSeries() async {
        isLookingUp = true; defer { isLookingUp = false }
        lookupResults = (try? await LookupService(client: appState.makeClient()).series(query: lookupQuery)) ?? []
    }

    private func applyLookup(_ r: SeriesLookupResult) {
        body_.name = r.name; body_.description = r.description
        body_.status = r.status; body_.originalLanguage = r.originalLanguage
        body_.totalCount = r.totalCount; body_.isComplete = r.isComplete
        body_.publicationYear = r.publicationYear
        body_.genres = r.genres; body_.url = r.url
        body_.externalId = r.externalId; body_.externalSource = r.externalSource
        lookupResults = []
    }

    private func loadTags() async {
        availableTags = (try? await TagService(client: appState.makeClient()).list(libraryId: library.id)) ?? []
        if let s = series {
            body_ = SeriesBody(name: s.name, description: s.description, totalCount: s.totalCount,
                               isComplete: s.isComplete, status: s.status, originalLanguage: s.originalLanguage,
                               publicationYear: s.publicationYear, externalId: s.externalId,
                               externalSource: s.externalSource, tagIds: s.tags.map(\.id))
            body_.genres = s.genres; body_.url = s.url
            selectedTagIds = Set(s.tags.map(\.id))
        }
    }

    private func save() async {
        isSaving = true; error = nil; defer { isSaving = false }
        body_.tagIds = Array(selectedTagIds)
        do {
            let saved: Series
            if let s = series {
                saved = try await SeriesService(client: appState.makeClient()).update(libraryId: library.id, seriesId: s.id, body: body_)
            } else {
                saved = try await SeriesService(client: appState.makeClient()).create(libraryId: library.id, body: body_)
            }
            onSave(saved); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
