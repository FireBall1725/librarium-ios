// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// Which collection to open.
///
/// Two servers are two collections that happen to be reachable from the same
/// phone. Their libraries, tags, lists and saved views are each their own, and
/// a view saved on one means nothing applied to books from the other. Merging
/// them produced a shelf that belonged to nobody; picking one produces a shelf
/// that behaves exactly like the web client pointed at that server.
///
/// Only shown when there is more than one. Making somebody choose from a list
/// of one is a screen that exists to be dismissed.
struct SourcePickerView: View {
    @Environment(AppState.self) private var appState
    /// Nil at launch, when there is nothing to go back to.
    var onCancel: (() -> Void)?

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    VStack(spacing: 12) {
                        ForEach(appState.sources) { source in
                            card(source)
                        }
                    }
                    .padding(.horizontal, 22)
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .topTrailing) {
            if let onCancel {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.appText2)
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 18)
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Librarium")
                .font(Theme.Fonts.ui(12, weight: .medium))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.appText3)
            Text("Open a collection")
                .font(Theme.Fonts.pageTitle)
                .foregroundStyle(Theme.Colors.appText)
            Text("Each one has its own libraries, lists and saved views.")
                .font(Theme.Fonts.ui(13, weight: .medium))
                .foregroundStyle(Theme.Colors.appText3)
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private func card(_ source: ServerAccount) -> some View {
        let active = appState.activeSource?.id == source.id
        Button {
            appState.setActiveSource(id: source.id)
            onCancel?()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: source.isServerBacked ? "server.rack" : "iphone")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 44, height: 44)
                    .background(Theme.Colors.accentSoft, in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 3) {
                    Text(source.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Colors.appText)
                        .lineLimit(1)
                    Text(subtitle(source))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(source.needsReauth ? Theme.Colors.warn : Theme.Colors.appText3)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if active {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .padding(14)
            .background(Theme.Colors.appCard, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(active ? Theme.Colors.accent.opacity(0.5) : Theme.Colors.appLine,
                            lineWidth: active ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    /// The host, or what Lite actually is. "Local" says nothing; "On this
    /// iPhone, not synced" says both where the books are and what happens to
    /// them if the phone goes in a lake.
    private func subtitle(_ source: ServerAccount) -> String {
        if source.needsReauth { return "Signed out — tap to sign back in" }
        guard source.isServerBacked else { return "On this iPhone" }
        return URL(string: source.url)?.host ?? source.url
    }
}
