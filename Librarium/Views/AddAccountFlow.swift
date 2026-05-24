// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftData
import SwiftUI

/// Account-creation flow used in two contexts:
///   1. OOBE — `ContentView` shows it when `appState.isAuthenticated` is
///      false; the auth flip swaps the root view back to the app shell.
///   2. Profile → Add Server — presented as a sheet; `onComplete` lets
///      the sheet caller dismiss when the user finishes.
///
/// Stages: `choice → (server | liteName)`. Telemetry is no longer part
/// of this flow — it surfaces post-auth from `ContentView` instead so a
/// user who's never seen Librarium isn't asked about data collection
/// before they've even chosen how to use the app.
struct AddAccountFlow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @State private var stage: Stage = .choice

    /// Optional dismiss callback. The OOBE call site leaves this nil and
    /// relies on `appState.isAuthenticated` flipping; the in-app "Add a
    /// server" sheet passes a closure that dismisses the sheet.
    var onComplete: (() -> Void)? = nil

    enum Stage {
        case choice
        case server
        case liteName
    }

    var body: some View {
        switch stage {
        case .choice:
            ChooseAccountTypeView(
                onConnectToServer: { stage = .server },
                onUseLocal: { stage = .liteName }
            )
        case .server:
            AddServerView(
                isFirstTime: true,
                showLocalOption: false,
                onComplete: {
                    onComplete?()
                }
            )
        case .liteName:
            LiteNamePromptView(
                onContinue: { name in
                    createLocalAccount(name: name)
                    onComplete?()
                },
                onBack: { stage = .choice }
            )
        }
    }

    /// Materialise the Lite-mode account + its single starter library.
    /// We pick the library label from the typed name ("Adaléa's Library")
    /// or fall back to a generic when the field is left empty. Once both
    /// rows commit, `appState.isAuthenticated` flips and `ContentView`
    /// swaps in the main app shell — no explicit `stage` advance needed.
    private func createLocalAccount(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let libraryName = trimmed.isEmpty ? "My Library" : "\(trimmed)'s Library"
        let account = appState.addLocalAccount(displayName: libraryName)
        appState.setLocalUserDisplayName(trimmed, for: account.id)
        let library = PersistedLibrary(
            serverAccountID: account.id,
            name: libraryName,
            libraryDescription: "",
            isPublic: false
        )
        modelContext.insert(library)
        try? modelContext.save()
    }
}

// MARK: - Choice screen

/// Single-screen Lite-vs-server fork. Two large tappable cards so the
/// decision reads as one moment, not a multi-step prompt. The hero line
/// up top is the only "welcome" copy — the actual feature explanations
/// live inside each card so the user can compare in one glance. When a
/// local account already exists the Lite card renders disabled so a
/// user can't accidentally end up with two local libraries (we cap Lite
/// at one library per device).
struct ChooseAccountTypeView: View {
    var onConnectToServer: () -> Void
    var onUseLocal: () -> Void

    @Environment(AppState.self) private var appState

    private var hasLocalAccount: Bool {
        appState.accounts.contains(where: { $0.kind == .local })
    }

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    hero
                    optionCard(
                        icon: "server.rack",
                        title: "Connect to a server",
                        body: "Sign in to a self or cloud-hosted Librarium server. Sync across devices, share libraries, and use AI suggestions.",
                        cta: "Sign in",
                        accent: Theme.Colors.accent,
                        action: onConnectToServer
                    )
                    optionCard(
                        icon: "iphone",
                        title: "Use without a server",
                        body: hasLocalAccount
                            ? "You already have a local library on this device. Lite is limited to one."
                            : "Track your books on this device. No account, no signup — your library stays here.",
                        cta: "Get started",
                        accent: Theme.Colors.gold,
                        disabled: hasLocalAccount,
                        action: onUseLocal
                    )
                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 22)
                .padding(.top, 36)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 36))
                .foregroundStyle(Theme.Colors.accent)
                .accessibilityHidden(true)
            Text("Welcome to Librarium")
                .font(Theme.Fonts.heroTitle)
                .foregroundStyle(Theme.Colors.appText)
            Text("How would you like to use it?")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Colors.appText3)
        }
    }

    @ViewBuilder
    private func optionCard(
        icon: String,
        title: String,
        body: String,
        cta: String,
        accent: Color,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 44, height: 44)
                        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    Text(title)
                        .font(Theme.Fonts.cardTitle)
                        .foregroundStyle(Theme.Colors.appText)
                    Spacer(minLength: 0)
                }
                Text(body)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText2)
                    .multilineTextAlignment(.leading)
                HStack {
                    Spacer()
                    Text(cta)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Theme.Colors.appLine, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1.0)
    }
}

// MARK: - Lite name prompt

/// Single-field "what should we call you?" prompt — only reached when
/// the user picked Lite from the choice screen. The field is optional;
/// "Skip" creates the same account but with the generic "My Library"
/// label so the rename path in Profile still works.
private struct LiteNamePromptView: View {
    var onContinue: (String) -> Void
    var onBack: () -> Void

    @State private var name: String = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    field
                    actions
                }
                .padding(.horizontal, 22)
                .padding(.top, 36)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear { nameFocused = true }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "person.fill")
                .font(.system(size: 36))
                .foregroundStyle(Theme.Colors.gold)
                .accessibilityHidden(true)
            Text("What should we call you?")
                .font(Theme.Fonts.heroTitle)
                .foregroundStyle(Theme.Colors.appText)
            Text("We'll use this for greetings and label your library. You can change it any time.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Colors.appText3)
        }
    }

    @ViewBuilder
    private var field: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Your name", text: $name)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($nameFocused)
                .submitLabel(.go)
                .onSubmit { onContinue(name) }
                .padding(14)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.Colors.appLine, lineWidth: 0.5))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.Colors.appText)
                .tint(Theme.Colors.accent)
            if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Your library will be called \"\(name.trimmingCharacters(in: .whitespaces))'s Library\".")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText3)
                    .padding(.leading, 4)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                onContinue(name)
            } label: {
                HStack {
                    Spacer()
                    Text(name.trimmingCharacters(in: .whitespaces).isEmpty ? "Skip" : "Get started")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            Button("Back", action: onBack)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Colors.appText3)
        }
    }
}
