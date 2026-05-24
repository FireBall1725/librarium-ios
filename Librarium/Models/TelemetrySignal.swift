import Foundation

/// A single telemetry signal recorded in the on-device transparency
/// log before being handed to the TelemetryDeck SDK.
///
/// The local log (visible to the user in `TelemetrySettingsView`) is a
/// list of these. Stored as JSON in UserDefaults so it survives app
/// restarts.
struct TelemetrySignal: Identifiable, Codable, Equatable {
    let id: UUID
    /// The signal type (e.g., `app_launched`, `book_detail_opened`).
    /// Snake-case so it groups cleanly on the dashboard.
    let name: String
    /// When the signal was recorded on this device. Delivery to
    /// TelemetryDeck happens asynchronously via the SDK; this is the
    /// "handed off" timestamp, not a "received by server" timestamp.
    let createdAt: Date
    /// Optional key-value pairs sent alongside the signal. Stays as a
    /// `[String: String]` dictionary on purpose: it's easy to display
    /// and the rule of no-user-content (no titles, no IDs that map
    /// back to specific books) keeps the surface small.
    let payload: [String: String]

    init(
        name: String,
        payload: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.name = name
        self.createdAt = createdAt
        self.payload = payload
    }
}
