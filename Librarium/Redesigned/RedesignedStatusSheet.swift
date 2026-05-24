// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// Picker sheet for `user_book_interactions.read_status`. Same shape
/// as the Rate sheet: tap a row to save and dismiss, "Cancel" backs
/// out without writing.
///
/// Writes go through the outbox: optimistic UI flip on
/// PersistedInteraction + PendingSyncOp + background drain. No direct
/// PUT for this field.
struct RedesignedStatusSheet: View {
    let initialStatus: String
    let onSave: (String) -> Void

    @State private var selectedStatus: String
    @Environment(\.dismiss) private var dismiss

    init(initialStatus: String, onSave: @escaping (String) -> Void) {
        self.initialStatus = initialStatus
        self.onSave = onSave
        self._selectedStatus = State(initialValue: initialStatus)
    }

    private struct Option {
        let value: String
        let label: String
        let dotColour: Color
    }

    private var options: [Option] {
        [
            Option(value: "unread",         label: "Unread",         dotColour: Theme.Colors.appText3),
            Option(value: "want_to_read",   label: "Want to read",   dotColour: Theme.Colors.gold),
            Option(value: "reading",        label: "Reading",        dotColour: Theme.Colors.accent),
            Option(value: "read",           label: "Read",           dotColour: Theme.Colors.good),
            Option(value: "did_not_finish", label: "Did not finish", dotColour: Theme.Colors.bad),
        ]
    }

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Theme.Colors.appLine)
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            Text("Reading status")
                .font(Theme.Fonts.cardTitle)
                .foregroundStyle(Theme.Colors.appText)
                .padding(.top, 4)

            VStack(spacing: 8) {
                ForEach(options, id: \.value) { option in
                    row(for: option)
                }
            }
            .padding(.horizontal, 16)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.appBackground.ignoresSafeArea())
        .presentationDetents([.height(420)])
        .presentationDragIndicator(.hidden)
    }

    @ViewBuilder
    private func row(for option: Option) -> some View {
        Button {
            save(status: option.value)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(option.dotColour)
                    .frame(width: 10, height: 10)
                Text(option.label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText)
                Spacer()
                if option.value == selectedStatus {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.Colors.appCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.Colors.appLine, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func save(status: String) {
        selectedStatus = status
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onSave(status)
        dismiss()
    }
}
