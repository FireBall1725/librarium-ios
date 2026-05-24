// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

struct CreateLibrarySheet: View {
    let onCreated: (Library) -> Void
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var isPublic = false
    @State private var keepOffline = false
    @State private var isSaving = false
    @State private var error: String?

    private let offlineStore = LibraryOfflineStore.shared

    var body: some View {
        NavigationStack {
            Form {
                libraryFields
                offlineSection
                if let err = error {
                    Section { Text(err).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle("New Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Creating…" : "Create") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var libraryFields: some View {
        Section("Library Details") {
            TextField("Name", text: $name)
            TextField("Description (optional)", text: $description)
            Toggle("Public library", isOn: $isPublic)
        }
    }

    private var offlineSection: some View {
        Section {
            Toggle(isOn: $keepOffline) {
                Label("Keep offline", systemImage: "arrow.down.circle")
            }
        } footer: {
            Text("Cache this library so it's available when the server is unreachable.")
        }
    }

    private func save() async {
        isSaving = true; error = nil; defer { isSaving = false }
        do {
            var lib = try await LibraryService(client: appState.makeClient())
                .create(name: name, description: description, isPublic: isPublic)
            // Stamp with active-account context so clientKey is stable before the
            // next list refresh re-injects it.
            if let ctx = appState.activeAccountContext {
                lib.serverURL  = ctx.url
                lib.serverName = ctx.name
            }
            offlineStore.setEnabled(keepOffline, for: lib.clientKey)
            if keepOffline {
                offlineStore.cacheLibrary(lib)
                let client = appState.makeClient()
                Task { await offlineStore.syncBooks(for: lib, client: client) }
            }
            onCreated(lib); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
