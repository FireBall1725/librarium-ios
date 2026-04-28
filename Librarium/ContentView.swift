import SwiftUI

/// Root view — switches between onboarding and the main app.
/// selectedLibrary drives navigation from library list → library detail without nested NavigationStacks.
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @AppStorage(RedesignFlag.key) private var redesignEnabled = false

    @State private var selectedLibrary: Library?
    @State private var showSplash = true

    var body: some View {
        ZStack {
            mainContent

            if showSplash, let user = appState.currentUser {
                SplashView(user: user) { showSplash = false }
                    .zIndex(1)
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if appState.isAuthenticated {
            if redesignEnabled {
                // The redesigned 5-tab shell owns its own library
                // selection — ContentView's selectedLibrary state is
                // legacy-only. Keep them disjoint to avoid double-state
                // headaches when toggling the flag.
                RedesignedAppShell()
            } else if let library = selectedLibrary {
                LibraryTabView(library: library) {
                    selectedLibrary = nil
                }
            } else {
                LibrariesView { library in
                    selectedLibrary = library
                }
            }
        } else {
            AddServerView(isFirstTime: true, onComplete: {})
        }
    }
}
