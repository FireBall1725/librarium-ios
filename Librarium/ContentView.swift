import SwiftData
import SwiftUI

/// Root view — switches between onboarding and the main app shell.
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

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
            await runSyncAllAccounts()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Re-drain on foreground so the local store catches up with
            // anything that landed on the server while the app was in
            // the background. Cheap when the outbox is empty and the
            // server has no new ops.
            if newPhase == .active {
                Task { await runSyncAllAccounts() }
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

    /// Run a sync drain for every authenticated account in parallel.
    /// Best-effort: errors per account are logged but don't surface in
    /// the UI (the existing read paths still hit the api directly
    /// until this rebuild is wired through). Each account has its own
    /// cursor, so a failure on one doesn't drag the others.
    private func runSyncAllAccounts() async {
        guard appState.isAuthenticated else { return }
        let container = modelContext.container
        let accounts = appState.accounts

        await withTaskGroup(of: Void.self) { group in
            for account in accounts {
                group.addTask {
                    let api = await appState.makeClient(serverURL: account.url)
                    let service = SyncService(
                        api: api,
                        serverAccountID: account.id,
                        modelContainer: container
                    )
                    do {
                        try await service.syncOnce()
                    } catch {
                        #if DEBUG
                        print("📥 [ContentView] sync failed for account \(account.id): \(error)")
                        #endif
                    }
                }
            }
        }
    }
}
