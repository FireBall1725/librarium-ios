// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// Single source of truth for the redesign's colour + type tokens.
///
/// The mockup at `plans/ios-redesign/mockup.html` defines these as CSS
/// custom properties on `:root`; this file mirrors the same names so the
/// design ↔ code mapping stays obvious. New screens reach for
/// `Theme.colors.*` and `Theme.fonts.*` instead of hard-coding values.
///
/// **Editorial fonts** (Cormorant Garamond / Crimson Pro / Cinzel) are
/// requested via `Font.custom` against their PostScript names; until the
/// `.ttf` files are bundled in the app (UIAppFonts in Info.plist), iOS
/// falls back to the built-in system serif (New York). The fallback looks
/// good enough to ship on for v1; we'll embed the editorial faces before
/// the redesign ships.
enum Theme {

    // MARK: - Colour tokens

    enum Colors {
        // Surfaces
        static let appBackground       = Color(hex: 0x0c0d12)
        static let appBackgroundEleva  = Color(hex: 0x16181f)
        static let appCard             = Color(hex: 0x1b1d25)

        // Text — three tiers, no fourth shade
        static let appText             = Color(hex: 0xf1ede2)   // primary
        static let appText2            = Color(hex: 0xb9b3a4)   // body / supporting
        static let appText3            = Color(hex: 0x6e6a5f)   // meta / timestamps

        // Lines
        static let appLine             = Color.white.opacity(0.07)
        static let appLineStrong       = Color.white.opacity(0.13)

        // Accent (indigo-ish)
        static let accent              = Color(hex: 0x8089ff)
        static let accentStrong        = Color(hex: 0xaab1ff)
        static let accentSoft          = Color(red: 128/255, green: 137/255, blue: 255/255, opacity: 0.18)

        // Status — semantic, not decorative
        static let good                = Color(hex: 0x7bd6a8)   // read / success
        static let warn                = Color(hex: 0xffb866)   // overdue / caution
        static let bad                 = Color(hex: 0xff8a8a)   // destructive
        static let gold                = Color(hex: 0xf3c971)   // rating + admin badges
    }

    // MARK: - Type stack

    /// Editorial fonts shipped as bundled `.ttf` files (UIAppFonts in
    /// Info.plist). The PostScript names below map to the family+style
    /// names of the bundled files.
    ///
    /// **Cormorant Garamond** — static cuts: Regular / Medium / SemiBold / Bold.
    /// **Crimson Pro** — variable font, weight axis. We pick a static
    /// weight at the call site by referring to "CrimsonPro" (the family
    /// name) + applying `.weight()`; SwiftUI maps that to the variable axis.
    /// **Cinzel** — variable font, weight axis. Same pattern.
    enum Fonts {
        // Editorial display — Cormorant Garamond.
        static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
            let face: String = {
                switch weight {
                case .bold, .heavy, .black: return "CormorantGaramond-Bold"
                case .semibold:             return "CormorantGaramond-SemiBold"
                case .medium:               return "CormorantGaramond-Medium"
                default:                    return "CormorantGaramond-Regular"
                }
            }()
            return Font.custom(face, size: size, relativeTo: .title)
        }

        // Body serif — Crimson Pro variable font.
        static func bodySerif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            Font.custom("CrimsonPro", size: size, relativeTo: .body)
                .weight(weight)
        }

        // Small-caps label — SF Pro at the call site, uppercased + letter-
        // spaced via `.tracking(...)`. The mockup originally specified
        // Cinzel via `--font-label`, but Cinzel reads too display-face for
        // utility labels (SERVERS / EDITION / CURRENTLY READING) — a
        // clean SF caps treatment matches the rendered mockup better and
        // keeps these chrome bits out of the editorial spotlight.
        static func label(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
            Font.system(size: size, weight: weight, design: .default)
        }

        // UI workhorse — SF Pro. Default for chrome, dense rows, numbers.
        static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            Font.system(size: size, weight: weight, design: .default)
        }

        // Tabular figures — SF Mono for ISBNs / build versions / numbers.
        static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
            Font.system(size: size, weight: weight, design: .monospaced)
        }

        // MARK: Named roles (matching the type-scale table in the mockup)

        static var pageTitle: Font     { display(36, weight: .semibold) }
        static var heroTitle: Font     { display(22, weight: .semibold) }
        static var cardTitle: Font     { display(18, weight: .semibold) }
        static var rowPrimary: Font    { ui(14, weight: .semibold) }
        static var rowMeta: Font       { ui(12, weight: .medium) }
        static var inlineAction: Font  { ui(11, weight: .semibold) }
        static var sectionLabel: Font  { label(11) }
        static var bodyPara: Font      { bodySerif(15) }
    }

    // MARK: - Spacing primitives

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 18
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Radius

    enum Radius {
        static let chip: CGFloat = 999
        static let pill: CGFloat = 14
        static let card: CGFloat = 18
        static let sheet: CGFloat = 24
    }
}

// MARK: - Color hex helper

extension Color {
    /// 0xRRGGBB hex initialiser. `Color(hex: 0x8089ff)` is the most direct
    /// translation of the mockup's CSS hex tokens.
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, opacity: opacity)
    }
}
