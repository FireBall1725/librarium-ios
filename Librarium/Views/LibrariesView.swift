import SwiftUI

enum LibraryRowState {
    case online            // fetched live this session
    case offlineCached     // server unreachable, books in local cache
    case offline           // server unreachable, no book cache
}

@Observable
private final class LibrariesViewModel {
    var libraries: [Library] = []
    var libraryStates: [String: LibraryRowState] = [:]
    var isLoading = false
    var error: String?
    var isOffline = false
    var isUnreachable = false

    private let offlineStore = LibraryOfflineStore.shared

    func load(appState: AppState) async {
        isLoading = true; error = nil
        defer { isLoading = false }

        let accounts = appState.accounts
        guard !accounts.isEmpty else {
            libraries = []; libraryStates = [:]
            isOffline = false; isUnreachable = true
            return
        }

        var successfulURLs: Set<String> = []
        var freshLibraries: [Library] = []

        await withTaskGroup(of: (String, [Library]?).self) { group in
            for account in accounts {
                group.addTask {
                    do {
                        let client = await appState.makeClient(serverURL: account.url)
                        var libs = try await LibraryService(client: client).list()
                        for i in libs.indices {
                            libs[i].serverURL  = account.url
                            libs[i].serverName = account.name
                        }
                        return (account.url, libs)
                    } catch {
                        return (account.url, nil)
                    }
                }
            }
            for await (url, libs) in group {
                if let libs {
                    successfulURLs.insert(url)
                    freshLibraries.append(contentsOf: libs)
                }
            }
        }

        // Always persist metadata for fresh libraries — decoupled from the
        // per-library "Keep offline" book-caching opt-in so every library
        // stays visible in the list when its server is unreachable.
        for lib in freshLibraries { offlineStore.cacheLibrary(lib) }

        // Merge in cached libraries for accounts that failed this pass.
        // Filter to currently-configured accounts (defensive; purge handles
        // the normal case) and skip any key we already have fresh data for.
        let accountURLs = Set(accounts.map { $0.url })
        let freshKeys = Set(freshLibraries.map { $0.clientKey })
        let cachedExtras = offlineStore.cachedLibraries().filter {
            accountURLs.contains($0.serverURL)
                && !successfulURLs.contains($0.serverURL)
                && !freshKeys.contains($0.clientKey)
        }

        let combined = (freshLibraries + cachedExtras)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        var states: [String: LibraryRowState] = [:]
        for lib in combined {
            if successfulURLs.contains(lib.serverURL) {
                states[lib.clientKey] = .online
            } else if offlineStore.cachedBooks(for: lib.clientKey) != nil {
                states[lib.clientKey] = .offlineCached
            } else {
                states[lib.clientKey] = .offline
            }
        }

        libraries = combined
        libraryStates = states

        for lib in combined
        where successfulURLs.contains(lib.serverURL) && offlineStore.isEnabled(for: lib.clientKey) {
            let client = appState.makeClient(serverURL: lib.serverURL)
            Task { await offlineStore.syncBooks(for: lib, client: client) }
        }

        // Global flags. `isOffline` is now "every server is unreachable" so
        // downstream views (Books/Series/Shelves/etc.) keep their existing
        // "hide network actions when offline" semantics; mixed states don't
        // trip the global offline guard.
        if combined.isEmpty && successfulURLs.isEmpty {
            isOffline = false; isUnreachable = true
        } else {
            isOffline = successfulURLs.isEmpty
            isUnreachable = false
        }
    }

    func updateLibrary(_ updated: Library) {
        // Match by clientKey, not id: two libraries on different servers can
        // share the same UUID (e.g. after a DB transplant), and matching by
        // bare id would collapse them into the same row.
        if let i = libraries.firstIndex(where: { $0.clientKey == updated.clientKey }) {
            libraries[i] = updated
        }
        offlineStore.cacheLibrary(updated)
        libraryStates[updated.clientKey] = .online
    }

    func appendLibrary(_ lib: Library) {
        libraries.append(lib)
        offlineStore.cacheLibrary(lib)
        libraryStates[lib.clientKey] = .online
    }
}

struct LibrariesView: View {
    let onSelect: (Library) -> Void
    @Environment(AppState.self) private var appState
    @State private var vm = LibrariesViewModel()
    @State private var showCreate = false
    @State private var libraryToEdit: Library?
    @State private var showScanner = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.libraries.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.isUnreachable {
                    ServerUnreachableView(
                        onRetry: { Task { await vm.load(appState: appState) } },
                        onLogout: { appState.logout() }
                    )
                } else if vm.libraries.isEmpty {
                    EmptyState(
                        icon: "books.vertical",
                        title: "No libraries yet",
                        subtitle: "Create a library to start cataloging your collection.",
                        action: { showCreate = true },
                        actionLabel: "New Library"
                    )
                } else {
                    List(vm.libraries, id: \.clientKey) { library in
                        LibraryRow(
                            library: library,
                            multiServer: appState.accounts.count > 1,
                            rowState: vm.libraryStates[library.clientKey] ?? .online
                        )
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(library) }
                            .swipeActions(edge: .leading) {
                                Button { libraryToEdit = library } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Libraries")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showScanner = true } label: { Image(systemName: "barcode.viewfinder") }
                        .disabled(vm.isUnreachable)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { showCreate = true } label: {
                            Label("New Library", systemImage: "plus")
                        }
                        .disabled(vm.isOffline || vm.isUnreachable)
                        Button { showSettings = true } label: {
                            Label("Manage Servers", systemImage: "server.rack")
                        }
                    } label: {
                        Image(systemName: "person.circle")
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                CreateLibrarySheet { newLib in vm.appendLibrary(newLib) }
            }
            .sheet(item: $libraryToEdit) { lib in
                EditLibrarySheet(library: lib) { updated in vm.updateLibrary(updated) }
            }
            .fullScreenCover(isPresented: $showScanner) {
                ScanFlow(libraries: vm.libraries) {
                    showScanner = false
                    Task { await vm.load(appState: appState) }
                }
            }
            .sheet(isPresented: $showSettings) {
                AccountsSettingsSheet()
            }
            .task { await vm.load(appState: appState) }
            .refreshable { await vm.load(appState: appState) }
            .onChange(of: vm.isOffline) { _, v in appState.isOffline = v }
            .onChange(of: vm.isUnreachable) { _, v in if v { appState.isOffline = false } }
            .alert("Error", isPresented: Binding(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
                Button("OK") { vm.error = nil }
            } message: { Text(vm.error ?? "") }
        }
    }
}

// MARK: - Library Row

private struct LibraryRow: View {
    let library: Library
    let multiServer: Bool
    let rowState: LibraryRowState
    private let offlineStore = LibraryOfflineStore.shared

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10)
                .fill(.tint.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "books.vertical.fill")
                        .foregroundStyle(.tint)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(library.name).font(.headline)
                if !library.description.isEmpty {
                    Text(library.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if multiServer && !library.serverName.isEmpty {
                        Text(library.serverName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                } else if multiServer && !library.serverName.isEmpty {
                    Text(library.serverName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                statusLine
            }
            Spacer()
            HStack(spacing: 8) {
                statusIcon
                if library.isPublic {
                    Image(systemName: "globe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch rowState {
        case .online:
            if let state = offlineStore.bookCacheStates[library.clientKey] {
                switch state {
                case .syncing(let progress):
                    VStack(alignment: .leading, spacing: 2) {
                        ProgressView(value: progress)
                            .tint(Color.accentColor)
                            .frame(maxWidth: 180)
                        Text("Caching books…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                case .cached(let count):
                    Text("\(count) book\(count == 1 ? "" : "s") cached")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                case .notCached:
                    EmptyView()
                }
            }
        case .offlineCached:
            if case .cached(let count) = offlineStore.bookCacheStates[library.clientKey] {
                Text("Offline · \(count) book\(count == 1 ? "" : "s") cached")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
                Text("Offline · cached")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        case .offline:
            Text("Offline")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch rowState {
        case .online:
            if let state = offlineStore.bookCacheStates[library.clientKey] {
                switch state {
                case .syncing:
                    ProgressView().scaleEffect(0.75)
                case .cached:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                case .notCached:
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }
        case .offlineCached, .offline:
            Image(systemName: "wifi.slash")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

// MARK: - Create Sheet

private struct CreateLibrarySheet: View {
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

// MARK: - Edit Sheet

private struct EditLibrarySheet: View {
    let library: Library
    let onSaved: (Library) -> Void
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var description: String
    @State private var isPublic: Bool
    @State private var keepOffline: Bool
    @State private var isSaving = false
    @State private var error: String?

    private let offlineStore = LibraryOfflineStore.shared

    init(library: Library, onSaved: @escaping (Library) -> Void) {
        self.library = library
        self.onSaved = onSaved
        _name        = State(initialValue: library.name)
        _description = State(initialValue: library.description)
        _isPublic    = State(initialValue: library.isPublic)
        _keepOffline = State(initialValue: LibraryOfflineStore.shared.isEnabled(for: library.clientKey))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Library Details") {
                    TextField("Name", text: $name)
                    TextField("Description (optional)", text: $description)
                    Toggle("Public library", isOn: $isPublic)
                }
                Section {
                    Toggle(isOn: $keepOffline) {
                        Label("Keep offline", systemImage: "arrow.down.circle")
                    }
                } footer: {
                    Text("Cache this library so it's available when the server is unreachable.")
                }
                if let err = error {
                    Section { Text(err).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle("Edit Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        isSaving = true; error = nil; defer { isSaving = false }
        do {
            // Hit the library's own server, not whichever account is currently
            // "active" — otherwise edits silently go to the wrong server and
            // (with duplicate UUIDs) corrupt the list.
            let client = appState.makeClient(serverURL: library.serverURL)
            var updated = try await LibraryService(client: client)
                .update(libraryId: library.id, name: name, description: description, isPublic: isPublic)
            updated.serverURL  = library.serverURL
            updated.serverName = library.serverName
            offlineStore.setEnabled(keepOffline, for: updated.clientKey)
            if keepOffline {
                offlineStore.cacheLibrary(updated)
                Task { await offlineStore.syncBooks(for: updated, client: client) }
            }
            onSaved(updated); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Server Unreachable

struct ServerUnreachableView: View {
    let onRetry: () -> Void
    let onLogout: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "wifi.slash")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Server Unreachable")
                    .font(.title2.bold())
                Text("Couldn't connect to your Librarium server.\nCheck that it's running and your network is reachable.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 12) {
                Button(action: onRetry) {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: 240)
                }
                .buttonStyle(.borderedProminent)

                Button(action: onLogout) {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: 240)
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

