// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// Where metadata enrichment sources are turned on and configured.
///
/// These sources only ever run for local (Lite) libraries. A book on a
/// Librarium server gets its metadata from the server's own providers,
/// which are configured in the admin console, so nothing here changes
/// what a server does. The notice at the top says so, because the screen
/// lives in app settings where it looks global.
struct LiteMetadataSourcesView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var openLibraryEnabled = LiteMetadataSettings.isEnabled(providerID: "openlibrary")
    @State private var hardcoverEnabled = LiteMetadataSettings.isEnabled(providerID: "hardcover")
    @State private var hardcoverKey = ""
    @State private var isValidating = false
    @State private var validationError: String?
    @State private var savedConfirmation = false
    @State private var hasStoredKey = KeychainService.shared.get(HardcoverService.keychainKey)?.isEmpty == false

    /// Says which source wins, but only when both are actually running.
    /// Stating a precedence rule that cannot apply is just noise.
    private var openLibraryFooter: String {
        let base = "Free and anonymous. No account, no key, and nothing that identifies you leaves the device beyond the ISBN or title being looked up."
        guard hardcoverEnabled, hasStoredKey, openLibraryEnabled else { return base }
        return base + " Hardcover answers first while it is on; Open Library fills in anything Hardcover does not have."
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("These sources are only used for libraries stored on this device. Books on a Librarium server get their metadata from that server's own providers.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Open Library", isOn: $openLibraryEnabled)
                    .onChange(of: openLibraryEnabled) { _, value in
                        LiteMetadataSettings.setEnabled(value, providerID: "openlibrary")
                    }
            } footer: {
                Text(openLibraryFooter)
            }

            Section {
                Toggle("Hardcover", isOn: $hardcoverEnabled)
                    .onChange(of: hardcoverEnabled) { _, value in
                        LiteMetadataSettings.setEnabled(value, providerID: "hardcover")
                    }

                if hardcoverEnabled {
                    if hasStoredKey {
                        LabeledContent("API key") {
                            Text("Saved").foregroundStyle(.secondary)
                        }
                        Button("Remove key", role: .destructive) { remove() }
                    }

                    SecureField(hasStoredKey ? "Replace key" : "API key", text: $hardcoverKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if isValidating {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Checking the key…").foregroundStyle(.secondary)
                        }
                    } else {
                        Button("Save and check") { Task { await save() } }
                            .disabled(hardcoverKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    Link("Get a Hardcover API key", destination: URL(string: "https://hardcover.app/account/api")!)

                    if let validationError {
                        Label(validationError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if savedConfirmation {
                        Label("Key saved. Hardcover will be used on refresh.", systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                }
            } header: {
                Text("Hardcover")
            } footer: {
                Text("Optional. Hardcover has descriptions, genres, and series data that Open Library usually lacks. It needs a free account, and because the key identifies you, every lookup tells Hardcover which book you are asking about. Pasting the key with or without its \"Bearer\" prefix both work. Stored in the device Keychain, never synced.")
            }

            if hardcoverEnabled && !hasStoredKey {
                Section {
                    Label("Hardcover is on but has no key yet, so it will be skipped.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            if !LiteMetadataSettings.hasActiveProvider {
                Section {
                    Label("No sources are active. Refresh metadata will be unavailable until you turn one on.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Metadata Sources")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() async {
        let key = hardcoverKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isValidating = true
        savedConfirmation = false
        validationError = nil
        defer { isValidating = false }

        // Check before storing, so a typo does not sit in the Keychain
        // quietly failing every refresh.
        if let failure = await HardcoverService.validate(key: key) {
            validationError = failure
            return
        }
        KeychainService.shared.set(
            HardcoverService.normalize(key: key),
            forKey: HardcoverService.keychainKey
        )
        hardcoverKey = ""
        hasStoredKey = true
        savedConfirmation = true
    }

    private func remove() {
        KeychainService.shared.delete(HardcoverService.keychainKey)
        hardcoverKey = ""
        hasStoredKey = false
        savedConfirmation = false
        validationError = nil
    }
}
