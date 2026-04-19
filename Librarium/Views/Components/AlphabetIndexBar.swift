import SwiftUI

struct AlphabetIndexBar: View {
    let letters: [String]
    let availableLetters: Set<String>
    let selected: String?
    @Binding var dragLetter: String?
    let onSelect: (String?) -> Void

    var body: some View {
        GeometryReader { geo in
            let rowHeight = geo.size.height / CGFloat(max(letters.count, 1))
            VStack(spacing: 0) {
                ForEach(letters, id: \.self) { letter in
                    Text(letter)
                        .font(.system(size: 10, weight: .semibold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundStyle(color(for: letter))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let idx = Int(value.location.y / rowHeight)
                        guard letters.indices.contains(idx) else { return }
                        let letter = letters[idx]
                        if letter != dragLetter {
                            dragLetter = letter
                            if availableLetters.contains(letter) || letter == "#" {
                                onSelect(letter == "#" ? nil : letter)
                            }
                        }
                    }
                    .onEnded { _ in dragLetter = nil }
            )
        }
        .frame(width: 18)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial.opacity(0.6), in: Capsule())
        .sensoryFeedback(.selection, trigger: dragLetter)
    }

    private func color(for letter: String) -> Color {
        if letter == "#" { return selected == nil ? .accentColor : .secondary }
        if letter == selected { return .accentColor }
        return availableLetters.contains(letter) ? .primary : .secondary.opacity(0.35)
    }
}
