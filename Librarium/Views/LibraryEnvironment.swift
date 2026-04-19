import SwiftUI

// Environment key that carries the "go back to libraries list" action.
// Set on each tab's NavigationStack in LibraryTabView; read by each root tab view.
// When the user navigates deeper within a tab, the root view's toolbar is no longer
// active, so the back button naturally disappears — exactly like a native back button.
private struct LibraryBackKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var libraryBack: (() -> Void)? {
        get { self[LibraryBackKey.self] }
        set { self[LibraryBackKey.self] = newValue }
    }
}
