import SwiftUI

struct ProfileView: View {
    let account: ServerAccount

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    // Server rename
    @State private var serverName: String

    // Profile
    @State private var displayName: String
    @State private var email: String
    @State private var profileSaving = false

    // Password
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var passwordSaving = false

    // Feedback
    @State private var profileMessage: Message?
    @State private var passwordMessage: Message?

    // Redesign feature flag — long-press the version footer to flip.
    @AppStorage(RedesignFlag.key) private var redesignEnabled = false
    @State private var redesignToastVisible = false

    struct Message {
        let text: String
        let success: Bool
    }

    init(account: ServerAccount) {
        self.account = account
        _serverName = State(initialValue: account.name)
        _displayName = State(initialValue: account.user.displayName)
        _email = State(initialValue: account.user.email)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("URL", value: account.url)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                LabeledContent("Username", value: account.user.username)
                if account.user.isInstanceAdmin {
                    Label("Instance admin", systemImage: "key.fill")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }

                if appState.primaryAccountID == account.id {
                    Label("Primary server", systemImage: "star.fill")
                        .foregroundStyle(.indigo)
                        .font(.footnote)
                } else {
                    Button {
                        appState.setPrimaryAccount(id: account.id)
                    } label: {
                        Label("Make primary server", systemImage: "star")
                    }
                }
            } header: {
                Text("Server")
            } footer: {
                if appState.primaryAccountID == account.id {
                    Text("This server is used for the welcome screen and for quick-scan metadata lookups.")
                }
            }

            Section {
                TextField("Server name", text: $serverName)
                    .autocorrectionDisabled()
                    .onSubmit(commitServerName)
                Button("Save name") { commitServerName() }
                    .disabled(!serverNameChanged)
            } header: {
                Text("Rename this server")
            } footer: {
                Text("Shown in the account list and library picker.")
            }

            Section {
                TextField("Display name", text: $displayName)
                    .textContentType(.name)
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.emailAddress)

                Button {
                    Task { await saveProfile() }
                } label: {
                    HStack {
                        Text("Save profile")
                        if profileSaving {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!profileChanged || profileSaving || displayName.trimmingCharacters(in: .whitespaces).isEmpty || email.trimmingCharacters(in: .whitespaces).isEmpty)

                if let msg = profileMessage {
                    Text(msg.text)
                        .font(.footnote)
                        .foregroundStyle(msg.success ? .green : .red)
                }
            } header: {
                Text("Profile")
            }

            Section {
                SecureField("Current password", text: $currentPassword)
                    .textContentType(.password)
                SecureField("New password (min 8)", text: $newPassword)
                    .textContentType(.newPassword)
                SecureField("Confirm new password", text: $confirmPassword)
                    .textContentType(.newPassword)

                Button {
                    Task { await savePassword() }
                } label: {
                    HStack {
                        Text("Change password")
                        if passwordSaving {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(passwordSaving || currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty)

                if let msg = passwordMessage {
                    Text(msg.text)
                        .font(.footnote)
                        .foregroundStyle(msg.success ? .green : .red)
                }
            } header: {
                Text("Security")
            }

            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(versionString)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 1.0) {
                    redesignEnabled.toggle()
                    redesignToastVisible = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            } header: {
                Text("About")
            } footer: {
                if redesignEnabled {
                    Label("Redesign preview enabled — long-press version to disable", systemImage: "sparkles")
                        .foregroundStyle(.indigo)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if redesignToastVisible {
                redesignToast
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        withAnimation { redesignToastVisible = false }
                    }
            }
        }
        .animation(.easeOut(duration: 0.2), value: redesignToastVisible)
    }

    /// "26.4.4 (build 1138)" — pulled from Info.plist at runtime so it
    /// stays in sync with the release workflow's MARKETING_VERSION bumps.
    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let marketing = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info?["CFBundleVersion"] as? String) ?? "?"
        return "\(marketing) (build \(build))"
    }

    @ViewBuilder
    private var redesignToast: some View {
        let label = redesignEnabled ? "Redesign preview ON" : "Redesign preview OFF"
        let icon = redesignEnabled ? "sparkles" : "circle.slash"
        Label(label, systemImage: icon)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.secondary.opacity(0.2)))
    }

    // MARK: - Derived

    private var serverNameChanged: Bool {
        let trimmed = serverName.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed != account.name
    }

    private var profileChanged: Bool {
        let d = displayName.trimmingCharacters(in: .whitespaces)
        let e = email.trimmingCharacters(in: .whitespaces)
        return d != account.user.displayName || e != account.user.email
    }

    // MARK: - Actions

    private func commitServerName() {
        let trimmed = serverName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != account.name else { return }
        appState.updateAccountName(trimmed, for: account.id)
    }

    private func saveProfile() async {
        let d = displayName.trimmingCharacters(in: .whitespaces)
        let e = email.trimmingCharacters(in: .whitespaces)
        guard !d.isEmpty, !e.isEmpty else { return }
        profileSaving = true
        defer { profileSaving = false }
        let client = appState.makeClient(serverURL: account.url)
        do {
            let updated = try await UserService(client: client).updateProfile(displayName: d, email: e)
            appState.updateAccountUser(updated, for: account.id)
            profileMessage = Message(text: "Profile updated.", success: true)
        } catch {
            profileMessage = Message(text: error.localizedDescription, success: false)
        }
    }

    private func savePassword() async {
        if newPassword.count < 8 {
            passwordMessage = Message(text: "New password must be at least 8 characters.", success: false)
            return
        }
        if newPassword != confirmPassword {
            passwordMessage = Message(text: "New passwords do not match.", success: false)
            return
        }
        passwordSaving = true
        defer { passwordSaving = false }
        let client = appState.makeClient(serverURL: account.url)
        do {
            try await UserService(client: client).updatePassword(current: currentPassword, new: newPassword)
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
            passwordMessage = Message(text: "Password changed.", success: true)
        } catch {
            passwordMessage = Message(text: error.localizedDescription, success: false)
        }
    }
}
