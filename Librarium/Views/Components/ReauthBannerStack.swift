// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// Persistent "your session expired" banner for the redesigned screens
/// that need it. The libraries grid has its own copy of this logic for
/// historical reasons; everywhere else (Home, Search, Series) pulls
/// this component so the look + behaviour stays in lockstep.
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
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Colors.warn)
                .frame(width: 32, height: 32)
                .background(Color.black.opacity(0.2), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("\(account.name) — sign in again")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText)
                    .lineLimit(1)
                Text("Your session expired.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Sign in") { onTap(account) }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Colors.warn)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.08), in: Capsule())
                .overlay(Capsule().stroke(Theme.Colors.warn.opacity(0.4), lineWidth: 0.5))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: 0xffb866, opacity: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Theme.Colors.warn.opacity(0.3), lineWidth: 0.5)
                )
        )
    }
}
