import SwiftUI

/// Root view — switches between onboarding and the main app shell.
struct ContentView: View {
    @Environment(AppState.self) private var appState

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
            RedesignedAppShell()
        } else {
            AddServerView(isFirstTime: true, onComplete: {})
        }
    }
}
