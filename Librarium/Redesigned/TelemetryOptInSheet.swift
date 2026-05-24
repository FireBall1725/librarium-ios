// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// Shown the first time the user reaches the authenticated app (and on
/// upgrade if they never made a telemetry decision). Lays out exactly
/// what gets sent, what doesn't, and offers an enable / decline pair.
/// The same decision can be flipped from `TelemetrySettingsView` later.
struct TelemetryOptInSheet: View {
    let onEnable: () -> Void
    let onDecline: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    TelemetryFactsView(showHero: true)
                    Text("You can change this any time in Profile → Telemetry.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.appText3)
                }
                .padding(.horizontal, 22)
                .padding(.top, 36)
                .padding(.bottom, 180)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) { actionBar }
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        VStack(spacing: 12) {
            Button {
                onEnable()
                dismiss()
            } label: {
                HStack {
                    Spacer()
                    Text("Enable telemetry")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button {
                onDecline()
                dismiss()
            } label: {
                Text("Not now")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 22)
        .background(Theme.Colors.appBackground.opacity(0.95))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.Colors.appLine)
                .frame(height: 0.5)
        }
    }

}

/// Reusable hero + "what gets / never gets sent" block. Drawn the same
/// way in the first-launch opt-in sheet and the in-app telemetry
/// settings screen so the copy stays in sync between the two surfaces.
/// `showHero` toggles the chart-icon + headline + description block —
/// the settings screen can pair the bullets with a different header
/// (e.g., the current opt-in state) when needed.
struct TelemetryFactsView: View {
    var showHero: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if showHero { hero }
            sentSection
            notSentSection
        }
    }

    @ViewBuilder
    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 36))
                .foregroundStyle(Theme.Colors.accent)
                .accessibilityHidden(true)
            Text("Help improve Librarium")
                .font(Theme.Fonts.heroTitle)
                .foregroundStyle(Theme.Colors.appText)
            Text("Anonymous usage telemetry tells us which parts of Librarium are actually used and where the rough edges are. It's opt-in and off by default.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Colors.appText3)
        }
    }

    @ViewBuilder
    private var sentSection: some View {
        section(title: "What gets sent", systemImage: "checkmark.circle.fill", tint: Theme.Colors.good) {
            bullet("Names of features you tap (e.g., \"opened a book\", \"rated a book\")")
            bullet("Your app version and device class (e.g., iPhone 17 Pro Max, iOS 26.1)")
            bullet("An anonymous install id that resets when you uninstall")
            bullet("A short session id that resets on every cold launch")
        }
    }

    @ViewBuilder
    private var notSentSection: some View {
        section(title: "What never gets sent", systemImage: "xmark.circle.fill", tint: Theme.Colors.bad) {
            bullet("Book titles, ISBNs, authors, covers, descriptions")
            bullet("Your ratings, reviews, notes, reading progress")
            bullet("Library names, member names, server URLs")
            bullet("Search queries, scan results, anything you type")
            bullet("Any identifier that could be traced back to you or your library")
        }
    }

    @ViewBuilder
    private func section(
        title: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText)
            }
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
        }
    }

    @ViewBuilder
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(Theme.Colors.appText3)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.appText2)
        }
    }
}
