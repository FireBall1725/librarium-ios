// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftData
import SwiftUI

/// Quick add-a-book sheet for Lite libraries when the user doesn't
/// have an ISBN (older books, library copies with worn barcodes,
/// books from countries that don't use ISBN). Title is required;
/// everything else is optional and editable later.
struct LiteManualAddSheet: View {
    let library: Library
    let serverAccountID: UUID
    var onAdded: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var author = ""
    @State private var mediaType = "Book"

    private let mediaTypes = ["Book", "Manga", "Comic", "Graphic novel", "Audiobook"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Book") {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)
                    TextField("Author (optional)", text: $author)
                        .textInputAutocapitalization(.words)
                }
                Section("Type") {
                    Picker("Media type", selection: $mediaType) {
                        ForEach(mediaTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                }
            }
            .navigationTitle("Add Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func add() {
        let writer = LiteBookWriter(modelContainer: modelContext.container)
        _ = writer.addManual(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            author: author.trimmingCharacters(in: .whitespacesAndNewlines),
            to: library,
            serverAccountID: serverAccountID,
            mediaType: mediaType
        )
        onAdded()
        dismiss()
    }
}
