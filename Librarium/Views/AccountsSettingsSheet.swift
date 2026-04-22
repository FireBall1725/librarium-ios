import SwiftUI

struct AccountsSettingsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showAddServer = false
    @State private var showSignOutConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(appState.accounts) { account in
                        NavigationLink(value: account.id) {
                            AccountRow(
                                account: account,
                                isPrimary: account.id == appState.primaryAccountID
                            )
                        }
                        .swipeActions(edge: .leading) {
                            if account.id != appState.primaryAccountID {
                                Button {
                                    appState.setPrimaryAccount(id: account.id)
                                } label: {
                                    Label("Primary", systemImage: "star.fill")
                                }
                                .tint(.indigo)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                appState.removeAccount(id: account.id)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                } footer: {
                    if appState.accounts.count > 1 {
                        Text("The primary server is used for the welcome screen and for quick-scan metadata lookups. Swipe right on a server to make it primary.")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Sign Out of All Servers")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Servers")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { accountID in
                if let account = appState.accounts.first(where: { $0.id == accountID }) {
                    ProfileView(account: account)
                } else {
                    // Account was removed while in detail view; pop back.
                    Color.clear.onAppear { /* handled by navigationDestination no-op */ }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddServer = true
                    } label: {
                        Label("Add Server", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showAddServer) {
                AddServerView(isFirstTime: false, onComplete: {})
            }
            .confirmationDialog(
                "Sign out of all servers?",
                isPresented: $showSignOutConfirm,
                titleVisibility: .visible
            ) {
                Button("Sign Out of All", role: .destructive) {
                    appState.logout()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You will be signed out of all connected servers.")
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Account Row

private struct AccountRow: View {
    let account: ServerAccount
    let isPrimary: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(account.name)
                        .font(.headline)
                    if isPrimary {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.indigo)
                            .accessibilityLabel("Primary server")
                    }
                }
                Text(account.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(account.user.displayName) · \(account.user.email)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
