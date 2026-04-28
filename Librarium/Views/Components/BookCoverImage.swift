import SwiftUI

struct BookCoverImage: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    /// Optional title — when supplied, a missing/failed cover renders a
    /// generated "book jacket" placard using the title rather than the
    /// generic icon placeholder. Legacy call sites that pass nil keep
    /// the old icon behaviour.
    let title: String?
    /// Optional author — rendered under the title on generated covers
    /// when present. Ignored when title is nil.
    let author: String?
    /// Optional read-status flag overlay. When set to "read" / "reading"
    /// / "did_not_finish" the cover renders a coloured corner triangle
    /// (matching the web's `BookCover` indicator). Sites that don't want
    /// the flag (e.g. the libraries-page fanned cover stack) leave it nil.
    let readStatus: String?

    @Environment(AppState.self) private var appState
    @State private var image: UIImage?
    @State private var didFail = false

    init(
        url: URL?,
        width: CGFloat,
        height: CGFloat,
        title: String? = nil,
        author: String? = nil,
        readStatus: String? = nil
    ) {
        self.url = url
        self.width = width
        self.height = height
        self.title = title
        self.author = author
        self.readStatus = readStatus
    }

    // Match the cover URL against stored accounts to find the right Bearer token.
    private var token: String? {
        guard let urlString = url?.absoluteString else { return nil }
        return appState.accounts.first(where: { urlString.hasPrefix($0.url) })?.accessToken
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else if let title, !title.isEmpty {
                GeneratedCover(title: title, author: author, width: width, height: height)
                    .transition(.opacity)
            } else {
                placeholder
                    .transition(.opacity)
            }
        }
        .frame(width: width, height: height)
        // Status flag is overlaid BEFORE the rounded clip so the
        // triangle's outer corner follows the cover's curve.
        .overlay(alignment: .topTrailing) {
            if let readStatus, !readStatus.isEmpty {
                CornerStatusFlag(status: readStatus, size: max(20, width * 0.26))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .animation(.easeInOut(duration: 0.18), value: image == nil)
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        image = nil
        didFail = false
        guard let url else { return }
        var req = URLRequest(url: url)
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let loaded = UIImage(data: data) else {
            didFail = true
            return
        }
        image = loaded
    }

    private var placeholder: some View {
        ZStack {
            // Soft vertical gradient reads less harshly than a flat fill while
            // a cover loads, and gives the failed-load icon something to sit on.
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(
                    colors: [
                        Color(.tertiarySystemFill),
                        Color(.quaternarySystemFill)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            Image(systemName: didFail ? "exclamationmark.triangle.fill" : "book.closed.fill")
                .foregroundStyle(didFail ? Color.orange.opacity(0.6) : Color.secondary.opacity(0.5))
                .font(.system(size: width * 0.32))
        }
    }
}

/// Title-bearing fallback rendered when a book has no cover image (or the
/// image failed to load). Picks a deterministic palette from the title
/// string so the same book always gets the same jacket. Designed to slot
/// in next to real covers without looking out of place — editorial serif
/// title, soft gradient, hairline border.
private struct GeneratedCover: View {
    let title: String
    let author: String?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let palette = Self.palette(for: title)
        // Title-only at very small widths (44pt list rows etc.); add author
        // and decorative rules once we have room. The thresholds keep tiny
        // covers legible by dropping non-essential ornament.
        let showAuthor = width >= 60 && (author?.isEmpty == false)
        let showRules  = width >= 80
        let titleSize  = max(8, min(width * 0.13, 16))
        let authorSize = max(7, min(width * 0.085, 11))

        ZStack {
            LinearGradient(
                colors: [palette.top, palette.bottom],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            VStack(spacing: max(2, height * 0.025)) {
                Spacer(minLength: 0)
                if showRules {
                    Rectangle()
                        .fill(palette.ink.opacity(0.45))
                        .frame(height: 0.5)
                        .padding(.horizontal, width * 0.18)
                }
                Text(title)
                    .font(Theme.Fonts.display(titleSize, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(width >= 80 ? 4 : 3)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, width * 0.10)
                if showAuthor, let author {
                    Text(author.uppercased())
                        .font(Theme.Fonts.label(authorSize))
                        .tracking(0.8)
                        .foregroundStyle(palette.ink.opacity(0.7))
                        .lineLimit(1)
                        .padding(.horizontal, width * 0.10)
                }
                if showRules {
                    Rectangle()
                        .fill(palette.ink.opacity(0.45))
                        .frame(height: 0.5)
                        .padding(.horizontal, width * 0.18)
                }
                Spacer(minLength: 0)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(palette.ink.opacity(0.18), lineWidth: 0.5)
        )
    }

    private struct Palette {
        let top: Color
        let bottom: Color
        let ink: Color
    }

    /// 6 jewel-tone palettes tuned for the dark editorial theme. Picked
    /// deterministically from a stable hash of the title so the same book
    /// always renders with the same jacket. Split into individual lets
    /// because a 6-element array literal of `Color(hex:)` calls trips
    /// Swift's type-checker timeout.
    private static let p0 = Palette(top: Color(hex: 0x2a1d3a), bottom: Color(hex: 0x1d1f2c), ink: Color(hex: 0xf1ede2))
    private static let p1 = Palette(top: Color(hex: 0x1f2a1f), bottom: Color(hex: 0x1a2e35), ink: Color(hex: 0xf1ede2))
    private static let p2 = Palette(top: Color(hex: 0x2a1d24), bottom: Color(hex: 0x1f1c2e), ink: Color(hex: 0xf1ede2))
    private static let p3 = Palette(top: Color(hex: 0x33271a), bottom: Color(hex: 0x1f1d18), ink: Color(hex: 0xf3c971))
    private static let p4 = Palette(top: Color(hex: 0x1a2630), bottom: Color(hex: 0x1f1d2c), ink: Color(hex: 0xaab1ff))
    private static let p5 = Palette(top: Color(hex: 0x2e1a1a), bottom: Color(hex: 0x1f1818), ink: Color(hex: 0xff8a8a))
    private static let palettes: [Palette] = [p0, p1, p2, p3, p4, p5]

    private static func palette(for title: String) -> Palette {
        var hash: UInt32 = 5381
        for byte in title.utf8 {
            hash = (hash &* 33) &+ UInt32(byte)
        }
        return palettes[Int(hash % UInt32(palettes.count))]
    }
}

// MARK: - Corner status flag

/// Top-right triangular flag indicating the user's read status on a cover.
/// Mirrors the web's `BookCover` treatment: green check for read, blue
/// book glyph for reading, amber X for did_not_finish. Used by sites
/// across the redesigned UI (books grid, home, search, detail) so the
/// status is visible at a glance everywhere a cover appears.
struct CornerStatusFlag: View {
    let status: String
    let size: CGFloat

    var body: some View {
        if let style = Self.style(for: status) {
            ZStack {
                CornerTriangle()
                    .fill(style.color)
                Image(systemName: style.icon)
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(.white)
                    // Centre the icon inside the visible (top-right)
                    // half of the bounding box.
                    .offset(x: size * 0.22, y: -size * 0.22)
            }
            .frame(width: size, height: size)
        }
    }

    private struct Style { let color: Color; let icon: String }

    private static func style(for status: String) -> Style? {
        switch status {
        case "read":           return Style(color: Color(hex: 0x22c55e), icon: "checkmark")
        case "reading":        return Style(color: Color(hex: 0x3b82f6), icon: "book.fill")
        case "did_not_finish": return Style(color: Color(hex: 0xf59e0b), icon: "xmark")
        default:               return nil
        }
    }
}

/// Right-triangle filling the top-right corner of its bounding box.
/// Hypotenuse runs from top-left to bottom-right.
struct CornerTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
