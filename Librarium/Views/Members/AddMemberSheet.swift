import SwiftUI

struct AddMemberSheet: View {
    let library: Library
    let onAdded: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var results: [ContributorResult] = []
    @State private var selected: ContributorResult?
    @State private var role = "library_viewer"
    @State private var isAdding = false
    @State private var error: String?
    @State private var searchTask: Task<Void, Never>?

    let roles = ["library_viewer", "library_editor", "library_owner"]

    var body: some View {
        NavigationStack {
            Form {
                Section("User") {
                    if let user = selected {
                        HStack {
                            Text(user.name)
                            Spacer()
                            Button { selected = nil; search = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        TextField("Search users…", text: $search)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: search) { _, q in
                                searchTask?.cancel()
                                guard !q.isEmpty else { results = []; return }
                                searchTask = Task {
                                    try? await Task.sleep(for: .milliseconds(300))
                                    guard !Task.isCancelled else { return }
                                    results = (try? await MemberService(client: appState.makeClient()).searchUsers(query: q)) ?? []
                                }
                            }
                        ForEach(results) { user in
                            Button { selected = user; search = user.name; results = [] } label: {
                                Text(user.name)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Section("Role") {
                    Picker("Role", selection: $role) {
                        ForEach(roles, id: \.self) { r in
                            Text(r.replacingOccurrences(of: "library_", with: "").capitalized).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                if let err = error {
                    Section { Text(err).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle("Add Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isAdding ? "Adding…" : "Add") {
                        Task { await addMember() }
                    }
                    .disabled(selected == nil || isAdding)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func addMember() async {
        guard let user = selected else { return }
        isAdding = true; defer { isAdding = false }
        do {
            try await MemberService(client: appState.makeClient()).add(libraryId: library.id, userId: user.id, roleId: role)
            onAdded(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
