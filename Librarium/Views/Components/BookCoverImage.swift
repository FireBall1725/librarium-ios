import SwiftUI

struct BookCoverImage: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat

    @Environment(AppState.self) private var appState
    @State private var image: UIImage?
    @State private var didFail = false

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
            } else {
                placeholder
                    .transition(.opacity)
            }
        }
        .frame(width: width, height: height)
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
