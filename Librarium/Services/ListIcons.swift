// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// Draws whatever a list has in its icon field.
///
/// That field has held two different things over time. Shelves used to store an
/// arbitrary emoji, picked with an emoji picker; the web client later moved to
/// a named icon set, so the same column now holds values like `star`. This app
/// rendered the field as text either way, which was fine for an emoji and drew
/// the literal word "star" for anything the web made.
///
/// Both are handled rather than one migrated away, because the old values are
/// real rows in real collections and nothing has rewritten them.
enum ListIcon {
    /// The SF Symbol for a named icon, or nil when the value is not a name.
    ///
    /// The names come from the web client's set, which is deliberately small:
    /// most of an icon set is navigation, and offering that whole would be a
    /// menu of mostly wrong answers.
    static func symbol(for icon: String) -> String? {
        switch icon {
        case "tag":        return "tag"
        case "star":       return "star"
        case "wish":       return "sparkles"
        case "check":      return "checkmark.circle"
        case "clock":      return "clock"
        case "next":       return "bookmark"
        case "lent":       return "arrow.up.right"
        case "books":      return "books.vertical"
        case "libraries":  return "building.columns"
        case "series":     return "square.stack"
        case "gaps":       return "circle.dashed"
        case "suggested":  return "wand.and.stars"
        case "newview":    return "plus.circle"
        default:           return nil
        }
    }

    /// What a list wears when it has said nothing at all.
    static let fallbackSymbol = "tag"
}

/// One list's icon, drawn from whichever of the two shapes it holds.
struct ListIconView: View {
    let icon: String
    let colour: String
    var size: CGFloat = 18

    var body: some View {
        if let symbol = ListIcon.symbol(for: icon) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.85, weight: .medium))
                .foregroundStyle(tint)
        } else if icon.isEmpty {
            Image(systemName: ListIcon.fallbackSymbol)
                .font(.system(size: size * 0.85, weight: .medium))
                .foregroundStyle(tint)
        } else {
            // An emoji from before the named set. Drawn as text because that is
            // what it is; a symbol lookup would fail and fall back, losing a
            // choice someone actually made.
            Text(icon).font(.system(size: size))
        }
    }

    // Color(hex:) falls back to grey on anything it cannot parse, so an empty
    // or malformed value lands on the muted text colour rather than a wrong one.
    private var tint: Color {
        colour.isEmpty ? Theme.Colors.appText2 : Color(hex: colour)
    }
}
