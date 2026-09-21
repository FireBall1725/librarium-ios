// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// A spinner with something to read beside it.
///
/// Every screen that waits for something drew its own `ProgressView` and its
/// own caption, at four sizes and three tints. The wait is the same wait
/// (librarium-ios-002).
struct LoadingRow: View {
    let label: String
    /// Small sits in a list row or under a header; large owns the screen.
    var size: Size = .small
    /// Centred when it stands in for the whole screen's content, leading
    /// when it sits inside a row that has a left edge to line up with.
    var alignment: Alignment = .leading

    enum Size { case small, large }

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(size == .small ? .small : .regular)
                .tint(Theme.Colors.appText3)
            Text(label)
                .font(Theme.Fonts.ui(size == .small ? 12 : 14, weight: .medium))
                .foregroundStyle(Theme.Colors.appText3)
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .padding(.vertical, size == .small ? 10 : 24)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Sizes") {
    VStack(spacing: 0) {
        LoadingRow(label: "Loading libraries…")
        LoadingRow(label: "Looking that up…", size: .large, alignment: .center)
    }
    .padding(18)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.Colors.appBackground)
}
