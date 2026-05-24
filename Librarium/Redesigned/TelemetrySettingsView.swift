// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// Detail view reachable from Profile → Telemetry. Reuses the same hero
/// + "what gets / never gets sent" block as the first-launch opt-in
/// sheet so the user sees the identical promises in both contexts.
/// Pairs the bullets with a prominent toggle card showing the current
/// opt-in state and a recent-signals log so the user can verify what
/// we send is what we promised.
struct TelemetrySettingsView: View {
    @Bindable var telemetry: TelemetryService = TelemetryService.shared
    @State private var confirmClear = false

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    TelemetryFactsView(showHero: true)
                    toggleCard
                    recentSignalsCard
                }
                .padding(.horizontal, 22)
                .padding(.top, 36)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Clear local telemetry log?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { telemetry.clearLog() }
            Button("Cancel", role: .cancel) { }
        }
    }

    // MARK: - Toggle card

    @ViewBuilder
    private var toggleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: optInBinding) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Send anonymous usage data")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Colors.appText)
                    Text(telemetry.optedIn
                         ? "On — signals are being queued and sent."
                         : "Off — nothing is being sent.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Colors.appText3)
                }
            }
            .tint(Theme.Colors.accent)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.Colors.appLine, lineWidth: 0.5)
        )
    }

    // MARK: - Recent signals

    @ViewBuilder
    private var recentSignalsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent signals")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText)
                Spacer()
                Text("\(telemetry.recentSignals.count)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText3)
                    .monospacedDigit()
            }

            if telemetry.recentSignals.isEmpty {
                Text(telemetry.optedIn
                     ? "No signals queued yet on this device."
                     : "Telemetry is off, so nothing's been queued.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.appText3)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(telemetry.recentSignals.enumerated()), id: \.element.id) { index, signal in
                        NavigationLink {
                            TelemetrySignalDetailView(signal: signal)
                        } label: {
                            signalRow(signal)
                        }
                        .buttonStyle(.plain)
                        if index < telemetry.recentSignals.count - 1 {
                            Divider().background(Theme.Colors.appLine)
                        }
                    }
                }
                Button(role: .destructive) {
                    confirmClear = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Clear local log", systemImage: "trash")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.Colors.bad)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }

            Text("This log lives on this device only. Clearing it does not affect signals already delivered.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.appText3)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.Colors.appLine, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func signalRow(_ signal: TelemetrySignal) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(signal.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText)
                Text(signal.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.appText3)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Colors.appText3)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var optInBinding: Binding<Bool> {
        Binding(
            get: { telemetry.optedIn },
            set: { telemetry.setOptIn($0) }
        )
    }
}

/// Tap-through view for a single signal. Shows exactly what was queued
/// (and, if delivered, sent) so a curious user can audit the payload.
struct TelemetrySignalDetailView: View {
    let signal: TelemetrySignal

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    metaCard
                    if !signal.payload.isEmpty { payloadCard }
                    Text("This view shows the entire signal as it sits in the local log. Identical to what the TelemetryDeck SDK is asked to send, plus an anonymous install id, session id, app version, and device class that the SDK appends automatically.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.appText3)
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(signal.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var metaCard: some View {
        VStack(spacing: 0) {
            row("Type", signal.name)
            Divider().background(Theme.Colors.appLine)
            row("Queued at", signal.createdAt.formatted(date: .abbreviated, time: .standard))
            Divider().background(Theme.Colors.appLine)
            row("Recorded", "Handed to TelemetryDeck SDK")
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.Colors.appLine, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var payloadCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Payload")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Colors.appText)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
            ForEach(Array(signal.payload.sorted(by: { $0.key < $1.key }).enumerated()), id: \.offset) { index, item in
                row(item.key, item.value)
                if index < signal.payload.count - 1 {
                    Divider().background(Theme.Colors.appLine)
                }
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.Colors.appLine, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.appText3)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Colors.appText)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
