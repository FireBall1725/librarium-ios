import SwiftUI

@Observable
private final class LoansViewModel {
    var loans: [Loan] = []
    var isLoading = false
    var error: String?
    var showActiveOnly = true

    var displayed: [Loan] {
        showActiveOnly ? loans.filter(\.isActive) : loans
    }

    func load(client: APIClient, libraryId: String) async {
        isLoading = true; error = nil; defer { isLoading = false }
        do { loans = try await LoanService(client: client).list(libraryId: libraryId) }
        catch { self.error = error.localizedDescription }
    }
}

struct LoansView: View {
    let library: Library
    @Environment(AppState.self) private var appState
    @State private var vm = LoansViewModel()
    @State private var showAdd = false
    @State private var editingLoan: Loan?

    var body: some View {
        Group {
            if appState.isOffline {
                EmptyState(icon: "wifi.slash", title: "Offline",
                           subtitle: "Loan data isn't cached. Connect to your server to view loans.")
            } else if vm.isLoading && vm.loans.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.displayed.isEmpty {
                EmptyState(icon: "arrow.left.arrow.right",
                           title: vm.showActiveOnly ? "No active loans" : "No loans",
                           subtitle: "Track books you've lent to others.",
                           action: { showAdd = true }, actionLabel: "Add Loan")
            } else {
                List(vm.displayed) { loan in
                    LoanRow(loan: loan)
                        .swipeActions(edge: .trailing) {
                            if loan.isActive {
                                Button {
                                    Task {
                                        if let updated = try? await LoanService(client: appState.makeClient())
                                            .markReturned(libraryId: library.id, loanId: loan.id) {
                                            if let i = vm.loans.firstIndex(where: { $0.id == loan.id }) {
                                                vm.loans[i] = updated
                                            }
                                        }
                                    }
                                } label: { Label("Returned", systemImage: "checkmark.circle") }
                                    .tint(.green)
                            }
                            Button(role: .destructive) {
                                Task {
                                    try? await LoanService(client: appState.makeClient()).delete(libraryId: library.id, loanId: loan.id)
                                    vm.loans.removeAll { $0.id == loan.id }
                                }
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editingLoan = loan }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Loans")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { LibraryBackButton() }
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    Toggle("Active only", isOn: $vm.showActiveOnly).toggleStyle(.button).font(.caption)
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add loan")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddEditLoanSheet(library: library) { _ in
                Task { await vm.load(client: appState.makeClient(), libraryId: library.id) }
            }
        }
        .sheet(item: $editingLoan) { loan in
            AddEditLoanSheet(library: library, loan: loan) { _ in
                Task { await vm.load(client: appState.makeClient(), libraryId: library.id) }
            }
        }
        .task { if !appState.isOffline { await vm.load(client: appState.makeClient(), libraryId: library.id) } }
        .refreshable { if !appState.isOffline { await vm.load(client: appState.makeClient(), libraryId: library.id) } }
    }
}

private struct LoanRow: View {
    let loan: Loan
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(loan.bookTitle).font(.headline).lineLimit(1)
                Spacer()
                if loan.isActive {
                    Text("Active").font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.green.opacity(0.15)).foregroundStyle(.green).clipShape(Capsule())
                } else {
                    Text("Returned").font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.secondary.opacity(0.15)).foregroundStyle(.secondary).clipShape(Capsule())
                }
            }
            Text("Loaned to \(loan.loanedTo)").font(.subheadline).foregroundStyle(.secondary)
            if let due = loan.dueDate, !due.isEmpty {
                Text("Due: \(due)").font(.caption)
                    .foregroundStyle(loan.isActive ? .orange : .secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
