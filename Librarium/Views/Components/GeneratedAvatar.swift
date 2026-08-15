// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// A per-account avatar derived from the account itself.
///
/// iOS gives a third-party app no way to reach the user's Memoji or Apple
/// ID picture: `unifiedMeContactWithKeysToFetch` is macOS-only, and the
/// Memoji symbols in UIKit are private. Rather than make everyone pick a
/// photo, the avatar is generated, so each account gets its own colours
/// without anyone being asked for anything.
///
/// The seed should be the account's stable id, not its name. Names get
/// edited; an avatar that changes colour because someone fixed a typo
/// looks broken.
struct GeneratedAvatar: View {
    /// Stable identity. Same seed gives the same avatar on every device
    /// and every launch.
    let seed: String
    /// Letter drawn over the gradient. Usually the display name's first
    /// character.
    let initial: String
    let size: CGFloat

    init(seed: String, initial: String, size: CGFloat = 40) {
        self.seed = seed
        self.initial = initial
        self.size = size
    }

    var body: some View {
        let palette = Self.palette(for: seed)
        ZStack {
            LinearGradient(
                colors: [palette.top, palette.bottom],
                startPoint: palette.startPoint,
                endPoint: palette.endPoint
            )

            // A soft off-centre highlight so the disc reads as a lit
            // object rather than a flat swatch. Its position comes from
            // the seed too, so two accounts sharing a palette still
            // differ.
            RadialGradient(
                colors: [.white.opacity(0.28), .clear],
                center: palette.highlight,
                startRadius: 0,
                endRadius: size * 0.62
            )

            Text(initial.isEmpty ? "?" : initial)
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.28), radius: 1, y: 0.5)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
        .shadow(color: palette.bottom.opacity(0.38), radius: size * 0.14, y: 2)
        .accessibilityHidden(true)
    }

    // MARK: - Derivation

    struct Palette {
        let top: Color
        let bottom: Color
        let startPoint: UnitPoint
        let endPoint: UnitPoint
        let highlight: UnitPoint
    }

    /// Curated pairs rather than a random hue.
    ///
    /// Free-running hue produces olive and mustard against this dark
    /// UI, and roughly a third of the wheel is unreadable behind white
    /// text. These are all drawn from the app palette or sit beside it,
    /// so any account's avatar still looks like it belongs to Librarium.
    private static let pairs: [(Color, Color)] = [
        (Color(hex: 0x8089ff), Color(hex: 0x5a64e8)),   // indigo, the house accent
        (Color(hex: 0x7bd6a8), Color(hex: 0x3f9c78)),   // green
        (Color(hex: 0xf3c971), Color(hex: 0xd09a3c)),   // gold
        (Color(hex: 0xff8a8a), Color(hex: 0xd4585f)),   // rose
        (Color(hex: 0x6fc3e8), Color(hex: 0x3b86b8)),   // sky
        (Color(hex: 0xc79bf0), Color(hex: 0x8f5fc4)),   // violet
        (Color(hex: 0xffb866), Color(hex: 0xd97f3a)),   // amber
        (Color(hex: 0x9ad4c0), Color(hex: 0x4f9d92))    // sea
    ]

    private static let directions: [(UnitPoint, UnitPoint)] = [
        (.topLeading, .bottomTrailing),
        (.top, .bottom),
        (.topTrailing, .bottomLeading),
        (.leading, .trailing)
    ]

    private static let highlights: [UnitPoint] = [
        UnitPoint(x: 0.3, y: 0.25),
        UnitPoint(x: 0.7, y: 0.3),
        UnitPoint(x: 0.35, y: 0.7),
        UnitPoint(x: 0.65, y: 0.68)
    ]

    static func palette(for seed: String) -> Palette {
        let h = fnv1a(seed)
        let pair = pairs[Int(h % UInt64(pairs.count))]
        let direction = directions[Int((h >> 8) % UInt64(directions.count))]
        let highlight = highlights[Int((h >> 16) % UInt64(highlights.count))]
        return Palette(
            top: pair.0,
            bottom: pair.1,
            startPoint: direction.0,
            endPoint: direction.1,
            highlight: highlight
        )
    }

    /// FNV-1a, written out rather than using `hashValue`.
    ///
    /// Swift seeds `Hashable` randomly per process, so `"abc".hashValue`
    /// differs between launches. An avatar built on that would change
    /// colour every time the app started, which is the one thing it
    /// must never do.
    private static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
