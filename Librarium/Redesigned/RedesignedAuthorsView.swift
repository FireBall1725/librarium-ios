// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// The people behind the collection.
///
/// Search and a role filter, and nothing else. A rail here would mostly repeat
/// the books rail one step removed: "authors of manga I have not read" is a
/// question about books, and the books surface already answers it with a
/// contributor filter. What this page adds is the axis that one cannot show —
/// a person, their whole shelf, and how much of it has been read.
///
/// No alphabet bar. It assumes a Latin script and one letter per name, and both
/// are wrong for a collection with Japanese credits in it.
struct RedesignedAuthorsView: View {
    @Environment(AppState.self) private var appState

    @State private var vm = AuthorsViewModel()
    @State private var query = ""
    @State private var selected: AuthorSelection?

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
                    searchPill
                    roleRow
                    listContent
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Authors")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard vm.authors.isEmpty else { return }
            await vm.load(appState: appState)
        }
        .refreshable { await vm.load(appState: appState) }
        .navigationDestination(item: $selected) { pick in
            // Their books, on the surface that already knows how to draw books.
            // A second grid here would be the same grid with one filter
            // pre-applied and its own bugs.
            RedesignedBrowseView(
                initialSelection: pick.selection,
                initialTitle: pick.name
            )
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(vm.isLoading && vm.authors.isEmpty
                 ? "Loading…"
                 : (vm.total == 1 ? "1 person" : "\(vm.total.formatted()) people"))
                .font(Theme.Fonts.ui(13, weight: .medium))
                .foregroundStyle(Theme.Colors.appText3)
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var searchPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Colors.appText3)
            TextField("Search people", text: $query)
                .font(Theme.Fonts.ui(14, weight: .medium))
                .foregroundStyle(Theme.Colors.appText)
                .tint(Theme.Colors.accent)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Colors.appText3)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.Colors.appLine, lineWidth: 0.5))
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
    }

    /// In memory, not over the network. The index is one request that already
    /// arrived and matching a name against it is instant; a round trip per
    /// keystroke would be slower and no more correct.
    private var filtered: [AuthorIndexEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return vm.authors }
        return vm.authors.filter {
            $0.name.lowercased().contains(q) || $0.sortName.lowercased().contains(q)
        }
    }

    // MARK: - Roles

    @ViewBuilder
    private var roleRow: some View {
        if vm.roles.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    roleChip(code: nil, label: "Everyone", count: vm.roles.map(\.count).max() ?? 0)
                    ForEach(vm.roles) { role in
                        roleChip(code: role.code, label: role.label, count: role.count)
                    }
                }
                .padding(.horizontal, 22)
            }
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private func roleChip(code: String?, label: String, count: Int) -> some View {
        let active = code == nil ? vm.roles(selected: nil) : vm.selectedRoles.contains(code!)
        Button {
            vm.toggleRole(code)
            Task { await vm.load(appState: appState) }
        } label: {
            Text("\(label) · \(count)")
                .font(Theme.Fonts.ui(13, weight: .medium))
                .foregroundStyle(active ? Theme.Colors.accentStrong : Theme.Colors.appText2)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(active ? Theme.Colors.accentSoft : Color.white.opacity(0.06))
                )
                .overlay(Capsule().stroke(active ? Color.clear : Theme.Colors.appLine, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - List

    @ViewBuilder
    private var listContent: some View {
        let rows = filtered
        if vm.isLoading && vm.authors.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 240)
                .tint(Theme.Colors.appText2)
        } else if rows.isEmpty {
            EmptyState(
                icon: "person.2",
                title: vm.authors.isEmpty ? "Nobody yet" : "No matches",
                subtitle: vm.authors.isEmpty
                    ? "People credited on your books show up here."
                    : "No one matches that name."
            )
            .padding(.top, 40)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, author in
                    Button { open(author) } label: { row(author) }
                        .buttonStyle(.plain)
                    if idx != rows.count - 1 {
                        Divider().background(Theme.Colors.appLine)
                            .padding(.leading, 22 + 44 + 12)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ author: AuthorIndexEntry) -> some View {
        HStack(spacing: 12) {
            // Seeded on the contributor id, not the name, so two people who
            // share a name do not share a face and a rename does not change
            // one.
            GeneratedAvatar(
                seed: author.id,
                initial: String(author.name.prefix(1)).uppercased(),
                size: 44
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(author.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(subtitle(author))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            spines(author)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Colors.appText3)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func subtitle(_ author: AuthorIndexEntry) -> String {
        let books = author.bookCount == 1 ? "1 book" : "\(author.bookCount) books"
        guard author.readCount > 0 else { return books }
        return "\(books) · \(author.readCount) read"
    }

    /// Three covers, fanned. Enough to recognise a shelf at a glance without
    /// turning a list row into a gallery.
    @ViewBuilder
    private func spines(_ author: AuthorIndexEntry) -> some View {
        let shown = Array(author.spines.prefix(3))
        if !shown.isEmpty {
            HStack(spacing: -10) {
                ForEach(shown) { spine in
                    BookCoverImage(
                        url: vm.coverURL(for: spine, authorID: author.id),
                        width: 22, height: 33,
                        title: spine.title, author: author.name, readStatus: nil
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Theme.Colors.appBackground, lineWidth: 1)
                    )
                }
            }
        }
    }

    private func open(_ author: AuthorIndexEntry) {
        var selection = BrowseSelection()
        // By id, not by name. Naming a person is a different question from
        // searching for their name: "Tite" the person is not a book with Tite
        // in its title.
        selection.contributors = [author.id]
        selected = AuthorSelection(id: author.id, name: author.name, selection: selection)
    }
}

struct AuthorSelection: Identifiable, Hashable {
    let id: String
    let name: String
    let selection: BrowseSelection

    static func == (a: AuthorSelection, b: AuthorSelection) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - View model

@MainActor
@Observable
final class AuthorsViewModel {
    var authors: [AuthorIndexEntry] = []
    var roles: [ContributorRoleCount] = []
    var selectedRoles: Set<String> = []
    var total = 0
    var isLoading = false

    /// Which server each person came from, so their covers resolve against the
    /// right host. Two accounts can hand back the same contributor id.
    private var origin: [String: String] = [:]

    func roles(selected code: String?) -> Bool {
        code == nil ? selectedRoles.isEmpty : selectedRoles.contains(code!)
    }

    func toggleRole(_ code: String?) {
        guard let code else {
            selectedRoles.removeAll()
            return
        }
        if selectedRoles.contains(code) { selectedRoles.remove(code) } else { selectedRoles.insert(code) }
    }

    func coverURL(for spine: AuthorSpine, authorID: String) -> URL? {
        CoverURL.resolve(spine.coverUrl, serverURL: origin[authorID] ?? "")
    }

    func load(appState: AppState) async {
        isLoading = true
        defer { isLoading = false }

        // The open collection only. Two servers are two sets of people, and
        // merging them puts one server's contributor beside another's with no
        // way to tell which shelf a tap will open.
        let accounts = [appState.activeSource].compactMap { $0 }.filter(\.isServerBacked)
        let picked = selectedRoles

        var collected: [AuthorIndexEntry] = []
        var roleCounts: [ContributorRoleCount] = []
        var origins: [String: String] = [:]

        for account in accounts {
            let client = appState.makeClient(serverURL: account.url)
            guard let page = try? await MeBrowseService(client: client)
                .authors(libraries: [], roles: picked) else { continue }
            for entry in page.items { origins[entry.id] = account.url }
            collected.append(contentsOf: page.items)
            roleCounts = FacetMerge.sum(
                roleCounts.map { FacetValue(value: $0.code, label: $0.code, count: $0.count) },
                page.roles.map { FacetValue(value: $0.code, label: $0.code, count: $0.count) }
            ).map { ContributorRoleCount(code: $0.value, count: $0.count) }
        }

        origin = origins
        roles = roleCounts.sorted { $0.count > $1.count }
        // The server sorts each account's answer; with two there is nothing
        // that can sort across them, so the merge happens on the same key.
        authors = accounts.count > 1
            ? collected.sorted { $0.sortName.localizedStandardCompare($1.sortName) == .orderedAscending }
            : collected
        total = authors.count
    }
}
