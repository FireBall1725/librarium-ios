import SwiftUI

/// Toolbar leading "Libraries" back button used by every root tab inside a
/// library (Books, Shelves, Series, Loans, Members). Renders a Label with
/// the chevron + title so it scales with Dynamic Type and exposes a real
/// accessibility label, instead of the bespoke `HStack { chevron, Text }`
/// each tab used to inline.
///
/// Usage:
///
///     .toolbar {
///         ToolbarItem(placement: .topBarLeading) { LibraryBackButton() }
///         ...
///     }
///
/// Reads the `\.libraryBack` environment value (set by `LibraryTabView`).
/// When that value is nil — i.e. the view is presented outside the library
/// tab bar — the button renders nothing, so screens that share these views
/// in other contexts don't get an orphaned back button.
struct LibraryBackButton: View {
    @Environment(\.libraryBack) private var onBack

    var body: some View {
        if let onBack {
            Button(action: onBack) {
                Label("Libraries", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
            }
            .accessibilityLabel("Back to libraries")
        }
    }
}
