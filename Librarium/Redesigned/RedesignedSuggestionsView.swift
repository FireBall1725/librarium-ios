// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// What to read next, and why.
///
/// The server has been generating these for months and the phone had no way to
/// see them. The reason line is the whole point: a list of titles with no
/// reasons is a list anyone could have written, so it gets the same weight as
/// the title rather than being tucked under it.
struct RedesignedSuggestionsView: View {
    @Environment(AppState.self) private var appState

    @State private var vm = SuggestionsViewModel()
    @State private var pushed: BookOpenRequest?
    @State private var libraries: [String: Library] = [:]

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
                    listContent
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard vm.suggestions.isEmpty else { return }
            await loadLibraries()
            await vm.load(appState: appState)
        }
        .refreshable { await vm.load(appState: appState) }
        .navigationDestination(item: $pushed) { request in
            RedesignedBookDetailView(library: request.library, book: request.book)
        }
    }

    @ViewBuilder
    private var header: some View {
        Text(vm.isLoading && vm.suggestions.isEmpty
             ? "Loading…"
             : (vm.suggestions.count == 1 ? "1 suggestion" : "\(vm.suggestions.count) suggestions"))
            .font(Theme.Fonts.ui(13, weight: .medium))
            .foregroundStyle(Theme.Colors.appText3)
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 12)
    }

    @ViewBuilder
    private var listContent: some View {
        if vm.isLoading && vm.suggestions.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 240)
                .tint(Theme.Colors.appText2)
        } else if vm.suggestions.isEmpty {
            EmptyState(
                icon: "sparkles",
                title: "Nothing suggested",
                subtitle: "Suggestions appear here once the instance has some to make."
            )
            .padding(.top, 40)
        } else {
            VStack(spacing: 12) {
                ForEach(vm.suggestions) { suggestion in
                    card(suggestion)
                }
            }
            .padding(.horizontal, 22)
        }
    }

    @ViewBuilder
    private func card(_ suggestion: Suggestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                BookCoverImage(
                    url: vm.coverURL(for: suggestion),
                    width: 44, height: 66,
                    title: suggestion.title, author: suggestion.author, readStatus: nil
                )
                .clipShape(RoundedRectangle(cornerRadius: 5))

                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.kindLabel)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Colors.accent)
                    Text(suggestion.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Colors.appText)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    if !suggestion.author.isEmpty {
                        Text(suggestion.author)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.Colors.appText3)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !suggestion.reasoning.isEmpty {
                Text(suggestion.reasoning)
                    .font(Theme.Fonts.ui(13))
                    .foregroundStyle(Theme.Colors.appText2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }

            HStack(spacing: 8) {
                if suggestion.bookId != nil {
                    action("Open", tint: Theme.Colors.accent) { open(suggestion) }
                }
                action("Interested", tint: Theme.Colors.good) {
                    Task { await vm.setStatus(suggestion, "interested", appState: appState) }
                }
                action("Not now", tint: Theme.Colors.appText3) {
                    Task { await vm.setStatus(suggestion, "dismissed", appState: appState) }
                }
                Spacer()
                // Not the same as dismissing. "Not now" clears the row and the
                // same book comes back next run; this is how someone says never.
                Button {
                    Task { await vm.block(suggestion, appState: appState) }
                } label: {
                    Image(systemName: "hand.raised")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Colors.bad)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Never suggest this again")
            }
        }
        .padding(14)
        .background(Theme.Colors.appCard, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.Colors.appLine, lineWidth: 0.5))
    }

    @ViewBuilder
    private func action(_ label: String, tint: Color, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(label)
                .font(Theme.Fonts.ui(12, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(tint.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }

    private func loadLibraries() async {
        var found: [String: Library] = [:]
        for account in appState.accounts where account.kind != .local {
            let client = appState.makeClient(serverURL: account.url)
            guard let list = try? await LibraryService(client: client).list() else { continue }
            for var library in list {
                library.serverURL = account.url
                library.serverName = account.name
                found[library.id] = library
            }
        }
        if !found.isEmpty { libraries = found }
    }

    private func open(_ suggestion: Suggestion) {
        guard let bookId = suggestion.bookId else { return }
        let library = suggestion.libraryId.flatMap { libraries[$0] }
            ?? libraries.values.first(where: { $0.serverURL == vm.serverURL(for: suggestion) })
        guard let library else { return }
        Task {
            let client = appState.makeClient(serverURL: library.serverURL)
            if let book = try? await BookService(client: client).get(bookId: bookId) {
                pushed = BookOpenRequest(book: book, library: library)
            }
        }
    }
}

// MARK: - View model

@MainActor
@Observable
final class SuggestionsViewModel {
    var suggestions: [Suggestion] = []
    var isLoading = false

    private var origin: [String: String] = [:]

    func serverURL(for suggestion: Suggestion) -> String { origin[suggestion.id] ?? "" }

    func coverURL(for suggestion: Suggestion) -> URL? {
        CoverURL.resolve(suggestion.coverUrl, serverURL: serverURL(for: suggestion))
    }

    func load(appState: AppState) async {
        isLoading = true
        defer { isLoading = false }

        var collected: [Suggestion] = []
        var origins: [String: String] = [:]
        for account in appState.accounts where account.kind != .local {
            let client = appState.makeClient(serverURL: account.url)
            guard let list = try? await SuggestionService(client: client).list() else { continue }
            for s in list where s.status == "new" || s.status == "interested" {
                origins[s.id] = account.url
                collected.append(s)
            }
        }
        origin = origins
        suggestions = collected
    }

    /// Removed from the list as soon as it is acted on, rather than after a
    /// reload. A card that stays put for a second after being dismissed gets
    /// tapped twice.
    func setStatus(_ suggestion: Suggestion, _ status: String, appState: AppState) async {
        guard let url = origin[suggestion.id] else { return }
        suggestions.removeAll { $0.id == suggestion.id }
        let client = appState.makeClient(serverURL: url)
        try? await SuggestionService(client: client).setStatus(id: suggestion.id, status: status)
    }

    func block(_ suggestion: Suggestion, appState: AppState) async {
        guard let url = origin[suggestion.id] else { return }
        suggestions.removeAll { $0.id == suggestion.id }
        let client = appState.makeClient(serverURL: url)
        try? await SuggestionService(client: client).block(id: suggestion.id)
    }
}
