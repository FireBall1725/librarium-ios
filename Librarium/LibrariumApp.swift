import SwiftUI
import UIKit

@main
struct LibrariumApp: App {
    @State private var appState = AppState()

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
        }
    }
}
