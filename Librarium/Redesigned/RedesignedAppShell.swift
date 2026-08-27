// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// 5-tab redesigned app shell (mockup IA): Home · Search · [Scan] · Library · Series.
///
/// Implementation notes:
///
/// - Rolls its own floating `EditorialTabBar` overlay rather than using
///   `TabView` — iOS 26's TabView ships a built-in floating bar that
///   `.toolbar(.hidden, for: .tabBar)` doesn't suppress reliably. Each
///   tab's view tree is kept alive in a `ZStack` (toggled via opacity)
///   so internal `@State` + NavigationStack history persist across
///   switches.
///
/// - The Library tab drives a local `selectedLibrary`: nil shows
///   `RedesignedLibrariesView`, non-nil pushes `RedesignedBooksView`
///   in a NavigationStack. Shelves / Loans / Members are not yet wired
///   into the new shell — those screens need to be rebuilt against the
///   mockup before they're reachable again.
///
/// - Profile is presented as a sheet from the Home tab's avatar (see
///   `RedesignedHomeView`), not a top-level tab.
///
/// - The center Scan FAB opens `RedesignedScanFlow` as a fullScreenCover.
struct RedesignedAppShell: View {
    @Environment(AppState.self) private var appState

    @State private var selectedTab: AppTab = .home
    @State private var showScan = false
    /// Book the books grid should push once it appears. Set when the
    /// scanner finds the book already on a shelf and the user asks to
    /// open it; cleared by the grid after it pushes.
    @State private var pendingOpenBookID: String?
    /// Shown when the reader asks to change collections rather than at launch,
    /// which is why it is separate from `needsSourceChoice`.
    @State private var showSourcePicker = false

    var body: some View {
        // Nothing is scoped until a collection is open, so the picker replaces
        // the shell rather than sitting on top of it: a tab bar over a screen
        // that has no source to read is four tabs that cannot answer anything.
        if appState.needsSourceChoice {
            SourcePickerView()
        } else {
            shell
        }
    }

    @ViewBuilder
    private var shell: some View {
        ZStack(alignment: .bottom) {
            // Each tab's content is kept alive in a ZStack and shown via
            // opacity rather than swapped with `if/else`. iOS 26's
            // TabView ships a built-in floating tab bar that
            // `.toolbar(.hidden, for: .tabBar)` does NOT suppress
            // reliably — so we avoid TabView entirely and roll our own
            // shell. Keeping all 4 trees alive preserves each tab's
            // internal @State + NavigationStack history across switches.
            ZStack {
                RedesignedHomeView()
                    .opacity(selectedTab == .home ? 1 : 0)
                    .allowsHitTesting(selectedTab == .home)

                RedesignedSearchView()
                    .opacity(selectedTab == .search ? 1 : 0)
                    .allowsHitTesting(selectedTab == .search)

                // The collection, with library as one filter among eleven
                // rather than the way in. The per-library screens are still
                // here, one level down from this tab's overflow, because that
                // is where syncing a library offline and adding to it live.
                RedesignedBrowseView(
                    openBookID: $pendingOpenBookID,
                    isActive: selectedTab == .books
                )
                .opacity(selectedTab == .books ? 1 : 0)
                .allowsHitTesting(selectedTab == .books)

                RedesignedSeriesListView()
                    .opacity(selectedTab == .series ? 1 : 0)
                    .allowsHitTesting(selectedTab == .series)
            }
            // Rebuilt from scratch when the collection changes. Every tab holds
            // its own loaded books, counts, filters and navigation stack, and
            // all of them belong to the collection they came from: a library
            // filter is another server's UUID, a saved view is another server's
            // row. Asking each surface to notice and reset itself is five
            // places to get it wrong; this is one place to get it right.
            .id(appState.activeSource?.id)
            // Reserve space for the floating bar so scroll content can
            // clear the pill. 64pt bar + 26pt gap = 90pt. We need both
            // modifiers: `safeAreaPadding` for plain layout descendants
            // and `contentMargins(.scrollContent)` for `Form`/`ScrollView`,
            // which use an internal UIScrollView that doesn't always pick
            // up the SwiftUI safe-area bump on its own.
            .safeAreaPadding(.bottom, 90)
            .contentMargins(.bottom, 90, for: .scrollContent)

            // Floating editorial bar — visible across all tabs and across
            // library list ↔ library detail. Shelves / Loans / Members
            // have no entry point here yet; rebuilding those screens
            // against the mockup is tracked in `plans/ios-redesign/PLAN.md`.
            EditorialTabBar(
                selected: $selectedTab,
                highlight: selectedTab,
                onScan: { showScan = true }
            )
            .padding(.bottom, 4)
        }
        .sheet(isPresented: $showSourcePicker) {
            SourcePickerView(onCancel: { showSourcePicker = false })
        }
        .environment(\.switchSource, { showSourcePicker = true })
        .fullScreenCover(isPresented: $showScan) {
            RedesignedScanFlow(
                onClose: { showScan = false },
                onOpenBook: { _, bookID in
                    // Close the scanner and let the books grid push the detail
                    // once it has the book. The library it came from is no
                    // longer needed: the grid can fetch a book by work and the
                    // scanner's answer is a book, not a shelf.
                    showScan = false
                    pendingOpenBookID = bookID
                    selectedTab = .books
                }
            )
        }
    }

}

// MARK: - Tab identity

enum AppTab: Hashable {
    case home, search, books, series
}

/// Detail views advertise the tab they "logically belong to" via this
/// preference. The shell reads it to highlight that tab on the floating
/// bar while leaving the originating NavigationStack (and therefore the
/// back button) untouched.
///
/// E.g. a book detail pushed onto the Search tab's stack sets the
/// preference to `.library`. The bar lights up Library, but tapping
/// back still returns to the search results because the detail is on
/// Search's stack.
struct LogicalTabPreferenceKey: PreferenceKey {
    static let defaultValue: AppTab? = nil
    static func reduce(value: inout AppTab?, nextValue: () -> AppTab?) {
        // Take the deepest non-nil value — descendants override their
        // ancestors so a series detail nested inside a book detail
        // (theoretical) would correctly highlight Series.
        if let next = nextValue() { value = next }
    }
}

// MARK: - Floating editorial tab bar

/// Mockup-faithful floating tab bar: 320pt × 64pt translucent pill, 5 slots,
/// 56pt accent-gradient scan FAB elevated in the center. Sits 26pt above
/// the home indicator.
private struct EditorialTabBar: View {
    @Binding var selected: AppTab
    /// Which tab to visually highlight. Usually equals `selected`, but
    /// detail views can override via `LogicalTabPreferenceKey` — that's
    /// how a book detail pushed onto the Books stack gets Library lit
    /// while the actual selectedTab stays `.books`.
    let highlight: AppTab
    let onScan: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tab(.home,    icon: "house.fill",          label: "Home")
            tab(.search,  icon: "magnifyingglass",      label: "Search")
            scanFAB
            tab(.books,   icon: "books.vertical.fill",  label: "Books")
            tab(.series,  icon: "list.number",         label: "Series")
        }
        .padding(.horizontal, 12)
        .frame(width: 320, height: 64)
        .background(
            RoundedRectangle(cornerRadius: 32)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 32)
                        .fill(Color(hex: 0x1c1e26, opacity: 0.66))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        )
        .shadow(color: Color.black.opacity(0.5), radius: 14, y: 14)
    }

    @ViewBuilder
    private func tab(_ tag: AppTab, icon: String, label: String) -> some View {
        let isActive = highlight == tag
        Button {
            // Tapping the active tab is a no-op (cheap; matches iOS native
            // expectation — re-tap doesn't pop the stack here, we'll add
            // that when there are deeper nav stacks worth popping).
            selected = tag
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    // SF Symbols have different intrinsic sizes:
                    // `list.number` is wide and short, `books.vertical.fill`
                    // is tall. Without a fixed box each VStack is a
                    // different height, so the icons and labels sit at
                    // different heights across the bar even though every
                    // slot is the same width.
                    .frame(width: 26, height: 22)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(isActive ? Theme.Colors.accentStrong : Theme.Colors.appText3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var scanFAB: some View {
        Button(action: onScan) {
            // The mockup specced a 2×2 grid icon, but it reads more like
            // an apps/menu glyph than a scan affordance. `barcode.viewfinder`
            // is the same icon the legacy in-library scan button uses, so
            // users already associate it with the scan flow.
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle().fill(LinearGradient(
                        colors: [Theme.Colors.accent, Color(hex: 0x5a64e8)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                )
                .shadow(color: Theme.Colors.accent.opacity(0.5), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scan a book")
    }
}

// MARK: - Placeholder tab content

/// Home tab placeholder. The real Home rebuild (mockup card 7) is the
/// next big screen — currently-reading hero + jump-back-in strips.
private struct HomeStubView: View {
    var body: some View {
        StubScreen(
            eyebrow: "Librarium · Home",
            title: "Home",
            message: "Currently-reading hero, sparkline, and jump-back-in strips ship in a later pass."
        )
    }
}

/// Search tab placeholder. Replaces the cross-type fan-out search across
/// books / series / contributors (mockup card 10).
private struct SearchStubView: View {
    var body: some View {
        StubScreen(
            eyebrow: "Librarium · Search",
            title: "Search",
            message: "Cross-type search (books · series · contributors) lands in a later pass."
        )
    }
}

private struct StubScreen: View {
    let eyebrow: String
    let title: String
    let message: String

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 8) {
                Text(eyebrow)
                    .font(Theme.Fonts.ui(12, weight: .medium))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.appText3)
                Text(title)
                    .font(Theme.Fonts.pageTitle)
                    .foregroundStyle(Theme.Colors.appText)
                Text(message)
                    .font(Theme.Fonts.bodyPara)
                    .foregroundStyle(Theme.Colors.appText2)
                    .padding(.top, 8)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 18)
            .padding(.top, 60)
            .padding(.bottom, 120)
        }
    }
}
