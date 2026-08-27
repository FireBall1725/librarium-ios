// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// Books that are out, across every library.
///
/// Loans existed on the phone only inside a book: to find out who had something
/// you had to already know which book to open, which is the opposite of the
/// question. `/me/loans` answers it in one request, each row carrying the
/// library its book lives in.
struct RedesignedLoansView: View {
    @Environment(AppState.self) private var appState

    @State private var vm = LoansViewModel()
    @State private var searchTask: Task<Void, Never>?
    @State private var pushed: BookOpenRequest?
    @State private var libraries: [String: Library] = [:]

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
                    searchPill
                    scopeRow
                    listContent
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Loans")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard vm.loans.isEmpty else { return }
            await loadLibraries()
            await vm.load(appState: appState)
        }
        .refreshable { await vm.load(appState: appState) }
        .onChange(of: vm.query) { _, _ in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await vm.load(appState: appState)
            }
        }
        .navigationDestination(item: $pushed) { request in
            RedesignedBookDetailView(library: request.library, book: request.book)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summary)
                .font(Theme.Fonts.ui(13, weight: .medium))
                .foregroundStyle(vm.overdueCount > 0 ? Theme.Colors.warn : Theme.Colors.appText3)
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// What is out, and how much of it is late. The second half is the reason
    /// to look, so it goes in the same line rather than waiting to be found in
    /// a row somewhere down the list.
    private var summary: String {
        if vm.isLoading && vm.loans.isEmpty { return "Loading…" }
        let out = vm.loans.filter(\.isActive).count
        if out == 0 { return vm.includeReturned ? "Nothing out" : "Nothing lent out" }
        let base = out == 1 ? "1 book out" : "\(out) books out"
        return vm.overdueCount > 0 ? "\(base) · \(vm.overdueCount) overdue" : base
    }

    @ViewBuilder
    private var searchPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Colors.appText3)
            TextField("Search borrower or title", text: $vm.query)
                .font(Theme.Fonts.ui(14, weight: .medium))
                .foregroundStyle(Theme.Colors.appText)
                .tint(Theme.Colors.accent)
                .autocorrectionDisabled()
            if !vm.query.isEmpty {
                Button { vm.query = "" } label: {
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

    @ViewBuilder
    private var scopeRow: some View {
        HStack(spacing: 8) {
            chip("Out", active: !vm.includeReturned && !vm.overdueOnly) {
                vm.includeReturned = false
                vm.overdueOnly = false
            }
            chip("Overdue", active: vm.overdueOnly) {
                vm.overdueOnly = true
                vm.includeReturned = false
            }
            chip("All", active: vm.includeReturned) {
                vm.includeReturned = true
                vm.overdueOnly = false
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func chip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Task { await vm.load(appState: appState) }
        } label: {
            Text(label)
                .font(Theme.Fonts.ui(13, weight: .medium))
                .foregroundStyle(active ? Theme.Colors.accentStrong : Theme.Colors.appText2)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Capsule().fill(active ? Theme.Colors.accentSoft : Color.white.opacity(0.06)))
                .overlay(Capsule().stroke(active ? Color.clear : Theme.Colors.appLine, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - List

    @ViewBuilder
    private var listContent: some View {
        if vm.isLoading && vm.loans.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 240)
                .tint(Theme.Colors.appText2)
        } else if vm.loans.isEmpty {
            EmptyState(
                icon: "arrow.left.arrow.right",
                title: vm.overdueOnly ? "Nothing overdue" : "Nothing lent out",
                subtitle: vm.overdueOnly
                    ? "Every book that is out is still within its due date."
                    : "Lend a book from its page and it shows up here."
            )
            .padding(.top, 40)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(vm.loans.enumerated()), id: \.element.id) { idx, loan in
                    Button { open(loan) } label: { row(loan) }
                        .buttonStyle(.plain)
                    if idx != vm.loans.count - 1 {
                        Divider().background(Theme.Colors.appLine).padding(.leading, 22)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ loan: Loan) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(loan.bookTitle.isEmpty ? "Untitled" : loan.bookTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(loan.isActive ? Theme.Colors.appText : Theme.Colors.appText2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(subtitle(loan))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(loan.isOverdue ? Theme.Colors.warn : Theme.Colors.appText3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if loan.isActive {
                Button {
                    Task { await vm.markReturned(loan, appState: appState) }
                } label: {
                    Text("Returned")
                        .font(Theme.Fonts.ui(12, weight: .semibold))
                        .foregroundStyle(Theme.Colors.good)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Theme.Colors.good.opacity(0.15)))
                }
                .buttonStyle(.plain)
            } else {
                Text("Returned")
                    .font(Theme.Fonts.ui(11, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText3)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func subtitle(_ loan: Loan) -> String {
        var parts = [loan.loanedTo.isEmpty ? "Someone" : loan.loanedTo]
        if let due = loan.dueLabel { parts.append(due) }
        if let name = libraries[loan.libraryId]?.name, libraries.count > 1 { parts.append(name) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Actions

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

    private func open(_ loan: Loan) {
        guard let library = libraries[loan.libraryId] else { return }
        Task {
            let client = appState.makeClient(serverURL: library.serverURL)
            if let book = try? await BookService(client: client).get(bookId: loan.bookId) {
                pushed = BookOpenRequest(book: book, library: library)
            }
        }
    }
}

// MARK: - View model

@MainActor
@Observable
final class LoansViewModel {
    var loans: [Loan] = []
    var query = ""
    var includeReturned = false
    var overdueOnly = false
    var isLoading = false

    /// Which server each loan came from, so marking one returned goes back to
    /// the right one.
    private var origin: [String: String] = [:]

    var overdueCount: Int { loans.filter(\.isOverdue).count }

    func load(appState: AppState) async {
        isLoading = true
        defer { isLoading = false }

        let accounts = appState.accounts.filter { $0.kind != .local && !$0.url.hasPrefix("local://") }
        var collected: [Loan] = []
        var origins: [String: String] = [:]

        for account in accounts {
            let client = appState.makeClient(serverURL: account.url)
            guard let page = try? await MeBrowseService(client: client).loans(
                query: query, includeReturned: includeReturned, overdueOnly: overdueOnly
            ) else { continue }
            for loan in page.items { origins[loan.id] = account.url }
            collected.append(contentsOf: page.items)
        }

        origin = origins
        // Overdue first, then by how soon they are due. A list ordered by when
        // a book went out buries the one that is three weeks late under
        // everything lent since.
        loans = collected.sorted { a, b in
            if a.isOverdue != b.isOverdue { return a.isOverdue }
            if a.isActive != b.isActive { return a.isActive }
            return (a.dueDate ?? "9999") < (b.dueDate ?? "9999")
        }
    }

    func markReturned(_ loan: Loan, appState: AppState) async {
        guard let url = origin[loan.id] else { return }
        let client = appState.makeClient(serverURL: url)
        _ = try? await LoanService(client: client)
            .markReturned(libraryId: loan.libraryId, loanId: loan.id)
        await load(appState: appState)
    }
}
