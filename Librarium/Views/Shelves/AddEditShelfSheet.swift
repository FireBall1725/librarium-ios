import SwiftUI

private let presetColors = ["#EF4444","#F97316","#EAB308","#22C55E","#3B82F6","#8B5CF6","#EC4899","#6B7280"]

struct AddEditShelfSheet: View {
    let library: Library
    var shelf: Shelf? = nil
    let onSave: (Shelf) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var color = "#3B82F6"
    @State private var icon = "📚"
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name *", text: $name)
                    TextField("Description", text: $description)
                    TextField("Icon (emoji)", text: $icon)
                }
                Section("Color") {
                    LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 8), spacing: 12) {
                        ForEach(presetColors, id: \.self) { c in
                            Circle()
                                .fill(Color(hex: c))
                                .frame(width: 32, height: 32)
                                .overlay(Circle().stroke(Color.primary, lineWidth: color == c ? 2 : 0).padding(2))
                                .onTapGesture { color = c }
                        }
                    }
                    .padding(.vertical, 4)
                }
                if let err = error {
                    Section { Text(err).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle(shelf == nil ? "New Shelf" : "Edit Shelf")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear {
                if let s = shelf {
                    name = s.name; description = s.description; color = s.color; icon = s.icon
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        isSaving = true; error = nil; defer { isSaving = false }
        let body = ShelfBody(name: name, description: description, color: color, icon: icon)
        do {
            let saved: Shelf
            if let s = shelf {
                saved = try await ShelfService(client: appState.makeClient()).update(libraryId: library.id, shelfId: s.id, body: body)
            } else {
                saved = try await ShelfService(client: appState.makeClient()).create(libraryId: library.id, body: body)
            }
            onSave(saved); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
