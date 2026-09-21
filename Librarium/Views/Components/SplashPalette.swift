// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// The two-colour wash behind a book or a run that has no cover.
///
/// Book detail and series detail each carried their own copy of the same
/// struct, the same six pairs and the same hash, which meant a title could
/// have drawn one gradient on one screen and another on the next as soon as
/// either list was edited (librarium-ios-003).
struct SplashPalette {
    let first: Color
    let second: Color

    /// Mockup order. The first pair is the default the mockup draws; the rest
    /// are here so a shelf of coverless books is not six of the same tile.
    static let all: [SplashPalette] = [
        // Violet + indigo
        SplashPalette(first: Color(hex: 0x8c50c8), second: Color(hex: 0x5064dc)),
        // Forest + teal
        SplashPalette(first: Color(hex: 0x3a8c5a), second: Color(hex: 0x2c8a96)),
        // Rose + amber
        SplashPalette(first: Color(hex: 0xc8508c), second: Color(hex: 0xdc8a50)),
        // Cobalt + violet
        SplashPalette(first: Color(hex: 0x5064dc), second: Color(hex: 0x8c50c8)),
        // Crimson + rust
        SplashPalette(first: Color(hex: 0xc85050), second: Color(hex: 0xa0623a)),
        // Gold + olive
        SplashPalette(first: Color(hex: 0xdcb850), second: Color(hex: 0x8a8c3a))
    ]

    /// Stable per title: the same book gets the same wash on every screen and
    /// after every launch, which a random pick would not.
    static func forTitle(_ title: String) -> SplashPalette {
        var hash: UInt32 = 5381
        for byte in title.utf8 { hash = (hash &* 33) &+ UInt32(byte) }
        return all[Int(hash % UInt32(all.count))]
    }
}

#Preview("Washes") {
    VStack(spacing: 8) {
        ForEach(Array(SplashPalette.all.enumerated()), id: \.offset) { _, palette in
            LinearGradient(colors: [palette.first, palette.second],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    .padding(18)
    .background(Theme.Colors.appBackground)
}
