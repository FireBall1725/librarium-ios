import SwiftUI

struct LibraryTabView: View {
    let library: Library
    let onBack: () -> Void
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            NavigationStack {
                BooksView(library: library)
            }
            .environment(\.libraryBack, onBack)
            .tabItem { Label("Books", systemImage: "books.vertical") }

            NavigationStack {
                ShelvesView(library: library)
            }
            .environment(\.libraryBack, onBack)
            .tabItem { Label("Shelves", systemImage: "square.stack") }

            NavigationStack {
                SeriesListView(library: library)
            }
            .environment(\.libraryBack, onBack)
            .tabItem { Label("Series", systemImage: "list.number") }

            NavigationStack {
                LoansView(library: library)
            }
            .environment(\.libraryBack, onBack)
            .tabItem { Label("Loans", systemImage: "arrow.left.arrow.right") }

            NavigationStack {
                MembersView(library: library)
            }
            .environment(\.libraryBack, onBack)
            .tabItem { Label("Members", systemImage: "person.2") }
        }
        .onAppear { appState.setActiveAccount(for: library) }
    }
}
