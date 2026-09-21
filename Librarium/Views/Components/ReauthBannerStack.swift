// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// Persistent "your session expired" banner for the redesigned screens
/// that need it: one row per account that cannot be used until somebody
/// signs in again. The row itself is `InlineBanner`, which the libraries
/// grid also draws, so the two cannot drift apart the way they had
/// (librarium-ios-002).
///
/// Tap → caller's `onTap` is invoked with the offending account; the
/// caller is expected to present `ReauthSheet(account:)`.
struct ReauthBannerStack: View {
    let accounts: [ServerAccount]
    let onTap: (ServerAccount) -> Void

    var body: some View {
        if !accounts.isEmpty {
            VStack(spacing: 8) {
                ForEach(accounts) { account in
                    bannerRow(for: account)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
    }

    @ViewBuilder
    private func bannerRow(for account: ServerAccount) -> some View {
        InlineBanner(
            tone: .warn,
            title: "\(account.name) — sign in again",
            detail: "Your session expired.",
            actionLabel: "Sign in",
            // Labelled rather than trailing: an unlabelled trailing closure
            // binds to the last closure parameter, which is `onDismiss`, and
            // the banner then draws a dismiss button that quietly signs
            // nobody in.
            action: { onTap(account) }
        )
    }
}
