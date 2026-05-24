import Foundation

struct ServerAccount: Identifiable {
    let id: UUID
    var name: String
    var url: String
    var accessToken: String
    var refreshToken: String
    var user: User
    /// When the current access token stops being valid. Captured at
    /// login / refresh and used by the proactive-refresh check so we
    /// can rotate tokens before any other request would otherwise hit
    /// a 401 and force the same rotation through the slower path.
    ///
    /// Optional because legacy accounts persisted before this field
    /// existed don't have a recorded expiry; treat that case as
    /// "refresh now to find out."
    var accessTokenExpiresAt: Date?

    /// True when either token is missing or has been blanked after a failed
    /// refresh. The user invariant is "only the user deletes a server", so
    /// instead of removing accounts on auth failure we surface them as
    /// `needsReauth` and let the user sign back in (or explicitly remove).
    var needsReauth: Bool { accessToken.isEmpty || refreshToken.isEmpty }

    static func defaultName(for url: String) -> String {
        guard let host = URL(string: url)?.host, !host.isEmpty else { return url }
        return host
    }
}

struct ServerAccountMeta: Codable {
    let id: UUID
    var name: String
    var url: String
    var user: User
    /// Mirrors `ServerAccount.accessTokenExpiresAt`. Optional so
    /// already-persisted installs decode cleanly.
    var accessTokenExpiresAt: Date?
}
