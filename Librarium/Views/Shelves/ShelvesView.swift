import SwiftUI

@Observable
private final class ShelvesViewModel {
    var shelves: [Shelf] = []
    var isLoading = false
    var error: String?

    func load(client: APIClient, libraryId: String) async {
        isLoading = true; error = nil; defer { isLoading = false }
        do { shelves = try await ShelfService(client: client).list(libraryId: libraryId) }
        catch { self.error = error.localizedDescription }
    }
}

struct ShelvesView: View {
    let library: Library
    @Environment(AppState.self) private var appState
    @State private var vm = ShelvesViewModel()
    @State private var showAdd = false
    @State private var selectedShelf: Shelf?

    var body: some View {
        Group {
            if appState.isOffline {
                EmptyState(icon: "wifi.slash", title: "Offline",
                           subtitle: "Shelf data isn't cached. Connect to your server to browse shelves.")
            } else if vm.isLoading && vm.shelves.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.shelves.isEmpty {
                EmptyState(icon: "square.stack", title: "No shelves",
                           subtitle: "Create a shelf to organize your books.",
                           action: { showAdd = true }, actionLabel: "Add Shelf")
            } else {
                List(vm.shelves) { shelf in
                    Button { selectedShelf = shelf } label: { ShelfRow(shelf: shelf) }
                        .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Shelves")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { LibraryBackButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add shelf")
            }
        }
        .sheet(isPresented: $showAdd) {
            AddEditShelfSheet(library: library) { _ in
                Task { await vm.load(client: appState.makeClient(), libraryId: library.id) }
            }
        }
        .sheet(item: $selectedShelf) { shelf in
            ShelfDetailSheet(library: library, shelf: shelf) {
                Task { await vm.load(client: appState.makeClient(), libraryId: library.id) }
            }
        }
        .task { if !appState.isOffline { await vm.load(client: appState.makeClient(), libraryId: library.id) } }
        .refreshable { if !appState.isOffline { await vm.load(client: appState.makeClient(), libraryId: library.id) } }
    }
}

struct ShelfRow: View {
    let shelf: Shelf
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color(hex: shelf.color).opacity(0.15)).frame(width: 40, height: 40)
                Text(shelf.icon.isEmpty ? "📚" : shelf.icon).font(.title3)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(shelf.name).font(.headline)
                Text("\(shelf.bookCount) book\(shelf.bookCount == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
