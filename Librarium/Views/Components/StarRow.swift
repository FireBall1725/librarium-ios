// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// Five stars, filled to a rating.
///
/// Three screens each decided for themselves when a star was full, half or
/// empty, which is three chances to round 3.4 differently from 3.6
/// (librarium-ios-002). The rule lives here now.
struct StarRow: View {
    /// 0 to 5, in halves. The api stores the same number doubled; callers
    /// holding that shape use `init(halfPoints:)`.
    let rating: Double
    var size: CGFloat = 12
    var tint: Color = Theme.Colors.gold

    /// The api's 0-10 scale, where 7 is three and a half stars.
    init(halfPoints: Int, size: CGFloat = 12, tint: Color = Theme.Colors.gold) {
        self.init(rating: Double(halfPoints) / 2, size: size, tint: tint)
    }

    init(rating: Double, size: CGFloat = 12, tint: Color = Theme.Colors.gold) {
        self.rating = rating
        self.size = size
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { position in
                Image(systemName: Self.symbol(for: position, rating: rating))
                    .font(.system(size: size))
            }
        }
        .foregroundStyle(tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rating.formatted(.number.precision(.fractionLength(1)))) out of 5")
    }

    /// Full at or above the whole number, half at or above the halfway mark,
    /// empty below it. Deliberately not rounded: 3.4 shows three and a half
    /// stars, not four, because a rating that reads higher than it is makes
    /// the number beside it look wrong.
    static func symbol(for position: Int, rating: Double) -> String {
        let full = Double(position)
        let half = full - 0.5
        if rating >= full { return "star.fill" }
        if rating >= half { return "star.leadinghalf.filled" }
        return "star"
    }
}

#Preview("Ratings") {
    VStack(alignment: .leading, spacing: 10) {
        StarRow(rating: 0)
        StarRow(rating: 2.5)
        StarRow(rating: 3.4)
        StarRow(rating: 5, size: 18)
        StarRow(halfPoints: 7, size: 18)
    }
    .padding(18)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(Theme.Colors.appBackground)
}
