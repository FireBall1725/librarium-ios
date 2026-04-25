import SwiftUI

/// Root view — switches between onboarding and the main app.
/// selectedLibrary drives navigation from library list → library detail without nested NavigationStacks.
struct ContentView: View {
    @Environment(AppState.self) private var appState

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
            if let library = selectedLibrary {
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
