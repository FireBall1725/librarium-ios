import SwiftUI

@Observable
final class ContributorDetailViewModel {
    var detail: ContributorDetail?
    var isLoading = false
    var error: String?

    func load(client: APIClient, libraryId: String, contributorId: String) async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            detail = try await ContributorService(client: client).get(
                libraryId: libraryId, contributorId: contributorId)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ContributorDetailView: View {
    let library: Library
    let contributorId: String

    @Environment(AppState.self) private var appState
    @State private var vm = ContributorDetailViewModel()

    var body: some View {
        Group {
            if vm.isLoading && vm.detail == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail = vm.detail {
                content(for: detail)
            } else if let error = vm.error {
                ContentUnavailableView("Couldn't load", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                Color.clear
            }
        }
        .navigationTitle(vm.detail?.name ?? "Contributor")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if vm.detail == nil {
                await vm.load(client: appState.makeClient(), libraryId: library.id, contributorId: contributorId)
            }
        }
    }

    @ViewBuilder
    private func content(for detail: ContributorDetail) -> some View {
        let photoURL: URL? = {
            guard let path = detail.photoUrl, !path.isEmpty, !library.serverURL.isEmpty else { return nil }
            return URL(string: library.serverURL + path)
        }()

        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    ContributorPhotoImage(url: photoURL, size: 120)
                    Text(detail.name).font(.title2).bold()
                    if let meta = metaLine(for: detail) {
                        Text(meta).font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("\(detail.bookCount) \(detail.bookCount == 1 ? "book" : "books") in this library")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                if let bio = detail.bio, !bio.isEmpty {
                    section("Biography") {
                        Text(bio).font(.callout)
                    }
                }

                if !detail.books.isEmpty {
                    section("In this library") {
                        VStack(spacing: 8) {
                            ForEach(detail.books) { book in
                                NavigationLink(destination: BookDetailView(library: library, book: book)) {
                                    BookLinkRow(book: book, serverURL: library.serverURL)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if !detail.works.isEmpty {
                    section("Other works") {
                        VStack(spacing: 8) {
                            ForEach(detail.works) { work in
                                WorkRow(work: work)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func metaLine(for detail: ContributorDetail) -> String? {
        var parts: [String] = []
        if let nat = detail.nationality, !nat.isEmpty { parts.append(nat) }
        if let born = detail.bornDate, !born.isEmpty {
            if let died = detail.diedDate, !died.isEmpty {
                parts.append("\(born) – \(died)")
            } else {
                parts.append("b. \(born)")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)
            content()
        }
    }
}

// MARK: - Rows

private struct BookLinkRow: View {
    let book: Book
    let serverURL: String

    private var coverURL: URL? {
        guard let path = book.coverUrl, !path.isEmpty, !serverURL.isEmpty else { return nil }
        return URL(string: serverURL + path)
    }

    var body: some View {
        HStack(spacing: 10) {
            BookCoverImage(url: coverURL, width: 40, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title).font(.subheadline).lineLimit(2)
                if !book.subtitle.isEmpty {
                    Text(book.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

private struct WorkRow: View {
    let work: ContributorWork

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 40, height: 56)
                Image(systemName: "book").foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(work.title).font(.subheadline).lineLimit(2)
                HStack(spacing: 6) {
                    if let year = work.publishYear {
                        Text(String(year)).font(.caption).foregroundStyle(.secondary)
                    }
                    if let source = work.source, !source.isEmpty {
                        Text(source).font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            if work.inLibrary {
                Label("In library", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }
}
