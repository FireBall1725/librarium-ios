import Foundation
import Observation

/// Per-device user-defined ordering for the merged Libraries list.
///
/// The Libraries surface combines libraries from every connected server into
/// one list. Users can drag-reorder that list; the resulting order persists
/// in `UserDefaults` (per-device, since the connected servers can differ
/// across devices) and is keyed by `Library.clientKey` (a `serverURL + id`
/// composite, since two libraries on different servers can share a UUID).
///
/// On read, `sorted(_:)` applies the saved order; libraries that don't
/// appear in the saved order — newly-discovered ones from a fresh server,
/// libraries created via the New Library sheet, etc. — fall through to a
/// stable alphabetical tail at the end of the list. New entries therefore
/// always land at the bottom and stay in a predictable position until the
/// user drags them.
@Observable
final class LibraryOrderStore {
    static let shared = LibraryOrderStore()

    private let key = "library.display.order.v1"
    private let defaults: UserDefaults

    /// Stored ordering as an array of `clientKey`s. Mirrored to UserDefaults
    /// on every write. Stale keys (e.g. for a removed server) are tolerated
    /// at read time — `sorted(_:)` filters them — so we don't have to chase
    /// every account-removal site to keep this clean.
    private(set) var order: [String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.order = defaults.stringArray(forKey: key) ?? []
    }

    /// Returns the input libraries in user-defined order. Anything not in
    /// the saved order is appended alphabetically by name.
    func sorted(_ libraries: [Library]) -> [Library] {
        let byKey = Dictionary(uniqueKeysWithValues: libraries.map { ($0.clientKey, $0) })
        let known = Set(libraries.map(\.clientKey))
        let pruned = order.filter { known.contains($0) }
        let prunedKeys = Set(pruned)
        let leftover = libraries
            .filter { !prunedKeys.contains($0.clientKey) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let ordered = pruned.compactMap { byKey[$0] }
        return ordered + leftover
    }

    /// Saves the current display order from the supplied (already-sorted)
    /// libraries. Called whenever the user drags a row, creates a new
    /// library, or otherwise mutates the list shape.
    func setOrder(from libraries: [Library]) {
        order = libraries.map(\.clientKey)
        defaults.set(order, forKey: key)
    }
}
