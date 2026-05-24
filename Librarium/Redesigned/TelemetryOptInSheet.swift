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

    @State private var showExample = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    sentSection
                    notSentSection
                    exampleSection
                    Text("You can change this any time in Profile → Telemetry.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.appText3)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
            .background(Theme.Colors.appBackground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { actionBar }
            .navigationTitle("Help improve Librarium")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 32))
                .foregroundStyle(Theme.Colors.accent)
            Text("Anonymous usage telemetry helps us see which parts of Librarium are actually used and where the rough edges are. It is opt-in and off by default.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.Colors.appText)
        }
        .padding(.top, 4)
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
    private var exampleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { showExample.toggle() }
            } label: {
                HStack {
                    Image(systemName: showExample ? "chevron.down" : "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                    Text(showExample ? "Hide example signal" : "See an example signal")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Theme.Colors.accent)
            }
            .buttonStyle(.plain)

            if showExample {
                Text(exampleJSON)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.Colors.appText2)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Theme.Colors.appCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Theme.Colors.appLine, lineWidth: 0.5)
                            )
                    )
            }
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        VStack(spacing: 10) {
            Button {
                onEnable()
                dismiss()
            } label: {
                Text("Enable telemetry")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            Button {
                onDecline()
                dismiss()
            } label: {
                Text("Not now")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 22)
        .background(.regularMaterial)
    }

    // MARK: - Helpers

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

    private var exampleJSON: String {
        """
        TelemetryDeck.signal(
            "book_detail_opened",
            parameters: ["media_type": "manga"]
        )

        // The SDK then attaches automatically:
        //   anonymous install id, session id,
        //   app version, device class.
        """
    }
}
