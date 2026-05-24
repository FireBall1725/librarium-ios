import Foundation
import Observation
import TelemetryDeck

/// User-facing telemetry control. Singleton because everywhere in the
/// app wants to send signals and they all need to share the same
/// opt-in state and local transparency log.
///
/// Opt-in is **off by default**. The user sees an introduction sheet
/// the first time they reach the authenticated app and explicitly
/// chooses enable or decline. The decision persists. They can flip it
/// later from `TelemetrySettingsView`.
///
/// Delivery is delegated to the TelemetryDeck Swift SDK so we don't
/// have to reinvent batching, retry, app-lifecycle handling, or
/// anonymous client identity. The local `recentSignals` log captures
/// every signal we hand to the SDK, before it's sent, so the user can
/// audit the surface from inside the app.
///
/// What we send (when enabled):
///   - Signal name (e.g., `app_launched`, `book_detail_opened`)
///   - A short anonymous payload (e.g., `media_type:manga`)
///   - The SDK adds: anonymous install id, session id, app version,
///     device class
///
/// What we do NOT send:
///   - Book titles, ISBNs, authors, ratings, reviews, notes
///   - Library names or member names
///   - Search queries
///   - Anything that could identify a user or what they read
///
/// Open code is the trust contract.
@Observable
final class TelemetryService {
    static let shared = TelemetryService()

    // MARK: - Public state

    /// True once the user has either enabled or declined telemetry.
    /// False means the opt-in sheet should be shown the next time the
    /// app reaches the authenticated UI.
    private(set) var hasDecided: Bool

    /// True only if the user has explicitly opted in.
    private(set) var optedIn: Bool

    /// Last `recentSignalLimit` signals queued on this device, newest
    /// first. Available regardless of opt-in state so the user can see
    /// "nothing is being sent" when opted out.
    private(set) var recentSignals: [TelemetrySignal]

    // MARK: - Constants

    /// TelemetryDeck app id for librarium-ios (production).
    private let appID = "53CE081B-9A81-4CA3-BBE6-0932D36472E9"

    private let recentSignalLimit = 50

    /// True once `TelemetryDeck.initialize` has been called. The SDK
    /// is idempotent on re-init but we guard locally so toggling opt-in
    /// off then back on doesn't pile up identical configurations.
    private var sdkInitialised = false

    // MARK: - Internals

    private let defaults: UserDefaults

    private static let keyDecided = "telemetry.optInDecided"
    private static let keyOptedIn = "telemetry.optedIn"
    private static let keyRecentSignals = "telemetry.recentSignals"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasDecided = defaults.bool(forKey: Self.keyDecided)
        self.optedIn = defaults.bool(forKey: Self.keyOptedIn)
        if let data = defaults.data(forKey: Self.keyRecentSignals),
           let decoded = try? JSONDecoder().decode([TelemetrySignal].self, from: data) {
            self.recentSignals = decoded
        } else {
            self.recentSignals = []
        }
        if optedIn {
            startSDK()
            send("app_launched")
        }
    }

    // MARK: - Decision

    /// Persist the user's opt-in decision. Calling this with the same
    /// value twice is fine; the side effect is the same.
    func setOptIn(_ enabled: Bool) {
        let wasOptedIn = optedIn
        hasDecided = true
        optedIn = enabled
        defaults.set(true, forKey: Self.keyDecided)
        defaults.set(enabled, forKey: Self.keyOptedIn)
        if enabled {
            startSDK()
            // Fire one signal immediately so the user sees the
            // transparency log populate the moment they flip the
            // toggle. Distinguish first opt-in from a flip-on so the
            // dashboard can tell them apart.
            send(wasOptedIn ? "telemetry_re_enabled" : "telemetry_enabled")
        }
    }

    // MARK: - Sending

    /// Record a signal in the local log and (if opted in) hand it to
    /// the TelemetryDeck SDK for delivery. Drops on the floor if the
    /// user hasn't opted in, but the call site doesn't have to check.
    func send(_ name: String, payload: [String: String] = [:]) {
        guard optedIn else { return }

        let signal = TelemetrySignal(name: name, payload: payload)
        prependSignal(signal)

        TelemetryDeck.signal(name, parameters: payload)
    }

    /// Wipe the local signal log. The view exposes this so the user
    /// can clear whatever record we have on device. Does not affect
    /// signals the SDK has already delivered or queued.
    func clearLog() {
        recentSignals = []
        persistRecent()
    }

    // MARK: - Internals

    private func startSDK() {
        guard !sdkInitialised else { return }
        let config = TelemetryDeck.Config(appID: appID)
        TelemetryDeck.initialize(config: config)
        sdkInitialised = true
    }

    private func prependSignal(_ signal: TelemetrySignal) {
        recentSignals.insert(signal, at: 0)
        if recentSignals.count > recentSignalLimit {
            recentSignals = Array(recentSignals.prefix(recentSignalLimit))
        }
        persistRecent()
    }

    private func persistRecent() {
        guard let data = try? JSONEncoder().encode(recentSignals) else { return }
        defaults.set(data, forKey: Self.keyRecentSignals)
    }
}
