import SwiftUI

/// Small bottom sheet for the "Add to <library>" flow. The barcode gives us
/// an ISBN-13 but no physical format, and the server requires a
/// `media_type_id`, so we ask for both before POSTing instead of guessing.
struct AddToLibrarySheet: View {
    let library: Library
    let mediaTypes: [MediaType]
    let initialMediaTypeID: String?
    let initialFormat: String
    let onAdd: (_ mediaTypeID: String, _ format: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mediaTypeID: String = ""
    @State private var format: String = "paperback"

    private let formats: [(id: String, label: String)] = [
        ("paperback", "Paperback"),
        ("hardcover", "Hardcover"),
        ("ebook", "E-book"),
        ("audiobook", "Audiobook"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type", selection: $mediaTypeID) {
                        ForEach(mediaTypes) { type in
                            Text(type.displayName).tag(type.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Format") {
                    Picker("Format", selection: $format) {
                        ForEach(formats, id: \.id) { f in
                            Text(f.label).tag(f.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Add to \(library.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(mediaTypeID, format)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(mediaTypeID.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            if mediaTypeID.isEmpty {
                mediaTypeID = initialMediaTypeID ?? mediaTypes.first?.id ?? ""
            }
            format = initialFormat
        }
    }
}
