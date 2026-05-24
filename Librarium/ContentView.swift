import SwiftData
import SwiftUI

/// Root view — switches between onboarding and the main app shell.
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var showSplash = true
    @State private var telemetry = TelemetryService.shared
    @State private var showTelemetryOptIn = false

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
            maybeShowTelemetryOptIn(source: "task")
        }
        .onChange(of: showSplash) { _, isShowing in
            // Wait until splash has fully dismissed so the sheet
            // doesn't race the splash transition.
            if !isShowing {
                maybeShowTelemetryOptIn(source: "splash-dismissed")
            }
        }
        .onChange(of: appState.isAuthenticated) { _, authed in
            if authed {
                maybeShowTelemetryOptIn(source: "auth-flipped")
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await runSyncAllAccounts() }
            }
        }
        .fullScreenCover(isPresented: $showTelemetryOptIn) {
            TelemetryOptInSheet(
                onEnable: { telemetry.setOptIn(true) },
                onDecline: { telemetry.setOptIn(false) }
            )
        }
    }

    /// Surface the opt-in sheet on the first authenticated launch and
    /// on upgrades from a build that never had telemetry. Once the
    /// user has either enabled or declined the sheet never appears
    /// again. Multiple triggers (initial .task, splash dismissal,
    /// auth flipping) all funnel through this single guarded check
    /// so whichever fires first wins.
    private func maybeShowTelemetryOptIn(source: String) {
        let auth = appState.isAuthenticated
        let decided = telemetry.hasDecided
        #if DEBUG
        print("📊 [Telemetry] check from \(source): auth=\(auth) decided=\(decided) splash=\(showSplash)")
        #endif
        guard auth, !decided, !showSplash else { return }
        #if DEBUG
        print("📊 [Telemetry] triggering opt-in cover")
        #endif
        showTelemetryOptIn = true
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
            for account in accounts where account.kind == .remote {
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
