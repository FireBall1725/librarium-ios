// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// The reader's saved filters, as a row of chips above the list.
///
/// A view is a filter with a name, and until now every one made on the web was
/// invisible on the phone: `/me/shelves` returns only lists shared with a
/// library, so a private saved view had nowhere to appear. They are the same
/// rows the web sidebar draws, filtered to the surface being looked at.
struct SavedViewsBar: View {
    let views: [SavedList]
    /// The view whose filter matches what is on screen, if any.
    let activeID: String?
    /// Whether there is anything worth saving. Save stays visible either way;
    /// this only decides whether it can be tapped.
    let canSave: Bool
    let onOpen: (SavedList) -> Void
    let onSave: () -> Void

    var body: some View {
        // Always drawn, rows or not. The web client learned this the hard way:
        // hiding the section when there were no views took the way to make one
        // away with the last one, so deleting everything left no way back. Here
        // it was worse, because a reader with no views saw no row at all and
        // had nothing to tell them views existed.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(views) { view in
                    chip(view)
                }
                if true {
                    Button(action: onSave) {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text(views.isEmpty ? "Save this as a view" : "Save view")
                                .font(Theme.Fonts.ui(13, weight: .medium))
                        }
                        .foregroundStyle(canSave ? Theme.Colors.appText2 : Theme.Colors.appText3)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .foregroundStyle(Theme.Colors.appLineStrong)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                }
            }
            .padding(.horizontal, 22)
        }
    }

    @ViewBuilder
    private func chip(_ view: SavedList) -> some View {
        let active = view.id == activeID
        Button { onOpen(view) } label: {
            HStack(spacing: 5) {
                if view.isDefault {
                    // The one the surface opens on. Marked rather than named,
                    // because "Default" is already its name and saying it twice
                    // in one chip is noise.
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .bold))
                }
                Text(view.name)
                    .font(Theme.Fonts.ui(13, weight: .medium))
            }
            .foregroundStyle(active ? Theme.Colors.accentStrong : Theme.Colors.appText2)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(active ? Theme.Colors.accentSoft : Color.white.opacity(0.06))
            )
            .overlay(Capsule().stroke(active ? Color.clear : Theme.Colors.appLine, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

/// Naming a view before it is saved.
struct SaveViewSheet: View {
    @Binding var name: String
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Saves the filters and sort currently on screen.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.appBackground)
            .navigationTitle("Save view")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.height(220)])
    }
}
