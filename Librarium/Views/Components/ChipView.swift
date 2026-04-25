import SwiftUI

/// Pill-shaped status / metadata chip used across the app. Centralizes the
/// padding, radius, font, and weight conventions so that `TagPill`, the
/// loan row's Active/Returned indicator, the member role badge, and the
/// scan-result status pill all read as the same visual primitive.
///
/// Selection state, dismiss buttons, and tap behaviour stay with the call
/// site — `ChipView` is intentionally a leaf view that just renders the
/// pill so callers can wrap it in a `Button` or compose it inside a row
/// without fighting an opinionated container.
struct ChipView: View {
    let label: String
    var size: Size = .regular
    var foreground: Color = .primary
    var background: Color = Color.secondary.opacity(0.15)

    enum Size { case xsmall, small, regular }

    var body: some View {
        Text(label)
            .font(font)
            .fontWeight(.medium)
            .padding(.horizontal, paddingH)
            .padding(.vertical, paddingV)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
    }

    private var font: Font {
        switch size {
        case .xsmall: return .caption2
        case .small: return .caption
        case .regular: return .subheadline
        }
    }

    private var paddingH: CGFloat {
        switch size {
        case .xsmall: return 6
        case .small: return 8
        case .regular: return 12
        }
    }

    private var paddingV: CGFloat {
        switch size {
        case .xsmall: return 2
        case .small: return 4
        case .regular: return 6
        }
    }
}
