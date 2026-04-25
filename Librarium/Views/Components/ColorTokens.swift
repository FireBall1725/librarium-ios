import SwiftUI

extension Color {
    /// Foreground color for text rendered on top of a chip whose tint is
    /// `tintHex`. Picks white when the tint is dark and the system label
    /// color when the tint is light, so chips stay legible regardless of
    /// the user-chosen tag color. Falls back to the system label when the
    /// hex can't be parsed.
    static func chipForeground(forTintHex tintHex: String) -> Color {
        guard let luminance = relativeLuminance(forHex: tintHex) else {
            return .primary
        }
        return luminance < 0.55 ? .white : .primary
    }

    /// Background color for a chip whose tint is `tintHex`. Renders the
    /// tint at a fixed opacity so it reads as a tinted surface rather
    /// than a saturated swatch.
    static func chipBackground(forTintHex tintHex: String, opacity: Double = 0.18) -> Color {
        Color(hex: tintHex).opacity(opacity)
    }

    /// Returns `true` when the given hex parses to a perceptually-dark
    /// colour. Used by chip primitives that need to flip their text
    /// colour for legibility.
    static func isDark(hex: String) -> Bool {
        guard let luminance = relativeLuminance(forHex: hex) else { return false }
        return luminance < 0.55
    }

    /// WCAG-style relative luminance for an sRGB hex string. Returns nil
    /// when the input can't be parsed as a 6-digit hex.
    private static func relativeLuminance(forHex hex: String) -> Double? {
        let trimmed = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard trimmed.count == 6 || trimmed.count == 3 else { return nil }
        var int: UInt64 = 0
        guard Scanner(string: trimmed).scanHexInt64(&int) else { return nil }
        let r, g, b: Double
        if trimmed.count == 6 {
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        } else {
            r = Double((int >> 8) & 0xF) * 17 / 255
            g = Double((int >> 4) & 0xF) * 17 / 255
            b = Double(int & 0xF) * 17 / 255
        }
        // Standard WCAG relative-luminance computation, gamma-corrected.
        let lin: (Double) -> Double = { c in
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
}
