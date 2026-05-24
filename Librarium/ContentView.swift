import SwiftData
import SwiftUI

/// Root view — switches between onboarding and the main app shell.
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @State private var showSplash = true

    var body: some View {
        ZStack {
            mainContent

            if showSplash, let user = appState.currentUser {
                SplashView(user: user) { showSplash = false }
                    .zIndex(1)
            }
        }
        .task(id: appState.isAuthenticated) {
            await runInitialSync()
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

    /// Kick off a sync drain for the primary account on launch so the
    /// local SwiftData store catches up with anything that changed on
    /// the server since the last session. Best-effort: errors are
    /// logged but don't surface in the UI (the existing read paths
    /// still hit the api directly until this rebuild is wired through).
    private func runInitialSync() async {
        guard appState.isAuthenticated,
              let account = appState.primaryAccount else { return }

        let api = appState.makeClient()
        let service = SyncService(
            api: api,
            serverAccountID: account.id,
            modelContainer: modelContext.container
        )
        do {
            try await service.syncOnce()
        } catch {
            #if DEBUG
            print("📥 [ContentView] initial sync failed: \(error)")
            #endif
        }
    }
}
