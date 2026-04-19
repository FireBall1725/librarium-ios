import SwiftUI

struct BookCoverImage: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat

    @Environment(AppState.self) private var appState
    @State private var image: UIImage?

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
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        image = nil
        guard let url else { return }
        var req = URLRequest(url: url)
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let loaded = UIImage(data: data) else { return }
        image = loaded
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
            Image(systemName: "book.closed.fill")
                .foregroundStyle(.tertiary)
                .font(.system(size: width * 0.35))
        }
    }
}
