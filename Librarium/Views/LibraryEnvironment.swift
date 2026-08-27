import SwiftUI

// Environment key that carries the "go back to libraries list" action.
// Set by the Library tab in `RedesignedAppShell` when a library is selected;
// read by `RedesignedBooksView` (and any future per-library root) so the back
// chevron pops the selection without needing its own NavigationStack pop.
private struct LibraryBackKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var libraryBack: (() -> Void)? {
        get { self[LibraryBackKey.self] }
        set { self[LibraryBackKey.self] = newValue }
    }
}

/// Ask for the collection picker.
///
/// Reached from the Home header rather than a tab of its own: switching
/// collections is rare, and a tab for it would sit unused beside four that get
/// used constantly.
private struct SwitchSourceKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var switchSource: (() -> Void)? {
        get { self[SwitchSourceKey.self] }
        set { self[SwitchSourceKey.self] = newValue }
    }
}
