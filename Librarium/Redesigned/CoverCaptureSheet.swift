// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import PhotosUI
import SwiftUI
import UIKit

/// Photograph a book's cover, or pick one from the library, and send it up.
///
/// `BookService.uploadCover` has existed since covers did, with nothing
/// calling it: the detail view's "Scan cover" set a flag that presented
/// nothing (librarium-ios #34). This is the missing half.
///
/// The image is downscaled and re-encoded before it leaves the phone. A
/// modern camera hands back something like 4000 × 3000, and a cover is read
/// at a few hundred points, so the full frame is megabytes of detail nobody
/// sees and a slow upload on a phone connection.
struct CoverCaptureSheet: View {
    let library: Library
    let bookId: String
    let bookTitle: String
    /// Called after the server has the new cover, so the caller can reload
    /// and bust its image cache.
    let onUploaded: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var pick: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isUploading = false
    @State private var error: String?

    /// The long edge a stored cover is worth keeping. Roughly three times
    /// the largest size any screen in the app draws one at.
    private let maxEdge: CGFloat = 1600

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                preview
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.bad)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                controls
                Spacer(minLength: 0)
            }
            .padding(.top, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Colors.appBackground)
            .navigationTitle("Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isUploading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isUploading ? "Saving…" : "Use") { Task { await upload() } }
                        .disabled(image == nil || isUploading)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CoverCamera { taken in
                    image = taken
                    showCamera = false
                } onCancel: {
                    showCamera = false
                }
                .ignoresSafeArea()
            }
            .onChange(of: pick) { _, item in
                guard let item else { return }
                Task {
                    // A picked asset can be HEIC or anything else Photos
                    // holds; decoding to UIImage normalises it before the
                    // JPEG encode below.
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let picked = UIImage(data: data) {
                        image = picked
                    } else {
                        error = "That image could not be read."
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.Colors.appCard)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.Colors.appLine, lineWidth: 0.5))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Theme.Colors.appText3)
                    Text(bookTitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.appText3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                }
            }
        }
        .frame(maxWidth: 260)
        .frame(height: 380)
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 10) {
            // Simulators have no camera, and a button that opens a black
            // screen is worse than one that is not there.
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    error = nil
                    showCamera = true
                } label: {
                    Label(image == nil ? "Take a photo" : "Retake", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            PhotosPicker(selection: $pick, matching: .images, photoLibrary: .shared()) {
                Label("Choose a photo", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 24)
        .disabled(isUploading)
    }

    private func upload() async {
        guard let image, let data = jpeg(from: image) else { return }
        isUploading = true
        error = nil
        do {
            let client = appState.makeClient(serverURL: library.serverURL)
            try await BookService(client: client).uploadCover(
                libraryId: library.id, bookId: bookId, jpegData: data
            )
            onUploaded()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isUploading = false
    }

    /// Downscale to `maxEdge` on the long side and encode as JPEG.
    private func jpeg(from source: UIImage) -> Data? {
        let longest = max(source.size.width, source.size.height)
        let scale = longest > maxEdge ? maxEdge / longest : 1
        let size = CGSize(width: source.size.width * scale, height: source.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let scaled = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: size))
        }
        return scaled.jpegData(compressionQuality: 0.85)
    }
}

/// The system camera, which SwiftUI still has no native view for.
private struct CoverCamera: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CoverCamera
        init(_ parent: CoverCamera) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let taken = info[.originalImage] as? UIImage {
                parent.onCapture(taken)
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}
