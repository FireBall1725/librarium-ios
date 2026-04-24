import SwiftUI

/// Numeric-keyboard ISBN entry as the fallback for users who can't or don't
/// want to use the camera. Reached from the scan sheet's top-right "Enter
/// manually" button. Not part of the camera module — lives as a child of the
/// scan coordinator so state is siblings, not nested.
struct ScanManualEntry: View {
    let onSearch: (String) -> Void
    let onCancel: () -> Void

    @State private var isbn: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("ISBN", text: $isbn)
                    .font(.title3.monospaced())
                    .keyboardType(.numberPad)
                    .textContentType(.none)
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .focused($focused)

                Button {
                    onSearch(normalized)
                } label: {
                    Text("Search")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)

                Spacer()
            }
            .padding()
            .navigationTitle("Enter ISBN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
            }
            .onAppear { focused = true }
        }
    }

    private var normalized: String {
        isbn.filter { $0.isNumber || $0 == "X" || $0 == "x" }.uppercased()
    }
    private var isValid: Bool {
        normalized.count == 10 || normalized.count == 13
    }
}
