// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// What you thought, and what you wrote down for yourself.
///
/// Two fields, deliberately far apart on the screen and labelled with who can
/// see them, because the product's own rule is that a review is visible to
/// everyone who shares the library and a note never leaves your account. A
/// sheet that put them side by side with grey captions would be the one place
/// that mistake is unrecoverable (librarium-ios-064).
struct ReviewSheet: View {
    let initialReview: String
    let initialNotes: String
    /// Both fields at once: they are one round trip to the same row, and
    /// saving them separately means a half-saved sheet on a flaky connection.
    let onSave: (String, String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var review: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field { case review, notes }

    init(initialReview: String, initialNotes: String,
         onSave: @escaping (String, String) async -> String?) {
        self.initialReview = initialReview
        self.initialNotes = initialNotes
        self.onSave = onSave
        _review = State(initialValue: initialReview)
        _notes = State(initialValue: initialNotes)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if let error {
                            InlineBanner(tone: .warn, title: "Not saved", detail: error)
                        }
                        field(
                            title: "Review",
                            caption: "Anyone who shares this library can read this.",
                            icon: "person.2.fill",
                            text: $review,
                            focus: .review
                        )
                        field(
                            title: "Private notes",
                            caption: "Only you. Never sent to other members.",
                            icon: "lock.fill",
                            text: $notes,
                            focus: .notes
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Your review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(isSaving || !changed)
                }
            }
        }
    }

    private var changed: Bool {
        review != initialReview || notes != initialNotes
    }

    @ViewBuilder
    private func field(title: String, caption: String, icon: String,
                       text: Binding<String>, focus target: Field) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(Theme.Fonts.ui(13, weight: .semibold))
            }
            .foregroundStyle(Theme.Colors.appText)
            Text(caption)
                .font(Theme.Fonts.ui(12))
                .foregroundStyle(Theme.Colors.appText3)
            TextEditor(text: text)
                .font(Theme.Fonts.bodySerif(15))
                .foregroundStyle(Theme.Colors.appText)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(10)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.Colors.appLine, lineWidth: 0.5))
                .focused($focus, equals: target)
        }
    }

    private func save() async {
        isSaving = true
        error = nil
        // Trimmed, so a field someone emptied by hand reads as empty to the
        // server rather than as a line of spaces that renders as a blank
        // review nobody can tell is there.
        let failure = await onSave(
            review.trimmingCharacters(in: .whitespacesAndNewlines),
            notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        isSaving = false
        if let failure {
            error = failure
        } else {
            dismiss()
        }
    }
}
