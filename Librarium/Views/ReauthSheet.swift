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
            ScrollView {
                VStack(spacing: 24) {
                    header
                    fields
                }
                .padding()
            }
            .contentShape(Rectangle())
            .onTapGesture { focusedField = nil }
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
    }

    private var fields: some View {
        VStack(spacing: 12) {
            TextField("Username or email", text: $identifier)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
                .focused($focusedField, equals: .identifier)
                .onSubmit { focusedField = .password }
                .submitLabel(.next)
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

            SecureField("Password", text: $password)
                .textContentType(.password)
                .focused($focusedField, equals: .password)
                .onSubmit { signIn() }
                .submitLabel(.go)
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            Button(action: signIn) {
                Group {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Sign In").fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .opacity(canSubmit ? 1 : 0.4)
            }
            .disabled(!canSubmit)
        }
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
