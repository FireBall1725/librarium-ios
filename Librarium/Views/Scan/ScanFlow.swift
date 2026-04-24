import SwiftUI

/// Top-level scan coordinator. Presented as a full-screen cover from the
/// Libraries tab when the user taps the barcode icon. Drives the flow:
///
///     camera  →  lookup  →  result screen
///       ↑                       │
///       └──────[ done ]─────────┘
///
/// Manual ISBN entry is reachable from the camera's overlay as a sheet, and
/// feeds into the same lookup branch as a barcode scan.
struct ScanFlow: View {
    let libraries: [Library]
    let onDone: () -> Void

    @State private var phase: Phase = .camera
    @State private var showManualEntry = false

    private enum Phase {
        case camera
        case result(isbn: String)
    }

    var body: some View {
        switch phase {
        case .camera:
            ZStack(alignment: .topTrailing) {
                BarcodeScannerView(
                    onScan: { raw in handle(raw: raw) },
                    onCancel: onDone
                )
                .ignoresSafeArea()

                // Mirror the Cancel button's style in BarcodeScannerView — plain
                // white text anchored to the safe area, no pill background.
                Button("Enter manually") { showManualEntry = true }
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .padding(.top, 16)
                    .padding(.trailing, 20)
            }
            .sheet(isPresented: $showManualEntry) {
                ScanManualEntry(
                    onSearch: { isbn in
                        showManualEntry = false
                        handle(raw: isbn)
                    },
                    onCancel: { showManualEntry = false }
                )
            }

        case .result(let isbn):
            ScanResultScreen(isbn: isbn, libraries: libraries, onClose: onDone)
        }
    }

    private func handle(raw: String) {
        let normalized = raw.filter { $0.isNumber || $0 == "X" || $0 == "x" }.uppercased()
        guard !normalized.isEmpty else { return }
        phase = .result(isbn: normalized)
    }
}
