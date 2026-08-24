// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation

/// What a given Librarium server can do.
///
/// Per connection, not per app. One install talks to several instances and they
/// can be on different versions, so "does this server have work-keyed reading
/// state" has a different answer for each of them. A single global flag would
/// be wrong the first time someone adds a second server, and wrong in the worst
/// way: the app would ask an older server for a route it does not have and read
/// the 404 as "you have not read this book".
///
/// The signal is already there. `/health` is unauthenticated and reports the
/// minimum client versions a server expects, a field older releases do not
/// send, so its presence is what distinguishes them.
actor ServerCapabilities {
    static let shared = ServerCapabilities()

    private struct Health: Decodable {
        let version: String?
        let minClients: [String: String]?
    }

    /// Answers already learned, keyed by server URL. An absent entry means not
    /// asked yet; a present one is trusted for the life of the process, since a
    /// server does not change version under a running app often enough to be
    /// worth re-probing on every read.
    private var known: [String: Bool] = [:]

    /// Whether this server keys reading state to the work.
    ///
    /// Defaults to false on anything unclear: an unreachable server, a
    /// malformed body, a timeout. False means the app uses the per-edition
    /// route, which every version still serves, so guessing wrong costs a
    /// less precise read rather than a broken screen.
    func hasWorkKeyedReadingState(serverURL: String) async -> Bool {
        if let answer = known[serverURL] { return answer }

        guard let url = URL(string: serverURL.appending("/health")) else {
            known[serverURL] = false
            return false
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue(ClientIdentity.name, forHTTPHeaderField: ClientIdentity.header)
        request.setValue(ClientIdentity.version, forHTTPHeaderField: ClientIdentity.versionHeader)

        var answer = false
        if let (data, response) = try? await URLSession.shared.data(for: request),
           let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            if let health = try? decoder.decode(Health.self, from: data) {
                answer = health.minClients != nil
            }
        }
        known[serverURL] = answer
        return answer
    }

    /// Forget what was learned about a server. Called when one is re-added or
    /// its URL changes, so a probe is not answered from a previous install.
    func forget(serverURL: String) {
        known.removeValue(forKey: serverURL)
    }

    /// Forget everything. Used by tests, and by a sign-out that clears accounts.
    func forgetAll() {
        known.removeAll()
    }
}
