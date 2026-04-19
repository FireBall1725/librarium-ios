import SwiftUI

struct SeriesDetailSheet: View {
    let library: Library
    let series: Series
    let onUpdate: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [SeriesEntry] = []
    @State private var isLoading = true
    @State private var showEdit = false
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if !series.description.isEmpty {
                        Text(series.description).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let year = series.publicationYear {
                        LabeledContent("First published", value: "\(year)")
                    }
                    if !series.status.isEmpty {
                        LabeledContent("Status", value: series.status.capitalized)
                    }
                    if let total = series.totalCount {
                        LabeledContent("Volumes", value: "\(series.bookCount) owned / \(total) total")
                    }
                    if !series.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack { ForEach(series.tags) { TagPill(tag: $0) } }
                        }
                    }
                }

                Section("Books in library") {
                    if isLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if entries.isEmpty {
                        Text("No books linked yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(entries.sorted { $0.position < $1.position }) { entry in
                            HStack {
                                Text(String(format: entry.position.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", entry.position))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 30, alignment: .trailing)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title).font(.subheadline)
                                    if let c = entry.contributors.first {
                                        Text(c.name).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(series.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showEdit = true } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(isPresented: $showEdit) {
                AddEditSeriesSheet(library: library, series: series) { _ in
                    onUpdate(); dismiss()
                }
            }
            .confirmationDialog("Delete \"\(series.name)\"?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        try? await SeriesService(client: appState.makeClient()).delete(libraryId: library.id, seriesId: series.id)
                        onUpdate(); dismiss()
                    }
                }
            }
            .task {
                entries = (try? await SeriesService(client: appState.makeClient()).books(libraryId: library.id, seriesId: series.id)) ?? []
                isLoading = false
            }
        }
    }
}
