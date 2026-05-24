// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// Mockup card #28 — Rate sheet.
///
/// v1: full-star precision only (1-5 stars), mapping to the api's
/// half-star integer scale (1-10) by doubling. Tap a star to save and
/// dismiss; tap "Clear" to remove the rating. Half-star precision and
/// the optional one-line review from the mockup land in a follow-up.
///
/// Writes go through the outbox: optimistic UI flip + PendingSyncOp +
/// background drain. No direct PUT.
struct RedesignedRateSheet: View {
    let initialRawRating: Int?
    let onSave: (Int?) -> Void

    @State private var selectedStars: Int
    @Environment(\.dismiss) private var dismiss

    init(initialRawRating: Int?, onSave: @escaping (Int?) -> Void) {
        self.initialRawRating = initialRawRating
        self.onSave = onSave
        self._selectedStars = State(initialValue: (initialRawRating ?? 0) / 2)
    }

    var body: some View {
        VStack(spacing: 28) {
            Capsule()
                .fill(Theme.Colors.appLine)
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            Text("Rate this book")
                .font(Theme.Fonts.cardTitle)
                .foregroundStyle(Theme.Colors.appText)
                .padding(.top, 4)

            HStack(spacing: 14) {
                ForEach(1...5, id: \.self) { i in
                    Button {
                        save(rawRating: i * 2)
                    } label: {
                        Image(systemName: i <= selectedStars ? "star.fill" : "star")
                            .font(.system(size: 42, weight: .regular))
                            .foregroundStyle(Theme.Colors.gold)
                            .contentShape(Rectangle())
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                save(rawRating: nil)
            } label: {
                Text("Clear rating")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText3)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .disabled(initialRawRating == nil)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.appBackground.ignoresSafeArea())
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.hidden)
    }

    private func save(rawRating: Int?) {
        selectedStars = (rawRating ?? 0) / 2
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onSave(rawRating)
        dismiss()
    }
}
