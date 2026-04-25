import SwiftUI

struct AdminUsersView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var users: [AdminUser] = []
    @State private var isLoading = false
    @State private var showAdd = false
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading && users.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(users) { user in
                    AdminUserRow(user: user)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                guard user.id != appState.currentUser?.id else { return }
                                Task {
                                    try? await AdminService(client: appState.makeClient()).deleteUser(userId: user.id)
                                    users.removeAll { $0.id == user.id }
                                }
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                Task {
                                    if let updated = try? await AdminService(client: appState.makeClient())
                                        .setActive(userId: user.id, isActive: !user.isActive) {
                                        if let i = users.firstIndex(where: { $0.id == user.id }) { users[i] = updated }
                                    }
                                }
                            } label: {
                                Label(user.isActive ? "Disable" : "Enable",
                                      systemImage: user.isActive ? "person.slash" : "person.fill.checkmark")
                            }
                            .tint(user.isActive ? .orange : .green)
                        }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Users")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    NavigationLink(destination: AdminSettingsView()) {
                        Image(systemName: "gear")
                    }
                    .accessibilityLabel("Admin settings")
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add user")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddAdminUserSheet { _ in Task { await load() } }
        }
        .task { await load() }
        .refreshable { await load() }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func load() async {
        isLoading = true; defer { isLoading = false }
        do { users = (try await AdminService(client: appState.makeClient()).users()).items }
        catch { self.error = error.localizedDescription }
    }
}

private struct AdminUserRow: View {
    let user: AdminUser
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(user.username).font(.headline)
                    if user.isInstanceAdmin {
                        Image(systemName: "shield.fill").font(.caption2).foregroundStyle(.tint)
                    }
                    if !user.isActive {
                        Text("Inactive").font(.caption2.weight(.medium))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(.secondary.opacity(0.2)).foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }
                }
                Text(user.email).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct AddAdminUserSheet: View {
    let onCreated: (AdminUser) -> Void
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var email = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Username", text: $username).autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("Email", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    TextField("Display name (optional)", text: $displayName)
                    SecureField("Password", text: $password)
                }
                if let err = error { Section { Text(err).foregroundStyle(.red).font(.caption) } }
            }
            .navigationTitle("New User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Creating…" : "Create") { Task { await create() } }
                        .disabled(username.isEmpty || email.isEmpty || password.isEmpty || isSaving)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func create() async {
        isSaving = true; error = nil; defer { isSaving = false }
        do {
            let user = try await AdminService(client: appState.makeClient())
                .createUser(username: username, email: email, displayName: displayName, password: password)
            onCreated(user); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
