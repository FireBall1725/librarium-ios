import Foundation

struct ServerAccount: Identifiable {
    let id: UUID
    var name: String
    var url: String
    var accessToken: String
    var refreshToken: String
    var user: User
    var kind: Kind = .remote

    /// Differentiates a real Librarium server-backed account from a Lite-mode
    /// local-only account whose data lives entirely in SwiftData on this
    /// device. Stored on `ServerAccountMeta` so persistence round-trips it.
    enum Kind: String, Codable {
        case remote
        case local
    }

    /// True when either token is missing or has been blanked after a failed
    /// refresh. The user invariant is "only the user deletes a server", so
    /// instead of removing accounts on auth failure we surface them as
    /// `needsReauth` and let the user sign back in (or explicitly remove).
    var needsReauth: Bool {
        if kind == .local { return false }
        return accessToken.isEmpty || refreshToken.isEmpty
    }

    static func defaultName(for url: String) -> String {
        guard let host = URL(string: url)?.host, !host.isEmpty else { return url }
        return host
    }

    /// Synthetic URL used to tag a local account so multi-account flows that
    /// key off `url` (offline cache, `Library.clientKey`) still see a unique
    /// per-account identifier even though there's no real server.
    static func localURL(for id: UUID) -> String {
        "local://\(id.uuidString)"
    }
}

struct ServerAccountMeta: Codable {
    let id: UUID
    var name: String
    var url: String
    var user: User
    /// Optional in the JSON to keep installs created before Lite mode existed
    /// decodable — anything without a `kind` row is by definition a remote
    /// server-backed account.
    var kind: ServerAccount.Kind? = .remote
}
