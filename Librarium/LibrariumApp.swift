import SwiftData
import SwiftUI
import UIKit

@main
struct LibrariumApp: App {
    @State private var appState = AppState()

    /// Local SwiftData container that mirrors per-account sync state.
    /// Built lazily so a failure to open the store crashes early with
    /// a useful stack trace rather than silently degrading at runtime.
    let modelContainer: ModelContainer = {
        let schema = Schema([PersistedInteraction.self, PendingSyncOp.self])
        let config = ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        // Debug — print every editorial font face actually registered at
        // runtime so the redesign theme can use PostScript names that match.
        for family in UIFont.familyNames.sorted() where
            family.contains("Cormorant") || family.contains("Crimson") || family.contains("Cinzel")
        {
            print("FONT family: \(family)")
            for name in UIFont.fontNames(forFamilyName: family) {
                print("  \(name)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .modelContainer(modelContainer)
        }
    }
}
