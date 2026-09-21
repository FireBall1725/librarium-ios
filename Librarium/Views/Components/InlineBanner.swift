// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// One message, told the same way everywhere.
///
/// Six screens had their own version of "an icon, a line of text and a tinted
/// box", and no two agreed on the icon size, the corner radius or whether the
/// detail line was the same colour as the title. This is the shape they were
/// all approximating (librarium-ios-002).
struct InlineBanner: View {
    enum Tone {
        case info, good, warn, bad

        var colour: Color {
            switch self {
            case .info: return Theme.Colors.accentStrong
            case .good: return Theme.Colors.good
            case .warn: return Theme.Colors.warn
            case .bad:  return Theme.Colors.bad
            }
        }

        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .good: return "checkmark.circle.fill"
            case .warn: return "exclamationmark.triangle.fill"
            case .bad:  return "xmark.octagon.fill"
            }
        }
    }

    let tone: Tone
    let title: String
    /// The second line, when the first one cannot carry the whole answer.
    var detail: String?
    /// What to do about it. A banner that only states a problem leaves the
    /// reader to find the fix themselves.
    var actionLabel: String?
    var action: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            message
            Spacer(minLength: 0)
            buttons
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(tone.colour.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tone.colour.opacity(0.28), lineWidth: 0.5)
        )
    }

    /// Read out as one statement. Split across an icon and two labels,
    /// VoiceOver announces three fragments and leaves the reader to assemble
    /// the message. The buttons stay outside it, or their own labels go into
    /// the same blur.
    @ViewBuilder
    private var message: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tone.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tone.colour)
                // Aligned with the first line of text rather than centred on
                // the whole block: a two-line message with a centred icon
                // reads as an icon with text beside it, not as one statement.
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.Fonts.ui(13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(Theme.Fonts.ui(12, weight: .medium))
                        .foregroundStyle(Theme.Colors.appText2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 4) {
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .font(Theme.Fonts.ui(12, weight: .semibold))
                    .foregroundStyle(tone.colour)
                    .buttonStyle(.plain)
            }
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.Colors.appText3)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
    }
}

#Preview("Tones") {
    VStack(spacing: 12) {
        InlineBanner(tone: .info, title: "Syncing this library",
                     detail: "1,652 books. You can keep using the app.")
        InlineBanner(tone: .good, title: "Saved")
        InlineBanner(tone: .warn, title: "Couldn't load your views",
                     detail: "The server answered, but not with views.",
                     actionLabel: "Retry", action: {})
        InlineBanner(tone: .bad, title: "localhost needs updating",
                     detail: "This screen uses parts of the API that arrived in 26.8.1.",
                     onDismiss: {})
    }
    .padding(18)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.Colors.appBackground)
}
