// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftData
import SwiftUI

struct CreateLibrarySheet: View {
    let onCreated: (Library) -> Void
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var isPublic = false
    @State private var keepOffline = false
    @State private var isSaving = false
    @State private var error: String?

    /// True when every signed-in account is Lite-mode local. Drives the
    /// SwiftData write-path below and hides server-only affordances
    /// (public toggle, keep-offline toggle) that don't apply locally.
    private var isLocalOnly: Bool { appState.isLocalOnly }

    private let offlineStore = LibraryOfflineStore.shared

    var body: some View {
        NavigationStack {
            Form {
                libraryFields
                if !isLocalOnly { offlineSection }
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
            if !isLocalOnly {
                Toggle("Public library", isOn: $isPublic)
            }
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
        if isLocalOnly, let account = appState.accounts.first(where: { $0.kind == .local }) {
            saveLocal(account: account)
            return
        }
        do {
            var lib = try await LibraryService(client: appState.makeClient())
                .create(name: name, description: description, isPublic: isPublic)
            // Stamp with active-account context so clientKey is stable before the
            // next list refresh re-injects it.
            if let ctx = appState.activeAccountContext {
                lib.serverURL  = ctx.url
                lib.serverName = ctx.name
            }
            offlineStore.setEnabled(keepOffline, for: lib.clientKey, modelContainer: modelContext.container)
            if keepOffline,
               let account = appState.accounts.first(where: { $0.url == lib.serverURL }) {
                offlineStore.cacheLibrary(lib)
                let client = appState.makeClient()
                let container = modelContext.container
                let accountID = account.id
                let accessToken = account.accessToken
                Task {
                    await offlineStore.syncBooks(
                        for: lib,
                        client: client,
                        serverAccountID: accountID,
                        accessToken: accessToken,
                        modelContainer: container
                    )
                }
            }
            onCreated(lib); dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func saveLocal(account: ServerAccount) {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedDesc = description.trimmingCharacters(in: .whitespaces)
        let row = PersistedLibrary(
            serverAccountID: account.id,
            name: trimmedName,
            libraryDescription: trimmedDesc,
            isPublic: false
        )
        modelContext.insert(row)
        do {
            try modelContext.save()
        } catch {
            self.error = error.localizedDescription
            return
        }
        onCreated(row.toLibrary(serverAccountID: account.id, accountName: account.name))
        dismiss()
    }
}
