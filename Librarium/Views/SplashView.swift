import SwiftUI

struct SplashView: View {
    let user: User
    let onDismiss: () -> Void

    @State private var opacity: Double = 1
    @ScaledMetric(relativeTo: .largeTitle) private var logoSize: CGFloat = 80

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build   = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "v\(version) (\(build))"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: logoSize))
                    .foregroundStyle(.tint)
                    .padding(.bottom, 8)
                    .accessibilityHidden(true)

                Text("Welcome back")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Text(user.displayName)
                    .font(.title.bold())
                    .foregroundStyle(.white)

                Text(user.email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if user.isInstanceAdmin {
                    HStack(spacing: 6) {
                        Image(systemName: "shield.fill")
                            .font(.caption2)
                        Text("Instance Admin")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(.tint)
                    .padding(.top, 2)
                }
            }

            VStack {
                Spacer()
                Text(appVersion)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 24)
            }
        }
        .opacity(opacity)
        .onAppear {
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                withAnimation(.easeInOut(duration: 0.5)) { opacity = 0 }
                try? await Task.sleep(for: .seconds(0.5))
                onDismiss()
            }
        }
    }
}
