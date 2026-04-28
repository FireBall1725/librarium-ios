import Foundation
import Observation

@Observable
final class AppState {

    // MARK: - Public state

    private(set) var accounts: [ServerAccount] = []
    var isAuthenticated: Bool { !accounts.isEmpty }
    var isOffline = false

    var currentUser: User? { primaryAccount?.user ?? accounts.first?.user }

    // MARK: - Primary account

    /// User-selected "home" server. Source of identity for the splash welcome
    /// and of metadata for global lookups like quick scan. Distinct from
    /// `activeAccount`, which tracks the library currently being viewed.
    private(set) var primaryAccountID: UUID?

    var primaryAccount: ServerAccount? {
        accounts.first(where: { $0.id == primaryAccountID }) ?? accounts.first
    }

    // MARK: - Active account

    private var activeAccountID: UUID?

    private var activeAccount: ServerAccount? {
        accounts.first(where: { $0.id == activeAccountID }) ?? accounts.first
    }

    /// The URL+name of the account `makeClient()` would hit. Used by flows that
    /// need to tag a freshly-fetched Library with server context before the next
    /// full list refresh re-injects it.
    var activeAccountContext: (url: String, name: String)? {
        activeAccount.map { ($0.url, $0.name) }
    }

    // MARK: - Init

    init() {
        migrateIfNeeded()
        loadAccounts()
        backfillPrimaryIfNeeded()
    }

    // MARK: - Account management

    func setActiveAccount(for library: Library) {
        if let match = accounts.first(where: { $0.url == library.serverURL }) {
            activeAccountID = match.id
        }
    }

    func setPrimaryAccount(id: UUID) {
        guard accounts.contains(where: { $0.id == id }) else { return }
        primaryAccountID = id
        savePrimary()
    }

    func addAccount(_ account: ServerAccount) {
        if let i = accounts.firstIndex(where: { $0.url == account.url }) {
            accounts[i] = account
        } else {
            accounts.append(account)
        }
        saveAccounts()
        if primaryAccountID == nil {
            primaryAccountID = account.id
            savePrimary()
        }
    }

    func updateAccountName(_ name: String, for id: UUID) {
        guard let i = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[i].name = name
        saveAccounts()
    }

    func updateAccountUser(_ user: User, for id: UUID) {
        guard let i = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[i].user = user
        saveAccounts()
    }

    func removeAccount(id: UUID) {
        let url = accounts.first(where: { $0.id == id })?.url
        KeychainService.shared.delete("access_\(id.uuidString)")
        KeychainService.shared.delete("refresh_\(id.uuidString)")
        accounts.removeAll { $0.id == id }
        if activeAccountID == id { activeAccountID = nil }
        if primaryAccountID == id {
            primaryAccountID = nil
            savePrimary()
        }
        saveAccounts()
        if let url {
            LibraryOfflineStore.shared.purgeLibraries(forServerURL: url)
        }
    }

    /// Blanks an account's tokens without removing the account. Used in place
    /// of `removeAccount` whenever the server (or our local Keychain) hands
    /// us a reason to believe the credentials are no longer valid — refresh
    /// rejected, refresh token missing, etc. The metadata stays so the UI
    /// can prompt for re-sign-in instead of silently bouncing the user back
    /// to "add server".
    func markNeedsReauth(id: UUID) {
        guard let i = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[i].accessToken = ""
        accounts[i].refreshToken = ""
        KeychainService.shared.delete("access_\(id.uuidString)")
        KeychainService.shared.delete("refresh_\(id.uuidString)")
        saveAccounts()
    }

    /// Refresh an existing account's tokens after the user has re-signed-in
    /// through the re-auth sheet. Mirrors `addAccount` but keyed by id so
    /// the server's URL, name, and primary-server flag stay intact.
    func updateTokens(for id: UUID, tokens: AuthTokens) {
        guard let i = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[i].accessToken = tokens.accessToken
        accounts[i].refreshToken = tokens.refreshToken
        accounts[i].user = tokens.user
        saveAccounts()
    }

    func logout() {
        let urls = accounts.map { $0.url }
        for account in accounts {
            KeychainService.shared.delete("access_\(account.id.uuidString)")
            KeychainService.shared.delete("refresh_\(account.id.uuidString)")
        }
        accounts = []
        activeAccountID = nil
        primaryAccountID = nil
        isOffline = false
        UserDefaults.standard.removeObject(forKey: "server_accounts")
        UserDefaults.standard.removeObject(forKey: "primary_account_id")
        for url in urls {
            LibraryOfflineStore.shared.purgeLibraries(forServerURL: url)
        }
    }

    // MARK: - Client factory

    func makeClient() -> APIClient {
        guard let account = activeAccount else {
            return APIClient(baseURL: "")
        }
        let client = APIClient(baseURL: account.url, token: account.accessToken)
        let accountID = account.id
        client.onUnauthorized = { [weak self] in
            guard let self else { return nil }
            let ok = await self.refreshToken(for: accountID)
            return ok ? self.accounts.first(where: { $0.id == accountID })?.accessToken : nil
        }
        return client
    }

    func makeClient(serverURL: String) -> APIClient {
        guard let account = accounts.first(where: { $0.url == serverURL }) else {
            return APIClient(baseURL: serverURL)
        }
        let client = APIClient(baseURL: account.url, token: account.accessToken)
        let accountID = account.id
        client.onUnauthorized = { [weak self] in
            guard let self else { return nil }
            let ok = await self.refreshToken(for: accountID)
            return ok ? self.accounts.first(where: { $0.id == accountID })?.accessToken : nil
        }
        return client
    }

    /// Client bound to the user-selected primary server — used for global
    /// lookups (e.g. ISBN metadata) that should not drift based on which
    /// library the user happens to be viewing.
    func makePrimaryClient() -> APIClient {
        guard let account = primaryAccount else {
            return APIClient(baseURL: "")
        }
        return makeClient(serverURL: account.url)
    }

    // MARK: - Token refresh

    /// Coalesces concurrent refresh attempts per account. Cold-launch fans out
    /// many requests in parallel; if all of them get 401 and each fires its own
    /// refresh, the second call presents an already-rotated token and the
    /// server treats it as token-reuse and revokes every active refresh token
    /// for the user — boots them out of every device. One coordinator, one
    /// in-flight task per account, every caller awaits the same outcome.
    private let refreshCoordinator = RefreshCoordinator()

    @discardableResult
    func refreshToken(for accountID: UUID) async -> Bool {
        guard let account = accounts.first(where: { $0.id == accountID }),
              !account.refreshToken.isEmpty else {
            // No refresh token to spend. Don't delete — keep the metadata and
            // mark the account as needing re-auth so the UI can prompt.
            markNeedsReauth(id: accountID)
            return false
        }
        let outcome = await refreshCoordinator.refresh(
            accountID: accountID,
            baseURL: account.url,
            refreshToken: account.refreshToken
        )
        switch outcome {
        case .success(let tokens):
            guard let i = accounts.firstIndex(where: { $0.id == accountID }) else { return false }
            accounts[i].accessToken = tokens.accessToken
            accounts[i].refreshToken = tokens.refreshToken
            accounts[i].user = tokens.user
            saveAccounts()
            return true
        case .rejected:
            // Refresh token was rejected — needs re-auth, but keep the
            // server. The user invariant is that only an explicit remove
            // wipes a server.
            markNeedsReauth(id: accountID)
            return false
        case .transient:
            // Network unreachable, 5xx, decode, timeout. Keep the account
            // untouched so the next try (next launch, pull-to-refresh) can
            // succeed.
            return false
        }
    }

    // MARK: - Persistence

    private func loadAccounts() {
        guard let data = UserDefaults.standard.data(forKey: "server_accounts"),
              let metas = try? JSONDecoder().decode([ServerAccountMeta].self, from: data) else { return }
        // Always materialise an account for every persisted metadata row, even
        // when the Keychain doesn't return tokens. Missing tokens mean the
        // account needs re-auth (`needsReauth == true`), not that the server
        // should silently disappear from the list. Previously this used
        // compactMap and dropped accounts whose Keychain tokens couldn't be
        // read, which manifested as "open app, briefly see library, bounced
        // to add-server" whenever the Keychain hiccupped.
        accounts = metas.map { meta in
            let access = KeychainService.shared.get("access_\(meta.id.uuidString)") ?? ""
            let refresh = KeychainService.shared.get("refresh_\(meta.id.uuidString)") ?? ""
            return ServerAccount(
                id: meta.id,
                name: meta.name,
                url: meta.url,
                accessToken: access,
                refreshToken: refresh,
                user: meta.user
            )
        }
        if let raw = UserDefaults.standard.string(forKey: "primary_account_id"),
           let id = UUID(uuidString: raw),
           accounts.contains(where: { $0.id == id }) {
            primaryAccountID = id
        }
    }

    private func saveAccounts() {
        let metas = accounts.map { ServerAccountMeta(id: $0.id, name: $0.name, url: $0.url, user: $0.user) }
        if let data = try? JSONEncoder().encode(metas) {
            UserDefaults.standard.set(data, forKey: "server_accounts")
        }
        // Empty token strings flag a needs-reauth account — don't write them
        // back to the Keychain. `markNeedsReauth` already deleted those entries
        // and we want them to stay gone until a real sign-in lands.
        for account in accounts {
            if account.accessToken.isEmpty {
                KeychainService.shared.delete("access_\(account.id.uuidString)")
            } else {
                KeychainService.shared.set(account.accessToken, forKey: "access_\(account.id.uuidString)")
            }
            if account.refreshToken.isEmpty {
                KeychainService.shared.delete("refresh_\(account.id.uuidString)")
            } else {
                KeychainService.shared.set(account.refreshToken, forKey: "refresh_\(account.id.uuidString)")
            }
        }
    }

    private func savePrimary() {
        if let id = primaryAccountID {
            UserDefaults.standard.set(id.uuidString, forKey: "primary_account_id")
        } else {
            UserDefaults.standard.removeObject(forKey: "primary_account_id")
        }
    }

    /// One-time promotion for installs that predate primary-account tracking:
    /// if any accounts exist but no primary has been chosen, pick the first
    /// one so the welcome banner and quick-scan target become deterministic.
    private func backfillPrimaryIfNeeded() {
        guard primaryAccountID == nil, let first = accounts.first else { return }
        primaryAccountID = first.id
        savePrimary()
    }

    private func migrateIfNeeded() {
        guard UserDefaults.standard.data(forKey: "server_accounts") == nil else { return }
        let url   = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        let at    = KeychainService.shared.get("access_token")
        let rt    = KeychainService.shared.get("refresh_token")
        guard !url.isEmpty, let accessToken = at, let refreshToken = rt else { return }

        var user = User(id: "", username: "", email: "", displayName: "", isInstanceAdmin: false)
        if let data = UserDefaults.standard.data(forKey: "current_user"),
           let decoded = try? JSONDecoder().decode(User.self, from: data) {
            user = decoded
        }

        let account = ServerAccount(
            id: UUID(),
            name: ServerAccount.defaultName(for: url),
            url: url,
            accessToken: accessToken,
            refreshToken: refreshToken,
            user: user
        )
        accounts = [account]
        saveAccounts()

        UserDefaults.standard.removeObject(forKey: "serverURL")
        UserDefaults.standard.removeObject(forKey: "current_user")
        UserDefaults.standard.removeObject(forKey: "token_expires_at")
        KeychainService.shared.delete("access_token")
        KeychainService.shared.delete("refresh_token")
    }
}

// MARK: - Refresh single-flight

private enum RefreshOutcome: Sendable {
    case success(AuthTokens)
    case rejected
    case transient
}

private actor RefreshCoordinator {
    private var inflight: [UUID: Task<RefreshOutcome, Never>] = [:]

    func refresh(
        accountID: UUID,
        baseURL: String,
        refreshToken: String
    ) async -> RefreshOutcome {
        if let existing = inflight[accountID] {
            return await existing.value
        }
        let task = Task<RefreshOutcome, Never> {
            do {
                let client = APIClient(baseURL: baseURL)
                let tokens: AuthTokens = try await client.post(
                    "/api/v1/auth/refresh",
                    body: ["refresh_token": refreshToken]
                )
                return .success(tokens)
            } catch APIError.unauthorized {
                return .rejected
            } catch let APIError.serverError(code, _) where code == 403 {
                return .rejected
            } catch {
                return .transient
            }
        }
        inflight[accountID] = task
        let result = await task.value
        inflight[accountID] = nil
        return result
    }
}
