// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// 5-slot redesigned app shell: Home · Collection · [Scan] · Views · Search.
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
/// - Collection carries books, runs and people behind one segmented
///   control, the way the web client carries them as three rows of one
///   rail. Views carries the saved filters plus the surfaces that are
///   not the collection: loans, suggestions and the libraries.
///
/// - Search holds the fifth slot rather than Profile. Searching is what
///   a reader does several times a visit; the account is a screen they
///   open when something needs changing, which is why the web client
///   keeps it at the foot of the rail and not in the nav. Profile is a
///   push off the Home avatar.
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

                // The collection, with library as one filter among eleven
                // rather than the way in. The per-library screens are still
                // here, under Libraries in the Views tab, because that is
                // where syncing a library offline and adding to it live.
                RedesignedCollectionView(
                    openBookID: $pendingOpenBookID,
                    isActive: selectedTab == .collection
                )
                .opacity(selectedTab == .collection ? 1 : 0)
                .allowsHitTesting(selectedTab == .collection)

                RedesignedViewsView(isActive: selectedTab == .views)
                    .opacity(selectedTab == .views ? 1 : 0)
                    .allowsHitTesting(selectedTab == .views)

                RedesignedSearchView()
                    .opacity(selectedTab == .search ? 1 : 0)
                    .allowsHitTesting(selectedTab == .search)
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

            // Floating editorial bar — visible across every tab and every
            // push. Shelves and Members have no screen in this app yet, so
            // they have no entry point here either; that is a screen to build
            // rather than a route to wire.
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
                onOpenBook: { library, bookID in
                    // Scanning is the one thing that asks every collection at
                    // once, so the answer can be in one the reader does not
                    // currently have open. Opening it moves them there rather
                    // than pushing a book the surfaces cannot see: without
                    // this, a match on the server while the Lite collection was
                    // open simply never loaded.
                    showScan = false
                    if let account = appState.accounts.first(where: { $0.url == library.serverURL }),
                       appState.activeSource?.id != account.id {
                        appState.setActiveSource(id: account.id)
                    }
                    pendingOpenBookID = bookID
                    selectedTab = .collection
                }
            )
        }
    }

}

// MARK: - Tab identity

enum AppTab: Hashable {
    case home, collection, views, search
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
            tab(.home,       icon: "house.fill",         label: "Home")
            tab(.collection, icon: "books.vertical.fill", label: "Collection")
            scanFAB
            tab(.views,      icon: "bookmark.fill",      label: "Views")
            tab(.search,     icon: "magnifyingglass",    label: "Search")
        }
        .padding(.horizontal, 12)
        .frame(width: 320, height: 64)
        .background(
            RoundedRectangle(cornerRadius: 32)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 32)
                        .fill(Theme.Colors.appBackgroundTrans)
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
                        colors: [Theme.Colors.accent, Theme.Colors.accentDeep],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                )
                .shadow(color: Theme.Colors.accent.opacity(0.5), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scan a book")
    }
}
