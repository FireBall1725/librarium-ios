import SwiftUI

struct BulkEditBooksSheet: View {
    let library: Library
    let books: [Book]
    let availableTags: [Tag]
    let availableMediaTypes: [MediaType]
    let onComplete: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// Empty string = no change
    @State private var newMediaTypeId: String = ""
    @State private var tagsToAdd: Set<String> = []
    @State private var tagsToRemove: Set<String> = []
    @State private var isApplying = false
    @State private var progress = 0
    @State private var error: String?

    private var hasChanges: Bool {
        !newMediaTypeId.isEmpty || !tagsToAdd.isEmpty || !tagsToRemove.isEmpty
    }

    /// Tags present in at least one of the selected books (candidates for removal)
    private var tagsInSelection: [Tag] {
        let ids = Set(books.flatMap { $0.tags.map(\.id) })
        return availableTags.filter { ids.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Media Type", selection: $newMediaTypeId) {
                        Text("No change").tag("")
                        ForEach(availableMediaTypes) { type in
                            Text(type.displayName).tag(type.id)
                        }
                    }
                } header: {
                    Text("Change Media Type")
                } footer: {
                    if !newMediaTypeId.isEmpty,
                       let name = availableMediaTypes.first(where: { $0.id == newMediaTypeId })?.displayName {
                        Text("Will be changed to \"\(name)\" on all selected books.")
                    }
                }

                if !availableTags.isEmpty {
                    Section("Add Tags") {
                        ForEach(availableTags.filter { !tagsToRemove.contains($0.id) }) { tag in
                            tagToggleRow(
                                tag: tag,
                                isOn: tagsToAdd.contains(tag.id),
                                icon: "plus.circle.fill",
                                activeColor: Color.accentColor
                            ) {
                                if tagsToAdd.contains(tag.id) { tagsToAdd.remove(tag.id) }
                                else { tagsToAdd.insert(tag.id) }
                            }
                        }
                    }

                    if !tagsInSelection.isEmpty {
                        Section("Remove Tags") {
                            ForEach(tagsInSelection.filter { !tagsToAdd.contains($0.id) }) { tag in
                                tagToggleRow(
                                    tag: tag,
                                    isOn: tagsToRemove.contains(tag.id),
                                    icon: "minus.circle.fill",
                                    activeColor: .red
                                ) {
                                    if tagsToRemove.contains(tag.id) { tagsToRemove.remove(tag.id) }
                                    else { tagsToRemove.insert(tag.id) }
                                }
                            }
                        }
                    }
                }

                if isApplying {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: Double(progress), total: Double(books.count))
                            Text("Updated \(progress) of \(books.count) books…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let err = error {
                    Section {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Edit \(books.count) Book\(books.count == 1 ? "" : "s")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isApplying)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { Task { await apply() } }
                        .disabled(!hasChanges || isApplying)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func tagToggleRow(tag: Tag, isOn: Bool, icon: String, activeColor: Color, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack {
                TagPill(tag: tag)
                Spacer()
                Image(systemName: isOn ? icon : "circle")
                    .foregroundStyle(isOn ? activeColor : Color.secondary.opacity(0.4))
                    .font(.title3)
            }
        }
        .buttonStyle(.plain)
    }

    private func apply() async {
        isApplying = true; error = nil; progress = 0
        defer { isApplying = false }

        let client = appState.makeClient()
        let mediaTypeChange = newMediaTypeId
        let addTags = tagsToAdd
        let removeTags = tagsToRemove

        // Build all requests on the main actor before spinning up concurrent tasks,
        // so toUpdateRequest() isn't called from a non-isolated task closure.
        let requests: [(bookId: String, req: CreateBookRequest)] = books.map { book in
            var req = book.toUpdateRequest()
            if !mediaTypeChange.isEmpty { req.mediaTypeId = mediaTypeChange }
            let current = Set(req.tagIds)
            req.tagIds = Array(current.union(addTags).subtracting(removeTags))
            return (book.id, req)
        }

        var failCount = 0
        await withTaskGroup(of: Bool.self) { group in
            for (bookId, req) in requests {
                group.addTask {
                    return (try? await BookService(client: client)
                        .update(libraryId: library.id, bookId: bookId, body: req)) != nil
                }
            }
            for await success in group {
                progress += 1
                if !success { failCount += 1 }
            }
        }

        if failCount > 0 {
            error = "\(failCount) book\(failCount == 1 ? "" : "s") failed to update."
        } else {
            onComplete()
            dismiss()
        }
    }
}
