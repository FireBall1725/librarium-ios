// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// Mockup card #28 — Rate sheet.
///
/// Half-star precision: each star is split into left and right tap
/// zones. Tapping the LEFT half sets the half-star value (1 / 3 / 5 /
/// 7 / 9 on the raw scale), tapping the RIGHT half sets the full-star
/// value (2 / 4 / 6 / 8 / 10). Tap dismisses; "Clear rating" removes
/// the rating entirely. Optional one-line review from the mockup
/// lands in a follow-up.
///
/// Writes go through the outbox: optimistic UI flip + PendingSyncOp +
/// background drain. No direct PUT.
struct RedesignedRateSheet: View {
    let initialRawRating: Int?
    let onSave: (Int?) -> Void

    /// 0-10 half-star integer (matches the api column).
    @State private var selectedRaw: Int
    @Environment(\.dismiss) private var dismiss

    init(initialRawRating: Int?, onSave: @escaping (Int?) -> Void) {
        self.initialRawRating = initialRawRating
        self.onSave = onSave
        self._selectedRaw = State(initialValue: initialRawRating ?? 0)
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

            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { i in
                    starButton(index: i)
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

    @ViewBuilder
    private func starButton(index: Int) -> some View {
        let halfValue = index * 2 - 1
        let fullValue = index * 2

        let iconName: String = {
            if selectedRaw >= fullValue { return "star.fill" }
            if selectedRaw >= halfValue { return "star.leadinghalf.filled" }
            return "star"
        }()

        ZStack {
            Image(systemName: iconName)
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(Theme.Colors.gold)
                .allowsHitTesting(false)

            HStack(spacing: 0) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { save(rawRating: halfValue) }
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { save(rawRating: fullValue) }
            }
        }
        .frame(width: 48, height: 48)
    }

    private func save(rawRating: Int?) {
        selectedRaw = rawRating ?? 0
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onSave(rawRating)
        dismiss()
    }
}
