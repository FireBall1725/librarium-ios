import SwiftUI

/// Sheet shown when an existing server's tokens have been blanked
/// (refresh rejected, Keychain hiccup, etc). Re-uses the server's
/// stored URL and name; the user only re-enters credentials, and on
/// success the account's tokens are replaced in place — the server
/// record itself never goes away.
struct ReauthSheet: View {
    let account: ServerAccount

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var identifier: String = ""
    @State private var password: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    enum Field { case identifier, password }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    header
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Section("Sign in") {
                    TextField("Username or email", text: $identifier)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .focused($focusedField, equals: .identifier)
                        .onSubmit { focusedField = .password }
                        .submitLabel(.next)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .onSubmit { signIn() }
                        .submitLabel(.go)
                }

                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button(action: signIn) {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                            } else {
                                Text("Sign In").fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canSubmit)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }
            .navigationTitle("Sign In Again")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                // Pre-fill from the stored user when we have one — usually
                // username; email also works against the login endpoint.
                if identifier.isEmpty, !account.user.username.isEmpty {
                    identifier = account.user.username
                }
                focusedField = identifier.isEmpty ? .identifier : .password
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(account.name)
                .font(.title2.bold())
            Text(account.url)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("Your session expired. Sign back in to keep using this server.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var canSubmit: Bool {
        !isLoading
            && !identifier.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
    }

    private func signIn() {
        guard canSubmit else { return }
        focusedField = nil
        isLoading = true
        errorMessage = nil

        Task {
            defer { isLoading = false }
            let client = APIClient(baseURL: account.url)
            do {
                let tokens = try await AuthService(client: client).login(
                    identifier: identifier.trimmingCharacters(in: .whitespaces),
                    password: password
                )
                appState.updateTokens(for: account.id, tokens: tokens)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
