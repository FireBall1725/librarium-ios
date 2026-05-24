// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftData
import SwiftUI

/// Lite-mode equivalent of the manage-account sheet. The remote
/// `ProfileView` is built around server-side concerns (password, primary
/// library, server URL); none of those apply locally, so a Lite account
/// only needs a name field and a remove action.
///
/// The single field is "Your name" — saving it does three things in one
/// shot: the server-row chip ("Adaléa's Library"), the `User.displayName`
/// the Home greeting reads, and the `PersistedLibrary.name` on the
/// libraries grid card. We hold the relationship together here so the
/// caller doesn't need to remember to update all three.
struct LiteAccountSettingsView: View {
    let account: ServerAccount

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var personName: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var confirmRemove = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Your name", text: $personName)
                    .textInputAutocapitalization(.words)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit(save)
            } header: {
                Text("Your name")
            } footer: {
                Text("We'll use this for greetings and label your library. Leave blank to keep it generic.")
            }

            Section {
                Button(role: .destructive) {
                    confirmRemove = true
                } label: {
                    Label("Remove this library", systemImage: "trash")
                }
            } footer: {
                Text("Removes the account and everything stored on this device. There's no cloud copy.")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Local Library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving…" : "Save", action: save)
                    .disabled(isSaving)
            }
        }
        .onAppear {
            personName = account.user.displayName
            nameFocused = true
        }
        .confirmationDialog(
            "Remove this library?",
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                removeAccount()
            }
        } message: {
            Text("This deletes \(account.name) and any books you've added locally.")
        }
    }

    private func save() {
        let trimmed = personName.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let resolvedLibraryName = trimmed.isEmpty ? "My Library" : "\(trimmed)'s Library"
        appState.setLocalUserDisplayName(trimmed, for: account.id)
        appState.setLocalAccountName(resolvedLibraryName, for: account.id)

        // Mirror the rename to the SwiftData library row. We update every
        // local library belonging to this account — Lite is single-library
        // today, but writing the loop now means a future "multiple Lite
        // libraries" change doesn't silently leave orphans.
        let accountID = account.id
        let descriptor = FetchDescriptor<PersistedLibrary>(
            predicate: #Predicate { $0.serverAccountID == accountID && $0.deletedAt == nil }
        )
        if let rows = try? modelContext.fetch(descriptor) {
            let now = Date()
            for row in rows {
                row.name = resolvedLibraryName
                row.updatedAt = now
            }
            do {
                try modelContext.save()
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        dismiss()
    }

    private func removeAccount() {
        let accountID = account.id
        let descriptor = FetchDescriptor<PersistedLibrary>(
            predicate: #Predicate { $0.serverAccountID == accountID }
        )
        if let rows = try? modelContext.fetch(descriptor) {
            for row in rows { modelContext.delete(row) }
            try? modelContext.save()
        }
        appState.removeAccount(id: accountID)
        dismiss()
    }
}
