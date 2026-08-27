// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// A run, collapsed into one tile.
///
/// Sized and shaped like a book tile on purpose: it sits in the same grid, and
/// a row that laid out differently would break the columns wherever a series
/// happened to fall. What marks it as a run is the stacked edge behind the
/// cover and the count on the front, not a different footprint.
struct SeriesGroupTile: View {
    let group: SeriesGroup
    let serverURL: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            cover
            VStack(alignment: .leading, spacing: 2) {
                Text(group.seriesName)
                    .font(Theme.Fonts.ui(12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(Theme.Fonts.ui(11, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText3)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
    }

    /// Owned over the run's length, and how many are read when any are.
    ///
    /// Not `matched`, which is how many the current filter selected: a run
    /// filtered to unread volumes would read "3 of 74" and look like a
    /// collection three volumes deep.
    private var subtitle: String {
        var parts: [String] = []
        if let total = group.totalCount, total > 0 {
            parts.append("\(group.owned) of \(total)")
        } else {
            parts.append(group.owned == 1 ? "1 vol" : "\(group.owned) vols")
        }
        if group.read > 0 { parts.append("\(group.read) read") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var cover: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = w * 1.5
            ZStack(alignment: .topTrailing) {
                // Two offset slabs behind the cover, so a run reads as a stack
                // before anybody gets to the count under it.
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.Colors.appCard)
                    .frame(width: w - 10, height: h - 10)
                    .offset(x: 8, y: 8)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.Colors.appBackgroundEleva)
                    .frame(width: w - 6, height: h - 6)
                    .offset(x: 4, y: 4)

                BookCoverImage(
                    url: CoverURL.resolve(group.coverUrl, serverURL: serverURL),
                    width: w - 8, height: h - 8,
                    title: group.seriesName, author: nil, readStatus: nil
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))

                if group.matched > 0 {
                    Text("\(group.matched)")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.appBackground)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.Colors.accentStrong))
                        .padding(6)
                }
            }
            .frame(width: w, height: h, alignment: .topLeading)
        }
        .aspectRatio(2.0/3.0, contentMode: .fit)
    }
}
