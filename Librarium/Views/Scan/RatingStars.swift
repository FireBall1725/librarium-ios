import SwiftUI

/// 10-point rating (0-10) rendered as 5 half-step stars. Each star is split
/// into two `Button` tap targets — left half sets the half value, right half
/// the whole value. Using `Button` (not raw tap gestures) is the reliable
/// way to hit-test inside a Form row; bare `onTapGesture` on clear shapes
/// gets swallowed by the row's selection behaviour.
struct RatingStars: View {
    @Binding var value: Int?
    var starSize: CGFloat = 28
    var spacing: CGFloat = 4

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: spacing) {
                ForEach(1...5, id: \.self) { position in
                    starView(position: position)
                }
            }
            if let v = value {
                Text(format(v))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
            }
            if value != nil {
                Button("Clear") { value = nil }
                    .font(.footnote)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func starView(position: Int) -> some View {
        let halfPoint = position * 2 - 1
        let fullPoint = position * 2
        let state = stateFor(position: position)

        return ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                Button(action: { value = halfPoint }) {
                    Rectangle().fill(Color.clear)
                        .frame(width: starSize * 0.5, height: starSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: { value = fullPoint }) {
                    Rectangle().fill(Color.clear)
                        .frame(width: starSize * 0.5, height: starSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            starGlyph(state: state)
                .font(.system(size: starSize))
                .allowsHitTesting(false)
                .frame(width: starSize, height: starSize)
        }
        .frame(width: starSize, height: starSize)
    }

    private func stateFor(position: Int) -> StarState {
        guard let v = value else { return .empty }
        if v >= position * 2 { return .full }
        if v >= position * 2 - 1 { return .half }
        return .empty
    }

    @ViewBuilder
    private func starGlyph(state: StarState) -> some View {
        switch state {
        case .full:  Image(systemName: "star.fill").foregroundStyle(.yellow)
        case .half:  Image(systemName: "star.leadinghalf.filled").foregroundStyle(.yellow)
        case .empty: Image(systemName: "star").foregroundStyle(.secondary)
        }
    }

    private enum StarState { case full, half, empty }

    private func format(_ v: Int) -> String {
        let stars = Double(v) / 2
        if stars.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", stars)
        }
        return String(format: "%.1f", stars)
    }
}
