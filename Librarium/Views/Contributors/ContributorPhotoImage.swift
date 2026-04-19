import SwiftUI

struct ContributorPhotoImage: View {
    let url: URL?
    let size: CGFloat

    @Environment(AppState.self) private var appState
    @State private var image: UIImage?

    private var token: String? {
        guard let urlString = url?.absoluteString else { return nil }
        return appState.accounts.first(where: { urlString.hasPrefix($0.url) })?.accessToken
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: url) { await loadImage() }
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
            Circle().fill(.quaternary)
            Image(systemName: "person.fill")
                .foregroundStyle(.tertiary)
                .font(.system(size: size * 0.45))
        }
    }
}
