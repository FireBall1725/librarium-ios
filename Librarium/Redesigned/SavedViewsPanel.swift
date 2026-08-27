// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// The reader's saved views, down the left.
///
/// A vertical list rather than the row of chips this replaces: a chip row does
/// not survive twenty views, and scrubbing a strip sideways to find one is
/// worse than not having them.
struct SavedViewsPanel: View {
    let views: [SavedList]
    /// The view whose filter matches what is on screen, if any.
    let activeID: String?
    let canSave: Bool
    let onOpen: (SavedList) -> Void
    let onSave: () -> Void
    let onDelete: (SavedList) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if views.isEmpty {
                Text("A view is a filter with a name. Set some filters, then save them here.")
                    .font(Theme.Fonts.ui(13))
                    .foregroundStyle(Theme.Colors.appText3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(views) { view in
                            row(view)
                            Divider().background(Theme.Colors.appLine).padding(.leading, 18)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            Spacer(minLength: 0)
            saveRow
        }
        .padding(.top, 18)
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            Text("Views")
                .font(Theme.Fonts.display(20, weight: .semibold))
                .foregroundStyle(Theme.Colors.appText)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Colors.appText3)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func row(_ view: SavedList) -> some View {
        let active = view.id == activeID
        Button { onOpen(view) } label: {
            HStack(spacing: 10) {
                Image(systemName: view.isDefault ? "pin.fill" : "line.3.horizontal.decrease")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(active ? Theme.Colors.accent : Theme.Colors.appText3)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(view.name)
                        .font(Theme.Fonts.ui(14, weight: active ? .semibold : .medium))
                        .foregroundStyle(active ? Theme.Colors.accentStrong : Theme.Colors.appText)
                        .lineLimit(1)
                    if view.isDefault {
                        // Worth saying rather than leaving to the pin: this is
                        // the one the page opens on, which is a different thing
                        // from the one currently applied.
                        Text("Opens by default")
                            .font(Theme.Fonts.ui(11))
                            .foregroundStyle(Theme.Colors.appText3)
                    }
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(active ? Theme.Colors.accentSoft.opacity(0.5) : Color.clear)
        .swipeActions {
            // Not for the built-in default: deleting it leaves the surface with
            // nothing to open on and no way to put it back.
            if !view.isDefault {
                Button(role: .destructive) { onDelete(view) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private var saveRow: some View {
        Divider().background(Theme.Colors.appLine)
        Button(action: onSave) {
            HStack(spacing: 7) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 13, weight: .semibold))
                Text("Save current filters")
                    .font(Theme.Fonts.ui(13, weight: .medium))
                Spacer()
            }
            .foregroundStyle(canSave ? Theme.Colors.accent : Theme.Colors.appText3)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
    }
}
