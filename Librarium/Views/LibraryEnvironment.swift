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
