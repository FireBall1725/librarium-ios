// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// Mockup card #29 — Update progress.
///
/// Page slider that drives the api's `progress` JSONB blob. The
/// canonical shape (per `plans/sync-protocol.md`) is
/// `{pages_read?, percent?, position?}`; v1 only writes `pages_read`.
/// Percent renders live from `pages_read / page_count * 100`. The
/// "I just finished it" button maxes the slider and tells the caller
/// to also flip the read-status to `read`.
///
/// Writes go through the outbox: optimistic update on PersistedInteraction
/// + PendingSyncOp.progress + background drain. No direct PUT.
struct RedesignedProgressSheet: View {
    let pageCount: Int?
    let initialPagesRead: Int?
    let onSavePages: (Int?) -> Void
    let onMarkFinished: () -> Void

    @State private var pages: Double
    @Environment(\.dismiss) private var dismiss

    init(
        pageCount: Int?,
        initialPagesRead: Int?,
        onSavePages: @escaping (Int?) -> Void,
        onMarkFinished: @escaping () -> Void
    ) {
        self.pageCount = pageCount
        self.initialPagesRead = initialPagesRead
        self.onSavePages = onSavePages
        self.onMarkFinished = onMarkFinished
        self._pages = State(initialValue: Double(initialPagesRead ?? 0))
    }

    private var percent: Int {
        guard let pc = pageCount, pc > 0 else { return 0 }
        return min(100, Int((pages / Double(pc) * 100.0).rounded()))
    }

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Theme.Colors.appLine)
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            Text("Update progress")
                .font(Theme.Fonts.cardTitle)
                .foregroundStyle(Theme.Colors.appText)
                .padding(.top, 4)

            if let pc = pageCount, pc > 0 {
                pageReadout(pc: pc)
                slider(pc: pc)
                actions(pc: pc)
            } else {
                noPageCountMessage
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .background(Theme.Colors.appBackground.ignoresSafeArea())
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.hidden)
    }

    @ViewBuilder
    private func pageReadout(pc: Int) -> some View {
        VStack(spacing: 4) {
            Text("Page \(Int(pages)) of \(pc)")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Colors.appText)
            Text("\(percent)%")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Colors.appText3)
        }
    }

    @ViewBuilder
    private func slider(pc: Int) -> some View {
        Slider(value: $pages, in: 0...Double(pc), step: 1)
            .tint(Theme.Colors.accent)
    }

    @ViewBuilder
    private func actions(pc: Int) -> some View {
        VStack(spacing: 10) {
            Button {
                save()
            } label: {
                Text("Save")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            Button {
                pages = Double(pc)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onSavePages(pc)
                onMarkFinished()
                dismiss()
            } label: {
                Text("I just finished it")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            Button {
                onSavePages(nil)
                dismiss()
            } label: {
                Text("Clear progress")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText3)
            }
            .buttonStyle(.plain)
            .disabled(initialPagesRead == nil)
        }
    }

    @ViewBuilder
    private var noPageCountMessage: some View {
        Text("This edition has no page count yet. Add one to the edition's details to track reading progress.")
            .font(.system(size: 14))
            .foregroundStyle(Theme.Colors.appText2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.top, 8)
    }

    private func save() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onSavePages(Int(pages))
        dismiss()
    }
}
