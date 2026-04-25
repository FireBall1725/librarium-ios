import SwiftUI

@Observable
private final class SeriesListViewModel {
    var series: [Series] = []
    var isLoading = false
    var error: String?
    var showAdd = false
    var searchText = ""

    var filtered: [Series] {
        guard !searchText.isEmpty else { return series }
        return series.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    func load(client: APIClient, libraryId: String) async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do { series = try await SeriesService(client: client).list(libraryId: libraryId) }
        catch { self.error = error.localizedDescription }
    }
}

struct SeriesListView: View {
    let library: Library
    @Environment(AppState.self) private var appState
    @State private var vm = SeriesListViewModel()
    @State private var selectedSeries: Series?

    var body: some View {
        Group {
            if appState.isOffline {
                EmptyState(icon: "wifi.slash", title: "Offline",
                           subtitle: "Series data isn't cached. Connect to your server to browse series.")
            } else if vm.isLoading && vm.series.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.filtered.isEmpty {
                EmptyState(icon: "list.number", title: "No series",
                           subtitle: "Create a series to group related books.",
                           action: { vm.showAdd = true }, actionLabel: "Add Series")
            } else {
                List(vm.filtered) { s in
                    Button { selectedSeries = s } label: { SeriesRow(series: s) }
                        .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .searchable(text: $vm.searchText, prompt: "Search series")
            }
        }
        .navigationTitle("Series")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { LibraryBackButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button { vm.showAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add series")
            }
        }
        .sheet(isPresented: $vm.showAdd) {
            AddEditSeriesSheet(library: library) { newSeries in
                vm.series.append(newSeries)
            }
        }
        .sheet(item: $selectedSeries) { s in
            SeriesDetailSheet(library: library, series: s) {
                Task { await vm.load(client: appState.makeClient(), libraryId: library.id) }
            }
        }
        .task { if !appState.isOffline { await vm.load(client: appState.makeClient(), libraryId: library.id) } }
        .refreshable { if !appState.isOffline { await vm.load(client: appState.makeClient(), libraryId: library.id) } }
        .alert("Error", isPresented: Binding(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("OK") { vm.error = nil }
        } message: { Text(vm.error ?? "") }
    }
}

private struct SeriesRow: View {
    let series: Series
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(series.name).font(.headline)
            HStack(spacing: 6) {
                Text("\(series.bookCount) book\(series.bookCount == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
                if let total = series.totalCount {
                    Text("/ \(total) total").font(.caption).foregroundStyle(.secondary)
                }
                if !series.status.isEmpty {
                    Text("·").foregroundStyle(.tertiary).font(.caption)
                    Text(series.status.capitalized).font(.caption).foregroundStyle(.secondary)
                }
            }
            if !series.tags.isEmpty {
                HStack(spacing: 4) { ForEach(series.tags) { TagPill(tag: $0) } }
            }
        }
        .padding(.vertical, 4)
    }
}
