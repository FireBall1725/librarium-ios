// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// Cold-launch splash: books shelve themselves, a rule draws under them,
/// and the wordmark sets.
///
/// Replaces the old welcome-back screen, which only appeared once an
/// account existed — so a fresh install went straight to the account
/// picker with no branding at all, and a returning user got a plain
/// system-tinted card that predated the editorial redesign.
///
/// The motion is doing one job: the app is a shelf, and this is books
/// landing on it. Everything is drawn from `Theme`, so it inherits the
/// same serif and the same indigo the rest of the app uses rather than
/// inventing splash-only styling.
struct BrandSplashView: View {
    /// Shown under the wordmark when someone is already signed in.
    /// Nil on a fresh install, where the tagline takes its place.
    var displayName: String?
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var shelved = false
    @State private var ruleDrawn = false
    @State private var wordmarkIn = false
    @State private var subtitleIn = false
    @State private var glowIn = false
    @State private var leaving = false
    @State private var glowBreathing = false
    @State private var washIn = false
    @State private var drifting = false
    /// Rolled once when the view is created, not per body evaluation, or
    /// the blooms would jump to new places on every render.
    @State private var blooms: [Bloom] = BrandSplashView.makeBlooms()

    /// The mark, at the size the splash wants it. Scales with Dynamic
    /// Type so the brand screen grows with the rest of the app.
    @ScaledMetric(relativeTo: .largeTitle) private var markSize: CGFloat = 78

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "v\(version) (\(build))"
    }

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()

            // Colour lives at the edges, so the middle of the screen
            // stays dark and the mark keeps its contrast. Everything is
            // from the app palette rather than a decorative gradient set
            // invented for this screen.
            colourWash

            // A single soft indigo bloom behind the shelf. Keeps the
            // screen from reading as a flat black rectangle without
            // adding anything the eye has to resolve.
            RadialGradient(
                colors: [Theme.Colors.accent.opacity(0.16), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 320
            )
            .ignoresSafeArea()
            .opacity(glowIn ? (glowBreathing ? 0.72 : 1) : 0)
            .blur(radius: 40)

            VStack(spacing: 0) {
                shelf
                wordmark
            }

            VStack {
                Spacer()
                Text(appVersion)
                    .font(Theme.Fonts.ui(11, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText3)
                    .padding(.bottom, 24)
                    .opacity(subtitleIn ? 1 : 0)
            }
        }
        .opacity(leaving ? 0 : 1)
        .task { await run() }
        // One label for the whole screen: VoiceOver should hear the app
        // name, not four decorative rectangles.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Librarium")
    }

    // MARK: - Colour wash

    /// One blurred bloom pushed out toward an edge.
    private struct Bloom: Identifiable {
        let id: Int
        let colour: Color
        let size: CGFloat
        let x: CGFloat
        let y: CGFloat
        /// Where it drifts to during the hold, as an offset from `x`/`y`.
        let driftX: CGFloat
        let driftY: CGFloat
        /// Seconds for one leg of the drift. Per-bloom so no two move at
        /// the same rate and the wash never reads as a single pulse.
        let driftDuration: Double
    }

    /// Rolled once per launch, so the splash is a little different every
    /// time without ever being wrong.
    ///
    /// The randomness is bounded rather than free. Each bloom is placed
    /// on a ring well outside the mark, one per angular sector with
    /// jitter inside it, so they cannot pile into the middle, wash out
    /// the wordmark, or all land in the same corner. Colours are drawn
    /// from the palette without replacement, because two golds next to
    /// each other looks like a mistake rather than a choice.
    private static func makeBlooms() -> [Bloom] {
        let palette: [Color] = [
            Theme.Colors.accent,
            Theme.Colors.gold,
            Theme.Colors.good,
            Theme.Colors.warn,
            Theme.Colors.accentStrong
        ].shuffled()

        let count = Int.random(in: 4...5)
        // Start the sector wheel at a random angle so the arrangement
        // rotates between launches instead of always beginning top-left.
        let wheelOffset = Double.random(in: 0..<(2 * .pi))
        let sector = (2 * .pi) / Double(count)

        return (0..<count).map { index in
            // Jitter stays inside the sector, so neighbours never swap
            // places or overlap into one blob.
            let angle = wheelOffset
                + sector * Double(index)
                + Double.random(in: (-sector * 0.3)...(sector * 0.3))
            let radius = CGFloat.random(in: 200...330)
            let driftAngle = Double.random(in: 0..<(2 * .pi))
            let driftDistance = CGFloat.random(in: 16...38)

            return Bloom(
                id: index,
                colour: palette[index % palette.count],
                size: CGFloat.random(in: 210...330),
                x: cos(angle) * radius,
                y: sin(angle) * radius,
                driftX: cos(driftAngle) * driftDistance,
                driftY: sin(driftAngle) * driftDistance,
                driftDuration: Double.random(in: 3.0...6.5)
            )
        }
    }

    @ViewBuilder
    private var colourWash: some View {
        ZStack {
            ForEach(blooms) { bloom in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [bloom.colour.opacity(0.85), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: bloom.size / 2
                        )
                    )
                    .frame(width: bloom.size, height: bloom.size)
                    .offset(
                        x: bloom.x + (drifting ? bloom.driftX : 0),
                        y: bloom.y + (drifting ? bloom.driftY : 0)
                    )
                    // Per-bloom animation rather than one withAnimation
                    // around the toggle: that is what lets each drift at
                    // its own speed and in its own direction.
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: bloom.driftDuration)
                                .repeatForever(autoreverses: true),
                        value: drifting
                    )
                    .blur(radius: 50)
                    .opacity(washIn ? 0.6 : 0)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Pieces

    @ViewBuilder
    private var shelf: some View {
        VStack(spacing: 10) {
            // The app's mark, not a bespoke splash drawing. `books.
            // vertical.fill` in accent is the logo everywhere else: the
            // welcome screen uses it, and generate-icon.swift renders the
            // App Store icon from this exact symbol. An invented shape
            // here would be a second logo nobody asked for.
            Image(systemName: "books.vertical.fill")
                .font(.system(size: markSize, weight: .medium))
                .foregroundStyle(
                    // A soft vertical gradient rather than flat accent,
                    // so the mark catches the glow behind it.
                    LinearGradient(
                        colors: [Theme.Colors.accentStrong, Theme.Colors.accent],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Theme.Colors.accent.opacity(0.45), radius: 18)
                // Rises onto the shelf and settles, the same gesture the
                // books had, now carried by the real mark.
                .offset(y: shelved ? 0 : 20)
                .scaleEffect(shelved ? 1 : 0.88)
                .opacity(shelved ? 1 : 0)
                .accessibilityHidden(true)
                .frame(height: markSize * 1.05, alignment: .bottom)

            // The shelf itself, drawn outward from the middle.
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Theme.Colors.appText3, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: ruleDrawn ? 132 : 0, height: 1)
        }
    }

    @ViewBuilder
    private var wordmark: some View {
        VStack(spacing: 6) {
            Text("Librarium")
                .font(Theme.Fonts.display(38, weight: .semibold))
                .foregroundStyle(Theme.Colors.appText)
                .opacity(wordmarkIn ? 1 : 0)
                .offset(y: wordmarkIn ? 0 : 10)

            Text(displayName.map { "Welcome back, \($0)" } ?? "Your shelf, on your terms")
                .font(Theme.Fonts.ui(12, weight: .medium))
                .foregroundStyle(Theme.Colors.appText3)
                .opacity(subtitleIn ? 1 : 0)
        }
        .padding(.top, 22)
    }

    // MARK: - Timeline

    private func run() async {
        // Reduce Motion still gets the splash, just composed rather than
        // performed: no travel, no stagger, only a cross-fade.
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.35)) {
                glowIn = true; shelved = true; ruleDrawn = true
                wordmarkIn = true; subtitleIn = true; washIn = true
            }
            try? await Task.sleep(for: .milliseconds(2700))
            await leave()
            return
        }

        withAnimation(.easeOut(duration: 0.45)) { glowIn = true }
        withAnimation(.easeOut(duration: 0.9)) { washIn = true }

        // Each spine carries its own delay, so one animation call
        // staggers the whole shelf.
        withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) {
            shelved = true
        }

        try? await Task.sleep(for: .milliseconds(420))
        withAnimation(.easeInOut(duration: 0.4)) { ruleDrawn = true }

        try? await Task.sleep(for: .milliseconds(160))
        withAnimation(.easeOut(duration: 0.45)) { wordmarkIn = true }

        try? await Task.sleep(for: .milliseconds(220))
        withAnimation(.easeOut(duration: 0.4)) { subtitleIn = true }

        // The composition is done, so the hold gets a slow breath on the
        // glow. A longer pause on a completely static frame reads as the
        // app having stalled; a little continuing motion reads as a
        // held beat.
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            glowBreathing = true
        }
        // Each bloom carries its own duration, so this toggle just
        // starts them; the .animation modifier on each one owns the
        // speed. This is what carries the longer hold: without it the
        // screen is a still frame and the extra second reads as the
        // app having hung.
        drifting = true

        try? await Task.sleep(for: .milliseconds(2200))
        await leave()
    }

    private func leave() async {
        withAnimation(.easeInOut(duration: 0.42)) { leaving = true }
        try? await Task.sleep(for: .milliseconds(420))
        onDismiss()
    }
}
