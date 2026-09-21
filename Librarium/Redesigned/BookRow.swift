// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// One book as a row: a small spine, then the words.
///
/// The grid is three covers across and answers "which one is it" by the
/// jacket. A list of 1,600 books whose covers you have never seen answers
/// nothing that way, and the web client offers both for the same reason
/// (librarium-ios-035).
struct BookRow: View {
    let book: Book
    /// The server the cover hangs off, rather than a `Library`. A book can sit
    /// in several libraries and the cross-library list never had to pick one.
    let serverURL: String

    private let coverWidth: CGFloat = 44

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                BookCoverImage(
                    url: coverURL,
                    width: coverWidth,
                    height: coverWidth * 1.5,
                    title: book.title,
                    author: primaryAuthor,
                    readStatus: book.userReadStatus
                )
                // Same rule as the tile: a volume nobody holds is drawn like a
                // book because it is one, and dimmed because it is not on a
                // shelf.
                if isMissing {
                    Color.black.opacity(0.45)
                        .frame(width: coverWidth, height: coverWidth * 1.5)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: coverWidth, height: coverWidth * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: 3))

            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(Theme.Fonts.ui(14, weight: .semibold))
                    .foregroundStyle(isMissing ? Theme.Colors.appText2 : Theme.Colors.appText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let author = primaryAuthor, !author.isEmpty {
                    Text(author)
                        .font(Theme.Fonts.ui(12, weight: .medium))
                        .foregroundStyle(Theme.Colors.appText3)
                        .lineLimit(1)
                }
                if !meta.isEmpty {
                    Text(meta)
                        .font(Theme.Fonts.ui(11, weight: .medium))
                        .foregroundStyle(Theme.Colors.appText3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    /// The row has width the tile does not, so it says what the tile could
    /// only draw as a chip: where it is up to, whether it is out, the score.
    private var meta: String {
        var parts: [String] = []
        if isMissing { parts.append("Missing") }
        if let count = book.activeLoanCount, count > 0 { parts.append("Lent") }
        if let pct = book.userProgressPct, pct > 0 { parts.append("\(Int(pct))%") }
        if let rating = book.userRating, rating > 0 {
            let stars = Double(rating) / 2
            parts.append(stars == stars.rounded()
                         ? "★ \(Int(stars))"
                         : String(format: "★ %.1f", stars))
        }
        return parts.joined(separator: " · ")
    }

    private var isMissing: Bool { book.ownership == "gap" }

    private var primaryAuthor: String? {
        book.contributors
            .first(where: { $0.role.caseInsensitiveCompare("author") == .orderedSame })?.name
            ?? book.contributors.first?.name
    }

    private var coverURL: URL? {
        CoverURL.resolve(book.coverUrl, serverURL: serverURL)
    }
}

/// Grid or rows, remembered per device.
enum CollectionLayout: String, CaseIterable {
    case grid, rows
}
