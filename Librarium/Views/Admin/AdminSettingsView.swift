import SwiftUI

struct AdminSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var providers: [ProviderStatus] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading && providers.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    let bookProviders = providers.filter { $0.capabilities.contains("book_isbn") }
                    let seriesProviders = providers.filter { $0.capabilities.contains("series_name") }

                    if !bookProviders.isEmpty {
                        Section("Book Metadata Providers") {
                            ForEach(bookProviders) { ProviderRow(provider: $0, onSave: save) }
                        }
                    }
                    if !seriesProviders.isEmpty {
                        Section("Series Metadata Providers") {
                            ForEach(seriesProviders) { ProviderRow(provider: $0, onSave: save) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Provider Settings")
        .task { await load() }
        .refreshable { await load() }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func load() async {
        isLoading = true; defer { isLoading = false }
        do { providers = try await AdminService(client: appState.makeClient()).providers() }
        catch { self.error = error.localizedDescription }
    }

    private func save(name: String, enabled: Bool, apiKey: String?) async {
        do {
            providers = try await AdminService(client: appState.makeClient())
                .updateProvider(name: name, enabled: enabled, apiKey: apiKey)
        } catch { self.error = error.localizedDescription }
    }
}

private struct ProviderRow: View {
    let provider: ProviderStatus
    let onSave: (String, Bool, String?) async -> Void

    @State private var enabled: Bool
    @State private var apiKey = ""
    @State private var isSaving = false

    init(provider: ProviderStatus, onSave: @escaping (String, Bool, String?) async -> Void) {
        self.provider = provider
        self.onSave = onSave
        self._enabled = State(initialValue: provider.enabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName).font(.headline)
                    Text(provider.description).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $enabled).labelsHidden()
            }
            if provider.requiresKey {
                SecureField(provider.hasApiKey ? "API key saved" : "Enter API key", text: $apiKey)
                    .font(.caption)
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            Button {
                isSaving = true
                Task {
                    await onSave(provider.name, enabled, apiKey.isEmpty ? nil : apiKey)
                    isSaving = false
                }
            } label: {
                Text(isSaving ? "Saving…" : "Save")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .disabled(isSaving)
        }
        .padding(.vertical, 4)
    }
}
