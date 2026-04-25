import SwiftUI

struct MembersView: View {
    let library: Library
    @Environment(AppState.self) private var appState
    @Environment(\.libraryBack) private var onBack
    @State private var members: [LibraryMember] = []
    @State private var isLoading = false
    @State private var showAdd = false
    @State private var error: String?

    var body: some View {
        Group {
            if appState.isOffline {
                EmptyState(icon: "wifi.slash", title: "Offline",
                           subtitle: "Member data isn't cached. Connect to your server to view members.")
            } else if isLoading && members.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if members.isEmpty {
                EmptyState(icon: "person.2", title: "No members",
                           subtitle: "Add members to give them access to this library.")
            } else {
                List(members) { member in
                    MemberRow(member: member)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task {
                                    try? await MemberService(client: appState.makeClient())
                                        .remove(libraryId: library.id, userId: member.userId)
                                    members.removeAll { $0.userId == member.userId }
                                }
                            } label: { Label("Remove", systemImage: "person.badge.minus") }
                        }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Members")
        .toolbar {
            if let onBack {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onBack) {
                        HStack(spacing: 4) { Image(systemName: "chevron.left"); Text("Libraries") }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "person.badge.plus") }
                    .accessibilityLabel("Add member")
            }
        }
        .sheet(isPresented: $showAdd) {
            AddMemberSheet(library: library) {
                Task { await load() }
            }
        }
        .task { if !appState.isOffline { await load() } }
        .refreshable { if !appState.isOffline { await load() } }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func load() async {
        isLoading = true; defer { isLoading = false }
        do { members = try await MemberService(client: appState.makeClient()).list(libraryId: library.id) }
        catch { self.error = error.localizedDescription }
    }
}

private struct MemberRow: View {
    let member: LibraryMember
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName.isEmpty ? member.username : member.displayName)
                    .font(.headline)
                Text(member.email).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(member.role.replacingOccurrences(of: "library_", with: "").capitalized)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.tint.opacity(0.1)).foregroundStyle(.tint)
                .clipShape(Capsule())
        }
    }
}
