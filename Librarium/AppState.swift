import Foundation
import Observation

@Observable
final class AppState {

    // MARK: - Public state

    private(set) var accounts: [ServerAccount] = []
    var isAuthenticated: Bool { !accounts.isEmpty }
    var isOffline = false

    var currentUser: User? { activeAccount?.user ?? accounts.first?.user }

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
    }

    // MARK: - Account management

    func setActiveAccount(for library: Library) {
        if let match = accounts.first(where: { $0.url == library.serverURL }) {
            activeAccountID = match.id
        }
    }

    func addAccount(_ account: ServerAccount) {
        if let i = accounts.firstIndex(where: { $0.url == account.url }) {
            accounts[i] = account
        } else {
            accounts.append(account)
        }
        saveAccounts()
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
        KeychainService.shared.delete("access_\(id.uuidString)")
        KeychainService.shared.delete("refresh_\(id.uuidString)")
        accounts.removeAll { $0.id == id }
        if activeAccountID == id { activeAccountID = nil }
        saveAccounts()
    }

    func logout() {
        for account in accounts {
            KeychainService.shared.delete("access_\(account.id.uuidString)")
            KeychainService.shared.delete("refresh_\(account.id.uuidString)")
        }
        accounts = []
        activeAccountID = nil
        isOffline = false
        UserDefaults.standard.removeObject(forKey: "server_accounts")
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

    // MARK: - Token refresh

    @discardableResult
    func refreshToken(for accountID: UUID) async -> Bool {
        guard let account = accounts.first(where: { $0.id == accountID }),
              !account.refreshToken.isEmpty else {
            removeAccount(id: accountID)
            return false
        }
        do {
            let client = APIClient(baseURL: account.url)
            let tokens: AuthTokens = try await client.post(
                "/api/v1/auth/refresh",
                body: ["refresh_token": account.refreshToken]
            )
            guard let i = accounts.firstIndex(where: { $0.id == accountID }) else { return false }
            accounts[i].accessToken = tokens.accessToken
            accounts[i].refreshToken = tokens.refreshToken
            accounts[i].user = tokens.user
            saveAccounts()
            return true
        } catch APIError.unauthorized {
            // Refresh token was rejected — user genuinely needs to re-auth.
            removeAccount(id: accountID)
            return false
        } catch let APIError.serverError(code, _) where code == 403 {
            // 403 from the auth endpoint is also a definitive rejection.
            removeAccount(id: accountID)
            return false
        } catch {
            // Transient failure (network unreachable, 5xx, decode, timeout).
            // Keep the account — previously we deleted it on any error here,
            // which made servers silently disappear whenever the app relaunched
            // during a brief connectivity hiccup or server cold-start.
            return false
        }
    }

    // MARK: - Persistence

    private func loadAccounts() {
        guard let data = UserDefaults.standard.data(forKey: "server_accounts"),
              let metas = try? JSONDecoder().decode([ServerAccountMeta].self, from: data) else { return }
        accounts = metas.compactMap { meta in
            guard let access = KeychainService.shared.get("access_\(meta.id.uuidString)"),
                  let refresh = KeychainService.shared.get("refresh_\(meta.id.uuidString)") else { return nil }
            return ServerAccount(
                id: meta.id,
                name: meta.name,
                url: meta.url,
                accessToken: access,
                refreshToken: refresh,
                user: meta.user
            )
        }
    }

    private func saveAccounts() {
        let metas = accounts.map { ServerAccountMeta(id: $0.id, name: $0.name, url: $0.url, user: $0.user) }
        if let data = try? JSONEncoder().encode(metas) {
            UserDefaults.standard.set(data, forKey: "server_accounts")
        }
        for account in accounts {
            KeychainService.shared.set(account.accessToken,  forKey: "access_\(account.id.uuidString)")
            KeychainService.shared.set(account.refreshToken, forKey: "refresh_\(account.id.uuidString)")
        }
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
