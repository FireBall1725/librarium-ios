// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation
import Network
import Observation

/// Global network reachability state. Watches `NWPathMonitor` and
/// publishes `isOnline` so call sites can short-circuit to the offline
/// cache without paying URLSession's 10-second timeout on every request.
///
/// Per-server reachability (the case where network is up but one
/// specific Librarium server is down) still relies on the api round-trip
/// failing; this monitor only handles the airplane-mode / no-Wi-Fi case.
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    /// True when at least one network path is satisfied. Defaults to
    /// `true` so the first launch on a fresh install isn't gated until
    /// `NWPathMonitor` reports in (which can take a beat).
    private(set) var isOnline: Bool = true

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let queue = DispatchQueue(label: "ca.fireball1725.librarium.network")

    /// Per-server failure timestamps. Updated by API call sites that
    /// catch URLSession timeouts. Lets view code skip the api on
    /// subsequent calls for a server that just timed out — saves the
    /// user from waiting 10 seconds again on each navigation.
    @ObservationIgnored private var failures: [String: Date] = [:]
    /// Window inside which a server is considered "recently failed".
    /// After this we let api calls try again — the server may have
    /// come back. Long enough to feel snappy across many navigations,
    /// short enough that a quick recovery is picked up.
    @ObservationIgnored private let unreachableTTL: TimeInterval = 60

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            DispatchQueue.main.async {
                self?.isOnline = online
            }
        }
        monitor.start(queue: queue)
    }

    /// Record that an api call to this server URL just failed in a
    /// network-y way (timeout, connection refused, DNS, etc.). View
    /// code shouldn't bother trying the api again for the next minute.
    func markServerUnreachable(_ serverURL: String) {
        failures[serverURL] = Date()
    }

    /// Record that an api call succeeded — clears any prior failure
    /// so subsequent navigations route through the api as normal.
    func markServerReachable(_ serverURL: String) {
        failures.removeValue(forKey: serverURL)
    }

    /// True when there's no network at all OR the named server failed
    /// within the last minute. Either case is a reason to skip api and
    /// go straight to cache.
    func shouldSkipAPI(for serverURL: String) -> Bool {
        if !isOnline { return true }
        guard let last = failures[serverURL] else { return false }
        return Date().timeIntervalSince(last) < unreachableTTL
    }
}
