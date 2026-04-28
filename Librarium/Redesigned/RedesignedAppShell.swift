// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// 5-tab redesigned app shell (mockup IA): Home · Search · [Scan] · Library · Profile.
///
/// Implementation notes:
///
/// - Uses a `TabView` with the system tab bar hidden (`.toolbar(.hidden, for: .tabBar)`),
///   plus a custom `EditorialTabBar` overlay so we get the floating glass-pill
///   look from the mockup. Switching the system bar off keeps tab-state
///   preservation (each tab keeps its NavigationStack history).
///
/// - The Library tab swaps between `RedesignedLibrariesView` (entry list)
///   and the legacy `LibraryTabView` (Books / Shelves / Series / Loans /
///   Members) based on a local `selectedLibrary` state. Until we rebuild
///   the library context (deferred), the floating bar **hides** when the
///   user has drilled into a library so the legacy inner tab bar is
///   unobstructed. They get back to the floating bar by tapping back.
///
/// - Home / Search are placeholder screens for v1. Profile reuses the
///   existing `ProfileView` (still has the long-press toggle for the flag).
///
/// - The center Scan button is a stub for v1 — alerts the user to use the
///   scan icon inside a library for now. Wiring the redesigned scan flow
///   happens with the camera screen rebuild.
struct RedesignedAppShell: View {
    @Environment(AppState.self) private var appState

    @State private var selectedTab: AppTab = .home
    @State private var selectedLibrary: Library?
    @State private var showScan = false
    /// Detail views advertise the tab they "belong to" via
    /// `LogicalTabPreferenceKey` so the floating bar can highlight that
    /// tab while the actual NavigationStack stays on the originating
    /// tab. Lets back-button return to where the user came from while
    /// the bar still reflects what they're viewing.
    @State private var logicalTabOverride: AppTab?

    var body: some View {
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

                libraryTab
                    .opacity(selectedTab == .library ? 1 : 0)
                    .allowsHitTesting(selectedTab == .library)

                RedesignedSeriesListView()
                    .opacity(selectedTab == .series ? 1 : 0)
                    .allowsHitTesting(selectedTab == .series)
            }
            // Reserve space for the floating bar so scroll content can
            // clear the pill. 64pt bar + 26pt gap = 90pt. We need both
            // modifiers: `safeAreaPadding` for plain layout descendants
            // and `contentMargins(.scrollContent)` for `Form`/`ScrollView`,
            // which use an internal UIScrollView that doesn't always pick
            // up the SwiftUI safe-area bump on its own.
            .safeAreaPadding(.bottom, 90)
            .contentMargins(.bottom, 90, for: .scrollContent)

            // Floating editorial bar — visible across all tabs and across
            // library list ↔ library detail. The legacy LibraryTabView
            // (Books / Shelves / Series / Loans / Members) is no longer
            // wrapped in the redesigned flow; Shelves/Series/Loans/Members
            // are deferred to follow-up screens (per `plans/ios-redesign/PLAN.md`).
            EditorialTabBar(
                selected: $selectedTab,
                highlight: logicalTabOverride ?? selectedTab,
                onScan: { showScan = true }
            )
            .padding(.bottom, 4)
        }
        .onPreferenceChange(LogicalTabPreferenceKey.self) { value in
            logicalTabOverride = value
        }
        .fullScreenCover(isPresented: $showScan) {
            RedesignedScanFlow {
                showScan = false
            }
        }
    }

    @ViewBuilder
    private var libraryTab: some View {
        if let library = selectedLibrary {
            // Wrap in NavigationStack so RedesignedBooksView's
            // `.navigationDestination` (book detail) has somewhere to
            // push. Pass `\.libraryBack` so the header chevron in the
            // books grid pops back to the library list.
            NavigationStack {
                RedesignedBooksView(library: library)
                    .environment(\.libraryBack, { selectedLibrary = nil })
            }
        } else {
            RedesignedLibrariesView { lib in
                selectedLibrary = lib
            }
        }
    }

}

// MARK: - Tab identity

enum AppTab: Hashable {
    case home, search, library, series
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
    /// how a book detail pushed onto Search's stack gets Library lit
    /// while the actual selectedTab stays `.search`.
    let highlight: AppTab
    let onScan: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tab(.home,    icon: "house.fill",          label: "Home")
            tab(.search,  icon: "magnifyingglass",     label: "Search")
            scanFAB
            tab(.library, icon: "books.vertical.fill", label: "Library")
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
