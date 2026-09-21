// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// Which face of the collection is on screen.
///
/// Books, runs and people are three readings of one shelf rather than three
/// places, which is why they share a tab. The web client reaches them from
/// three rows of the same rail; a phone has no rail, so they are segments
/// (librarium-ios-001).
enum CollectionSurface: String, CaseIterable, Hashable {
    case books, series, authors

    var label: String {
        switch self {
        case .books: return "Books"
        case .series: return "Series"
        case .authors: return "Authors"
        }
    }
}

/// The segmented control above the collection.
///
/// Drawn inside each surface's own scroll content rather than pinned above
/// them by the tab: pushing a book has to cover it, and a control that stays
/// put while the screen under it changes belongs to the wrong screen.
struct CollectionSegments: View {
    @Binding var surface: CollectionSurface
    /// Counts beside each name, where the surface knows one. Absent renders
    /// nothing rather than a zero, which beside a full shelf reads as broken.
    var counts: [CollectionSurface: Int] = [:]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CollectionSurface.allCases, id: \.self) { value in
                segment(value)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func segment(_ value: CollectionSurface) -> some View {
        let active = surface == value
        Button {
            surface = value
        } label: {
            Text(title(value))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? Theme.Colors.appText : Theme.Colors.appText2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(active ? Color.white.opacity(0.08) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    private func title(_ value: CollectionSurface) -> String {
        guard let count = counts[value] else { return value.label }
        return "\(value.label) · \(count.formatted())"
    }
}
