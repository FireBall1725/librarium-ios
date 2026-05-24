// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI

/// Detail view reachable from Profile → Telemetry. Shows the current
/// opt-in state, lets the user flip it, and surfaces the local log of
/// recent signals (with the full payload of each, tappable) so they
/// can verify what we send is what we promised.
struct TelemetrySettingsView: View {
    @Bindable var telemetry: TelemetryService = TelemetryService.shared
    @State private var confirmClear = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: optInBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Send anonymous usage data")
                            .font(.system(size: 15, weight: .medium))
                        Text("Helps us see which features are actually used.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Colors.appText3)
                    }
                }
            }

            Section("What we send") {
                bullet("Names of features you tap")
                bullet("App version and device class")
                bullet("An anonymous install id")
                bullet("A short session id")
            }

            Section("What we never send") {
                bullet("Book titles, ISBNs, authors")
                bullet("Ratings, reviews, notes, reading progress")
                bullet("Library or member names")
                bullet("Search queries, anything you type")
            }

            Section {
                if telemetry.recentSignals.isEmpty {
                    Text(telemetry.optedIn
                         ? "No signals queued yet on this device."
                         : "Telemetry is off, so nothing's been queued.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.appText3)
                } else {
                    ForEach(telemetry.recentSignals) { signal in
                        NavigationLink {
                            TelemetrySignalDetailView(signal: signal)
                        } label: {
                            signalRow(signal)
                        }
                    }
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Text("Clear local log")
                    }
                }
            } header: {
                Text("Recent signals (last \(telemetry.recentSignals.count))")
            } footer: {
                Text("This log is on this device only. Clearing it does not affect signals already delivered.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.appText3)
            }
        }
        .navigationTitle("Telemetry")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Clear local telemetry log?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { telemetry.clearLog() }
            Button("Cancel", role: .cancel) { }
        }
    }

    private var optInBinding: Binding<Bool> {
        Binding(
            get: { telemetry.optedIn },
            set: { telemetry.setOptIn($0) }
        )
    }

    @ViewBuilder
    private func signalRow(_ signal: TelemetrySignal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(signal.name)
                .font(.system(size: 14, weight: .medium))
            Text(signal.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.appText3)
        }
    }

    @ViewBuilder
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(Theme.Colors.appText3)
            Text(text).font(.system(size: 13))
        }
    }
}

/// Tap-through view for a single signal. Shows exactly what was queued
/// (and, if delivered, sent) so a curious user can audit the payload.
struct TelemetrySignalDetailView: View {
    let signal: TelemetrySignal

    var body: some View {
        List {
            Section {
                row("Type", signal.name)
                row("Queued at", signal.createdAt.formatted(date: .abbreviated, time: .standard))
                row("Recorded", "Handed to TelemetryDeck SDK")
            }
            if !signal.payload.isEmpty {
                Section("Payload") {
                    ForEach(signal.payload.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        row(key, value)
                    }
                }
            }
            Section {
                Text("This view shows the entire signal as it sits in the local log. Identical to what the TelemetryDeck SDK is asked to send, plus an anonymous install id, session id, app version, and device class that the SDK appends automatically.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.appText3)
            }
        }
        .navigationTitle(signal.name)
        .navigationBarTitleDisplayMode(.inline)
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
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}
