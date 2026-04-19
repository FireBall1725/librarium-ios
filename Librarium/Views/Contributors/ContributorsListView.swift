import SwiftUI

@Observable
final class ContributorsViewModel {
    var items: [LibraryContributor] = []
    var total = 0
    var page = 1
    let perPage = 50
    var isLoading = false
    var isLoadingMore = false
    var error: String?
    var searchText = ""

    var hasMore: Bool { items.count < total }

    func load(client: APIClient, libraryId: String) async {
        isLoading = true; error = nil; page = 1
        defer { isLoading = false }
        do {
            let paged = try await ContributorService(client: client).listForLibrary(
                libraryId: libraryId, query: searchText, page: 1, perPage: perPage)
            items = paged.items
            total = paged.total
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadMore(client: APIClient, libraryId: String) async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        page += 1
        do {
            let paged = try await ContributorService(client: client).listForLibrary(
                libraryId: libraryId, query: searchText, page: page, perPage: perPage)
            items.append(contentsOf: paged.items)
            total = paged.total
        } catch {
            page -= 1
            self.error = error.localizedDescription
        }
    }
}

struct ContributorsListView: View {
    let library: Library

    @Environment(AppState.self) private var appState
    @State private var vm = ContributorsViewModel()
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        Group {
            if vm.isLoading && vm.items.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = vm.error, vm.items.isEmpty {
                ContentUnavailableView("Couldn't load contributors", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if vm.items.isEmpty {
                ContentUnavailableView(
                    vm.searchText.isEmpty ? "No contributors yet" : "No matches",
                    systemImage: "person.2",
                    description: Text(vm.searchText.isEmpty
                        ? "Contributors appear here as you add books."
                        : "Try a different name.")
                )
            } else {
                List {
                    ForEach(vm.items) { contributor in
                        NavigationLink(destination: ContributorDetailView(library: library, contributorId: contributor.id)) {
                            ContributorRow(contributor: contributor, serverURL: library.serverURL)
                        }
                        .onAppear {
                            if contributor.id == vm.items.last?.id {
                                Task { await vm.loadMore(client: appState.makeClient(), libraryId: library.id) }
                            }
                        }
                    }
                    if vm.isLoadingMore {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Contributors")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $vm.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search contributors")
        .task {
            if vm.items.isEmpty {
                await vm.load(client: appState.makeClient(), libraryId: library.id)
            }
        }
        .refreshable {
            await vm.load(client: appState.makeClient(), libraryId: library.id)
        }
        .onChange(of: vm.searchText) { _, _ in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await vm.load(client: appState.makeClient(), libraryId: library.id)
            }
        }
    }
}

// MARK: - Row

private struct ContributorRow: View {
    let contributor: LibraryContributor
    let serverURL: String

    private var photoURL: URL? {
        guard let path = contributor.photoUrl, !path.isEmpty, !serverURL.isEmpty else { return nil }
        return URL(string: serverURL + path)
    }

    var body: some View {
        HStack(spacing: 12) {
            ContributorPhotoImage(url: photoURL, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(contributor.name).font(.headline).lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(contributor.bookCount) \(contributor.bookCount == 1 ? "book" : "books")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let nat = contributor.nationality, !nat.isEmpty {
                        Text("·").font(.caption).foregroundStyle(.tertiary)
                        Text(nat).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
