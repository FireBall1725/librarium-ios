// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// The Views tab: saved filters, and the surfaces that are not the collection.
///
/// A saved view used to be a drawer inside the books grid and a second drawer
/// inside the series list, so the same feature had two homes and neither was
/// visible from the other. The web client puts them in the rail beside Loans,
/// Suggestions and the libraries; this is that part of the rail
/// (librarium-ios-001).
struct RedesignedViewsView: View {
    /// Whether this tab is the one on screen.
    var isActive = true

    @Environment(AppState.self) private var appState

    @State private var bookViews: [SavedList] = []
    @State private var seriesViews: [SavedList] = []
    @State private var isLoading = true
    /// Why the list is empty, when it is not simply empty. A failed request
    /// and a reader with no views look identical otherwise.
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.appBackground.ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        header
                        destinations
                        savedSection(
                            title: "Book views",
                            views: bookViews,
                            empty: "A view is a filter with a name. Filter the books and save it."
                        )
                        savedSection(
                            title: "Series views",
                            views: seriesViews,
                            empty: "Filter the runs and save that too."
                        )
                    }
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            // Keyed on being on screen AND on whether the accounts can be
            // used. A tab that loads at launch asks before the reader has
            // signed back in, gets "invalid credentials" and keeps showing it
            // for the rest of the session, because nothing about the account
            // list changes when a session is restored.
            .task(id: loadKey) {
                guard isActive else { return }
                await load()
            }
            .refreshable { await load() }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Librarium · Views")
                .font(Theme.Fonts.ui(12, weight: .medium))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.appText3)
            Text("Views")
                .font(Theme.Fonts.pageTitle)
                .foregroundStyle(Theme.Colors.appText)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    // MARK: - The rest of the rail

    /// Loans, suggestions and the libraries themselves. They sat behind an
    /// overflow menu on the books grid, which is two taps and a guess away
    /// from anywhere a reader would look for them.
    @ViewBuilder
    private var destinations: some View {
        VStack(spacing: 0) {
            NavigationLink { RedesignedLoansView() } label: {
                destinationRow(icon: "arrow.left.arrow.right", title: "Loans",
                               detail: "What is out, and what is late")
            }
            .buttonStyle(.plain)
            NavigationLink { RedesignedSuggestionsView() } label: {
                destinationRow(icon: "sparkles", title: "Suggestions",
                               detail: "What to read next")
            }
            .buttonStyle(.plain)
            NavigationLink { LibrariesBrowser() } label: {
                destinationRow(icon: "building.columns", title: "Libraries",
                               detail: "Keep one offline, or add to it")
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func destinationRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Colors.accentStrong)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.Colors.accentSoft))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Fonts.ui(15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText)
                Text(detail)
                    .font(Theme.Fonts.ui(12))
                    .foregroundStyle(Theme.Colors.appText3)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Colors.appText3)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    // MARK: - Saved views

    @ViewBuilder
    private func savedSection(title: String, views: [SavedList], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Theme.Fonts.ui(12, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.appText3)
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 8)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(Theme.Fonts.ui(13))
                    .foregroundStyle(Theme.Colors.warn)
                    .padding(.horizontal, 22)
            } else if views.isEmpty {
                Text(isLoading ? "Loading…" : empty)
                    .font(Theme.Fonts.ui(13))
                    .foregroundStyle(Theme.Colors.appText3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 22)
            } else {
                ForEach(views) { view in
                    NavigationLink {
                        destination(for: view)
                    } label: {
                        viewRow(view)
                    }
                    .buttonStyle(.plain)
                    Divider().background(Theme.Colors.appLine).padding(.leading, 22)
                }
            }
        }
    }

    @ViewBuilder
    private func destination(for view: SavedList) -> some View {
        if view.surface == "series" {
            RedesignedSeriesListView(
                initialSelection: SeriesSelection(query: view.filterQuery),
                initialTitle: view.name
            )
        } else {
            RedesignedBrowseView(
                initialSelection: BrowseSelection(query: view.filterQuery),
                initialTitle: view.name
            )
        }
    }

    @ViewBuilder
    private func viewRow(_ view: SavedList) -> some View {
        HStack(spacing: 12) {
            Image(systemName: view.isDefault ? "pin.fill" : "line.3.horizontal.decrease")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Colors.appText3)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(view.name)
                    .font(Theme.Fonts.ui(15, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText)
                    .lineLimit(1)
                if view.isDefault {
                    // Which one the shelf opens on, as against which one is
                    // applied right now: different things, and only one of them
                    // survives closing the app.
                    Text("Opens by default")
                        .font(Theme.Fonts.ui(11))
                        .foregroundStyle(Theme.Colors.appText3)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Colors.appText3)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    // MARK: - Loading

    private var loadKey: String {
        let accounts = appState.accounts.map { "\($0.id):\($0.needsReauth)" }.joined(separator: ",")
        return "\(isActive)|\(accounts)"
    }

    private func load() async {
        guard let client = appState.makeServerClient() else {
            // A Lite collection has no server to keep views on, so there is
            // nothing to fetch and nothing broken about that.
            bookViews = []
            seriesViews = []
            error = nil
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let service = ListService(client: client)
            async let books = service.savedViews(surface: "books")
            async let series = service.savedViews(surface: "series")
            bookViews = try await books
            seriesViews = try await series
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
