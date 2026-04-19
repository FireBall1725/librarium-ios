import SwiftUI
import VisionKit

/// Wraps VisionKit's document scanner. If the user captures more than one page,
/// shows a picker so they can choose the best shot. Single-page captures pass
/// straight through.
struct BookCoverScannerView: View {
    let onScan: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var captured: [UIImage] = []

    var body: some View {
        if captured.isEmpty {
            DocumentScannerRepresentable(
                onFinish: { images in
                    if images.count == 1 {
                        onScan(images[0])
                    } else if !images.isEmpty {
                        captured = images
                    } else {
                        onCancel()
                    }
                },
                onCancel: onCancel
            )
            .ignoresSafeArea()
        } else {
            ScanPickerView(
                images: captured,
                onSelect: { img in onScan(img) },
                onRetake: { captured = [] },
                onCancel: onCancel
            )
        }
    }
}

private struct DocumentScannerRepresentable: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerRepresentable
        init(_ parent: DocumentScannerRepresentable) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.onFinish(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            parent.onCancel()
        }
    }
}

private struct ScanPickerView: View {
    let images: [UIImage]
    let onSelect: (UIImage) -> Void
    let onRetake: () -> Void
    let onCancel: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                        Button { onSelect(image) } label: {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .frame(height: 200)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(.separator), lineWidth: 1)
                                )
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Pick a scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", role: .cancel) { onCancel() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Retake") { onRetake() }
                }
            }
        }
    }
}
