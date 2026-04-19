import SwiftUI

struct AddServerView: View {
    let isFirstTime: Bool
    var onComplete: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var serverURL = ""
    @State private var serverName = ""
    @State private var lastAutoName = ""   // last hostname we injected; lets us detect manual edits
    @State private var identifier = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    // Setup-mode state — flipped on when a probe of /setup/status returns initialized=false.
    @State private var setupMode = false
    @State private var setupEmail = ""
    @State private var setupDisplayName = ""
    @State private var setupConfirmPassword = ""

    enum Field { case url, name, identifier, email, displayName, password, confirm }

    var body: some View {
        if isFirstTime {
            firstTimeContent
        } else {
            NavigationStack {
                formContent
                    .navigationTitle(setupMode ? "Set Up Server" : "Add Server")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                        }
                    }
            }
        }
    }

    private var firstTimeContent: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer().frame(height: 40)

                VStack(spacing: 8) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.tint)
                    Text("Librarium")
                        .font(.largeTitle.bold())
                    Text(setupMode
                         ? "This server hasn't been set up yet — create the first admin account."
                         : "Connect to your server to get started.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                fields
                    .padding(.horizontal)

                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focusedField = nil }
    }

    private var formContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                if setupMode {
                    Text("This server hasn't been set up yet — create the first admin account.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                fields.padding()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focusedField = nil }
    }

    private var fields: some View {
        VStack(spacing: 12) {
            TextField("Server URL (e.g. https://librarium.example.com)", text: $serverURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.URL)
                .focused($focusedField, equals: .url)
                .onSubmit { focusedField = .name }
                .submitLabel(.next)
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: serverURL) { _, val in
                    let auto = hostname(from: val)
                    if serverName.isEmpty || serverName == lastAutoName {
                        serverName = auto
                        lastAutoName = auto
                    }
                    // URL edits invalidate any prior setup-mode detection.
                    if setupMode { setupMode = false }
                }

            TextField("Server name (optional)", text: $serverName)
                .textInputAutocapitalization(.words)
                .focused($focusedField, equals: .name)
                .onSubmit { focusedField = .identifier }
                .submitLabel(.next)
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

            TextField(setupMode ? "Username" : "Username or email", text: $identifier)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
                .focused($focusedField, equals: .identifier)
                .onSubmit { focusedField = setupMode ? .email : .password }
                .submitLabel(.next)
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

            if setupMode {
                TextField("Email", text: $setupEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.emailAddress)
                    .focused($focusedField, equals: .email)
                    .onSubmit { focusedField = .displayName }
                    .submitLabel(.next)
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

                TextField("Display name (optional)", text: $setupDisplayName)
                    .textContentType(.name)
                    .focused($focusedField, equals: .displayName)
                    .onSubmit { focusedField = .password }
                    .submitLabel(.next)
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }

            SecureField(setupMode ? "Password (min 8 characters)" : "Password", text: $password)
                .textContentType(setupMode ? .newPassword : .password)
                .focused($focusedField, equals: .password)
                .onSubmit { setupMode ? (focusedField = .confirm) : connect() }
                .submitLabel(setupMode ? .next : .go)
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

            if setupMode {
                SecureField("Confirm password", text: $setupConfirmPassword)
                    .textContentType(.newPassword)
                    .focused($focusedField, equals: .confirm)
                    .onSubmit { connect() }
                    .submitLabel(.go)
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            Button(action: connect) {
                Group {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text(buttonLabel).fontWeight(.semibold)
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

    private var buttonLabel: String {
        if setupMode { return "Create admin & connect" }
        return isFirstTime ? "Connect" : "Add Server"
    }

    private var canSubmit: Bool {
        let urlOK = !serverURL.trimmingCharacters(in: .whitespaces).isEmpty
        let idOK = !identifier.trimmingCharacters(in: .whitespaces).isEmpty
        let pwOK = !password.isEmpty
        if isLoading || !urlOK || !idOK || !pwOK { return false }
        if setupMode {
            return !setupEmail.trimmingCharacters(in: .whitespaces).isEmpty
                && !setupConfirmPassword.isEmpty
        }
        return true
    }

    private func connect() {
        guard canSubmit else { return }
        focusedField = nil
        isLoading = true
        errorMessage = nil

        Task {
            defer { isLoading = false }
            let url = serverURL.trimmingCharacters(in: .whitespaces)
            let client = APIClient(baseURL: url)

            if setupMode {
                await performBootstrap(client: client, url: url)
            } else {
                await performLoginOrProbe(client: client, url: url)
            }
        }
    }

    private func performLoginOrProbe(client: APIClient, url: String) async {
        // Probe setup status first; a fresh server (no users) requires the bootstrap
        // flow instead of login. If the probe fails, fall through to login and let
        // that surface the real error.
        if let status = try? await SetupService(client: client).status(), !status.initialized {
            setupMode = true
            errorMessage = nil
            // Prefill display name from identifier if the user hasn't typed one.
            if setupDisplayName.isEmpty {
                setupDisplayName = identifier.trimmingCharacters(in: .whitespaces)
            }
            focusedField = .email
            return
        }

        do {
            let tokens = try await AuthService(client: client).login(
                identifier: identifier.trimmingCharacters(in: .whitespaces),
                password: password
            )
            finishConnection(url: url, tokens: tokens)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performBootstrap(client: APIClient, url: String) async {
        if password.count < 8 {
            errorMessage = "Password must be at least 8 characters."
            return
        }
        if password != setupConfirmPassword {
            errorMessage = "Passwords do not match."
            return
        }
        let username = identifier.trimmingCharacters(in: .whitespaces)
        let email = setupEmail.trimmingCharacters(in: .whitespaces)
        let displayName = setupDisplayName.trimmingCharacters(in: .whitespaces).isEmpty
            ? username
            : setupDisplayName.trimmingCharacters(in: .whitespaces)
        do {
            let tokens = try await SetupService(client: client).bootstrapAdmin(
                BootstrapAdminRequest(
                    username: username,
                    email: email,
                    displayName: displayName,
                    password: password
                )
            )
            finishConnection(url: url, tokens: tokens)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finishConnection(url: String, tokens: AuthTokens) {
        let name = serverName.trimmingCharacters(in: .whitespaces).isEmpty
            ? ServerAccount.defaultName(for: url)
            : serverName.trimmingCharacters(in: .whitespaces)
        let account = ServerAccount(
            id: UUID(),
            name: name,
            url: url,
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            user: tokens.user
        )
        appState.addAccount(account)
        onComplete()
        if !isFirstTime { dismiss() }
    }

    private func hostname(from urlString: String) -> String {
        ServerAccount.defaultName(for: urlString)
    }
}
