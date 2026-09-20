// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// A save error, shown where the eye already is.
///
/// Both edit sheets used to append the message as the last section of a
/// scrolling form. Save sits in the navigation bar, so on anything longer
/// than a screen the reader pressed Save, saw nothing change, and pressed
/// it again (librarium-ios #56). Pinned under the bar, the answer is where
/// the button is.
struct SaveErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // The app's own colours, not the theme's: this sits in sheets that
        // still use the system style as well as in the redesigned dark ones,
        // and a fixed dark card reads as pasted on in the light ones.
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.red.opacity(0.45)).frame(height: 1)
        }
        // Read out as soon as it appears, so the failure is not something
        // only a sighted reader learns about.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

extension View {
    /// Pin a save error under the navigation bar for the whole sheet.
    func saveError(_ message: Binding<String?>) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            if let text = message.wrappedValue {
                SaveErrorBanner(message: text) { message.wrappedValue = nil }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: message.wrappedValue)
    }
}
