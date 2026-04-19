import SwiftUI

/// Root view — switches between onboarding and the main app.
/// selectedLibrary drives navigation from library list → library detail without nested NavigationStacks.
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedLibrary: Library?
    @State private var showSplash = true
    @State private var splashKey = UUID()

    var body: some View {
        ZStack {
            mainContent

            if showSplash, let user = appState.currentUser {
                SplashView(user: user) { showSplash = false }
                    .id(splashKey)
                    .zIndex(1)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, appState.isAuthenticated {
                splashKey = UUID()
                showSplash = true
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
