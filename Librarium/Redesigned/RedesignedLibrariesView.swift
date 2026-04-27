// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// Redesigned post-auth library picker — mockup card #2.
///
/// Layout: editorial dark surface, 2-column grid where the first library
/// is rendered as a "full" card spanning both columns and the rest fall
/// into 4:5 tiles. Each card carries a themed gradient + a fanned cover
/// stack tucked in the upper-right corner so libraries read as distinct
/// even before real cover thumbnails are wired in.
///
/// v1 keeps it simple: load from every signed-in account, no offline
/// merge yet. The legacy LibrariesView retains the rich offline / reauth
/// / drag-reorder UX; we'll layer those back on this view as the redesign
/// matures.
struct RedesignedLibrariesView: View {
    let onSelect: (Library) -> Void
    @Environment(AppState.self) private var appState

    @State private var libraries: [Library] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        gridContent
                    }
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await load() }
            .refreshable { await load() }
        }
    }

    // MARK: - Header (matches .nav-large)

    @ViewBuilder
    private var header: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Librarium · Home")
                    .font(Theme.Fonts.label(11))
                    .tracking(1.6)
                    .foregroundStyle(Theme.Colors.appText3)
                    .textCase(.uppercase)
                Text("Libraries")
                    .font(Theme.Fonts.pageTitle)
                    .foregroundStyle(Theme.Colors.appText)
            }

            // Placeholder + button — no-op for v1, hookup later
            Button(action: {}) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText2)
                    .frame(width: 44, height: 44)
                    .background(Theme.Colors.appLine, in: Circle())
            }
            .opacity(0.6)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Grid

    @ViewBuilder
    private var gridContent: some View {
        if isLoading && libraries.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 240)
                .tint(Theme.Colors.appText2)
        } else if libraries.isEmpty {
            emptyState
        } else {
            // First card spans both columns; the rest go into a 2-col grid.
            VStack(spacing: 14) {
                Button { onSelect(libraries[0]) } label: {
                    LibraryCard(
                        library: libraries[0],
                        isPrimary: appState.primaryAccountID == account(for: libraries[0])?.id,
                        showServerName: appState.accounts.count > 1,
                        layout: .full,
                        theme: theme(for: 0)
                    )
                }
                .buttonStyle(.plain)

                if libraries.count > 1 {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                        spacing: 14
                    ) {
                        ForEach(Array(libraries.dropFirst().enumerated()), id: \.element.clientKey) { idx, lib in
                            Button { onSelect(lib) } label: {
                                LibraryCard(
                                    library: lib,
                                    isPrimary: appState.primaryAccountID == account(for: lib)?.id,
                                    showServerName: appState.accounts.count > 1,
                                    layout: .compact,
                                    theme: theme(for: idx + 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)

            if let error {
                Text(error)
                    .font(Theme.Fonts.rowMeta)
                    .foregroundStyle(Theme.Colors.bad)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "books.vertical")
                .font(.system(size: 32))
                .foregroundStyle(Theme.Colors.appText3)
            Text("No libraries yet")
                .font(Theme.Fonts.cardTitle)
                .foregroundStyle(Theme.Colors.appText)
            Text("Create one to start cataloguing your collection.")
                .font(Theme.Fonts.rowMeta)
                .foregroundStyle(Theme.Colors.appText3)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    // MARK: - Helpers

    private func account(for library: Library) -> ServerAccount? {
        appState.accounts.first(where: { $0.url == library.serverURL })
    }

    /// Cycle through 3 themes by card index, matching the mockup's
    /// theme-1 / theme-2 alternation.
    private func theme(for index: Int) -> LibraryCardTheme {
        switch index % 3 {
        case 0: return .purple
        case 1: return .green
        default: return .rose
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let accounts = appState.accounts
        guard !accounts.isEmpty else {
            libraries = []
            return
        }

        var collected: [Library] = []
        var firstError: String?

        await withTaskGroup(of: (String, [Library]?, Error?).self) { group in
            for account in accounts {
                group.addTask {
                    do {
                        let client = await appState.makeClient(serverURL: account.url)
                        var libs = try await LibraryService(client: client).list()
                        for i in libs.indices {
                            libs[i].serverURL = account.url
                            libs[i].serverName = account.name
                        }
                        return (account.url, libs, nil)
                    } catch {
                        return (account.url, nil, error)
                    }
                }
            }
            for await (_, libs, err) in group {
                if let libs {
                    collected.append(contentsOf: libs)
                } else if firstError == nil, let err {
                    firstError = err.localizedDescription
                }
            }
        }

        libraries = collected.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if libraries.isEmpty, let firstError {
            error = firstError
        }
    }
}

// MARK: - Card layout + theme

enum LibraryCardLayout {
    case full       // first row, spans both columns
    case compact    // 4:5 tile
}

enum LibraryCardTheme {
    case purple, green, rose

    var gradient: LinearGradient {
        switch self {
        case .purple:
            return LinearGradient(
                colors: [Color(hex: 0x1d1f2c), Color(hex: 0x2a1d3a)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .green:
            return LinearGradient(
                colors: [Color(hex: 0x1f2a1f), Color(hex: 0x1a2e35)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .rose:
            return LinearGradient(
                colors: [Color(hex: 0x2a1d24), Color(hex: 0x1f1c2e)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    /// Three placeholder cover colours for the fanned stack on this
    /// theme. Real cover thumbnails replace these once the cover URL
    /// fetcher is wired into the redesign.
    var stackColors: [Color] {
        switch self {
        case .purple:
            return [Color(hex: 0x16213e), Color(hex: 0x4a1a3c), Color(hex: 0x1a0d2e)]
        case .green:
            return [Color(hex: 0x0d2a2e), Color(hex: 0x1f4d2c), Color(hex: 0x3a2410)]
        case .rose:
            return [Color(hex: 0x4a1a3c), Color(hex: 0x3a1c1c), Color(hex: 0xf0e7d3)]
        }
    }
}

// MARK: - Library card

private struct LibraryCard: View {
    let library: Library
    let isPrimary: Bool
    let showServerName: Bool
    let layout: LibraryCardLayout
    let theme: LibraryCardTheme

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Fanned cover stack — sits in the top-right corner, behind text
            CoverStack(colors: theme.stackColors)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .opacity(0.7)

            // Foreground content
            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                Text(library.name)
                    .font(layout == .full
                          ? .system(size: 22, weight: .semibold)
                          : .system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText)
                    .lineLimit(2)
                Text(countLine)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText2)
                    .monospacedDigit()
                if showServerName, !library.serverName.isEmpty {
                    Text(library.serverName)
                        .font(Theme.Fonts.label(9))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Colors.appText3)
                        .padding(.top, 2)
                }
                pills
                    .padding(.top, 8)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(layout == .full ? 16.0/7.0 : 4.0/5.0, contentMode: .fit)
        .background(theme.gradient)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Theme.Colors.appLine, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var pills: some View {
        HStack(spacing: 6) {
            if isPrimary {
                pill(text: "Primary", textColor: Theme.Colors.accentStrong, bg: Theme.Colors.accentSoft)
            }
            if library.isPublic {
                pill(text: "Public", textColor: Theme.Colors.gold, bg: Color(hex: 0xf3c971, opacity: 0.15))
            }
        }
    }

    @ViewBuilder
    private func pill(text: String, textColor: Color, bg: Color) -> some View {
        Text(text)
            .font(Theme.Fonts.label(9))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(bg, in: Capsule())
    }

    private var countLine: String {
        let book = library.bookCount ?? 0
        let reading = library.readingCount ?? 0
        let read = library.readCount ?? 0
        if book == 0 { return "Empty library" }
        var parts = ["\(book.formatted()) book\(book == 1 ? "" : "s")"]
        if reading > 0 { parts.append("\(reading) reading") }
        if read > 0 { parts.append("\(read.formatted()) read") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Fanned cover stack

private struct CoverStack: View {
    let colors: [Color]

    var body: some View {
        // Three rounded rects, each rotated/offset to fan out from the
        // top-right corner. Z-order matters — the middle cover sits on
        // top, matching the mockup's stack composition.
        GeometryReader { geo in
            let w = geo.size.width
            let coverW = w * 0.42
            let coverH = coverW * 1.5

            ZStack {
                cover(color: colors[2])
                    .frame(width: coverW, height: coverH)
                    .rotationEffect(.degrees(-12))
                    .offset(x: -coverW * 0.55, y: coverH * 0.18)

                cover(color: colors[0])
                    .frame(width: coverW, height: coverH)
                    .rotationEffect(.degrees(8))
                    .offset(x: 0, y: coverH * 0.12)

                cover(color: colors[1])
                    .frame(width: coverW, height: coverH)
                    .rotationEffect(.degrees(-3))
                    .offset(x: -coverW * 0.28, y: 0)
            }
            .frame(width: w * 0.65, height: coverH * 1.3, alignment: .topTrailing)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .padding(12)
    }

    @ViewBuilder
    private func cover(color: Color) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
    }
}
