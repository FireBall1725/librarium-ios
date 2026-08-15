// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI
import SwiftData
import AVFoundation
import UIKit

/// Redesigned scan flow — mockup cards #5 (camera) + #6 (result).
///
/// Scoped to the primary account for v1: lookup hits the primary
/// server's `/lookup/isbn` endpoint and the resulting book is added to
/// one of the primary account's libraries. Multi-server scanning is
/// deferred. Quick-rate mode + continuous-scan counter (visible in the
/// mockup) are stubbed — the camera shows the toggle with only "Add to
/// library" wired up.
struct RedesignedScanFlow: View {
    let onClose: () -> Void

    @Environment(AppState.self) private var appState

    @State private var phase: Phase = .camera
    /// Manual-entry sheet lives at the flow level so both the camera
    /// view (when the user can't scan) and the result view (when the
    /// scanned code wasn't an ISBN) can summon it.
    @State private var showManualEntry = false

    private enum Phase: Equatable {
        case camera
        case result(isbn: String)
    }

    var body: some View {
        ZStack {
            switch phase {
            case .camera:
                RedesignedScanCameraView(
                    onScan: { isbn in
                        let normalized = normalize(isbn: isbn)
                        phase = .result(isbn: normalized)
                    },
                    onManualEntry: { showManualEntry = true },
                    onClose: onClose
                )
                .ignoresSafeArea()
            case .result(let isbn):
                RedesignedScanResultView(
                    isbn: isbn,
                    onScanAnother: { phase = .camera },
                    onClose: onClose,
                    onManualEntry: { showManualEntry = true }
                )
            }
        }
        .sheet(isPresented: $showManualEntry) {
            ManualISBNEntrySheet { isbn in
                showManualEntry = false
                phase = .result(isbn: normalize(isbn: isbn))
            }
            .presentationDetents([.height(280)])
            .presentationDragIndicator(.visible)
        }
    }

    /// Normalize a scanned barcode value before lookup. EAN-13 codes can
    /// arrive with leading zero from some scanners; strip non-digits and
    /// pass through.
    private func normalize(isbn raw: String) -> String {
        raw.filter { $0.isNumber || $0 == "X" || $0 == "x" }.uppercased()
    }
}

// MARK: - Camera screen

/// Mockup card #5. Camera preview with editorial dark overlay: corner
/// brackets, animated laser line, help copy, mode toggle, and a glass
/// close button.
struct RedesignedScanCameraView: View {
    let onScan: (String) -> Void
    let onManualEntry: () -> Void
    let onClose: () -> Void

    @State private var laserOffset: CGFloat = -1
    @State private var hasFiredScan = false
    @State private var mode: ScanMode = .add

    enum ScanMode: Hashable { case add, rate }

    /// Geometry constants — keep mask cutout, scan target frame, and
    /// the offsets used by overlays in lockstep so they all line up no
    /// matter the device size.
    private static let targetW: CGFloat = 260
    private static let targetH: CGFloat = 160
    private static let maskW: CGFloat = 280
    private static let maskH: CGFloat = 180

    var body: some View {
        ZStack {
            HeadlessBarcodeScanner(onScan: { value in
                // Debounce: AVCaptureMetadataOutput can fire repeatedly
                // on the same code; we only want to act on the first.
                guard !hasFiredScan else { return }
                hasFiredScan = true
                onScan(value)
            })
            .ignoresSafeArea()

            // Mask + target are both ZStack-centered so they share a
            // single origin. Layering them via the same parent (rather
            // than nesting the target inside a VStack with Spacers)
            // guarantees the corner brackets sit inside the cutout.
            scanMaskOverlay
            scanTarget

            // Help copy sits 130pt above centre — half the mask height
            // (90) plus a 40pt gutter — so it never overlaps the target.
            helpText
                .offset(y: -(Self.maskH / 2 + 40))

            // Mode toggle sits the same distance below the target.
            modeToggle
                .offset(y: Self.maskH / 2 + 40)

            // Top close button + bottom manual-entry button via a
            // simple VStack with Spacer between — independent of the
            // scan target's centre coordinate.
            VStack(spacing: 0) {
                topBar
                Spacer()
                manualEntryButton
                    .padding(.bottom, 30)
            }
        }
        .background(Color.black)
    }

    @ViewBuilder
    private var topBar: some View {
        HStack {
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.black.opacity(0.45), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 60)
    }

    @ViewBuilder
    private var helpText: some View {
        VStack(spacing: 6) {
            Text("Scan a barcode")
                .font(Theme.Fonts.heroTitle)
                .foregroundStyle(.white)
            Text("Hold steady — ISBN, UPC, or EAN.")
                .font(Theme.Fonts.ui(13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private var scanTarget: some View {
        ZStack {
            ForEach(Corner.allCases, id: \.self) { corner in
                cornerBracket(corner)
            }
            GeometryReader { geo in
                Rectangle()
                    .fill(LinearGradient(
                        colors: [Color.clear, Theme.Colors.accent, Color.clear],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(height: 2)
                    .offset(y: geo.size.height * 0.5 * (1 + laserOffset))
                    .shadow(color: Theme.Colors.accent.opacity(0.6), radius: 6)
            }
        }
        .frame(width: Self.targetW, height: Self.targetH)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                laserOffset = 1
            }
        }
    }

    private enum Corner: CaseIterable { case tl, tr, bl, br }

    @ViewBuilder
    private func cornerBracket(_ corner: Corner) -> some View {
        let path = Path { p in
            switch corner {
            case .tl: p.move(to: .init(x: 0, y: 18)); p.addLine(to: .init(x: 0, y: 0)); p.addLine(to: .init(x: 18, y: 0))
            case .tr: p.move(to: .init(x: 0, y: 0)); p.addLine(to: .init(x: 18, y: 0)); p.addLine(to: .init(x: 18, y: 18))
            case .bl: p.move(to: .init(x: 0, y: 0)); p.addLine(to: .init(x: 0, y: 18)); p.addLine(to: .init(x: 18, y: 18))
            case .br: p.move(to: .init(x: 0, y: 18)); p.addLine(to: .init(x: 18, y: 18)); p.addLine(to: .init(x: 18, y: 0))
            }
        }
        path
            .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .frame(width: 18, height: 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(for: corner))
    }

    private func alignment(for corner: Corner) -> Alignment {
        switch corner {
        case .tl: return .topLeading
        case .tr: return .topTrailing
        case .bl: return .bottomLeading
        case .br: return .bottomTrailing
        }
    }

    /// Two modes from the mockup — both selectable. Quick rate doesn't
    /// branch the result flow yet (it'd skip the "Add to" picker and
    /// jump straight to a star-rating sheet); for v1 it's wired as a
    /// no-op selector so the UI matches the mockup. Real divergence
    /// lands when the Rate sheet ships (mockup card 29).
    @ViewBuilder
    private var modeToggle: some View {
        HStack(spacing: 4) {
            modeButton(.add, label: "Add to library")
            modeButton(.rate, label: "Quick rate")
        }
        .padding(4)
        .background(
            Capsule().fill(Color.white.opacity(0.1))
        )
        .padding(.horizontal, 22)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func modeButton(_ tag: ScanMode, label: String) -> some View {
        let active = mode == tag
        Button { mode = tag } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? Color.black : Color.white.opacity(0.8))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(active ? Color.white : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    /// Manual entry escape hatch when the camera can't pick up the
    /// barcode (worn label, awkward angle, weird format). Opens a small
    /// sheet that takes an ISBN and feeds the same `onScan` path.
    @ViewBuilder
    private var manualEntryButton: some View {
        Button {
            onManualEntry()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .font(.system(size: 13, weight: .semibold))
                Text("Enter ISBN manually")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial.opacity(0.9), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    /// Dim everything outside the scan target — uses the same maskW /
    /// maskH constants as `.offset` callers so the cutout always lines
    /// up with the corner brackets.
    @ViewBuilder
    private var scanMaskOverlay: some View {
        Color.black.opacity(0.4)
            .mask(
                Rectangle()
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .frame(width: Self.maskW, height: Self.maskH)
                            .blendMode(.destinationOut)
                    )
                    .compositingGroup()
            )
            .allowsHitTesting(false)
    }
}

// MARK: - Manual ISBN entry

/// Small sheet for typing an ISBN when the scanner can't pick it up.
/// Single field + Look up button; the parent flow drives lookup via
/// the same handler that scanned barcodes use.
private struct ManualISBNEntrySheet: View {
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isbn: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text("Enter ISBN")
                    .font(Theme.Fonts.heroTitle)
                    .foregroundStyle(Theme.Colors.appText)
                    .padding(.top, 8)
                Text("10 or 13 digits — useful when the barcode is worn or the camera can't lock onto it.")
                    .font(Theme.Fonts.ui(13, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText3)

                TextField("ISBN", text: $isbn)
                    .keyboardType(.numberPad)
                    .textContentType(.none)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .font(Theme.Fonts.mono(18, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText)
                    .tint(Theme.Colors.accent)
                    .padding(14)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.Colors.appLine, lineWidth: 0.5))
                    .padding(.top, 4)

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.appText2)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    Button {
                        let normalized = isbn.filter { $0.isNumber || $0 == "X" || $0 == "x" }.uppercased()
                        guard normalized.count == 10 || normalized.count == 13 else { return }
                        onSubmit(normalized)
                    } label: {
                        Text("Look up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule().fill(LinearGradient(
                                    colors: [Theme.Colors.accent, Color(hex: 0x5a64e8)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                            )
                    }
                    .disabled(!isValid)
                    .opacity(isValid ? 1 : 0.4)
                }
                Spacer()
            }
            .padding(.horizontal, 22)
        }
        .onAppear { focused = true }
    }

    private var isValid: Bool {
        let n = isbn.filter { $0.isNumber || $0 == "X" || $0 == "x" }.count
        return n == 10 || n == 13
    }
}

// MARK: - Headless camera

/// Bare camera + barcode detector — no UI chrome. SwiftUI overlays its
/// own editorial UI on top via `RedesignedScanCameraView`.
struct HeadlessBarcodeScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> HeadlessScannerVC {
        let vc = HeadlessScannerVC()
        vc.onScan = onScan
        return vc
    }

    func updateUIViewController(_ vc: HeadlessScannerVC, context: Context) {}
}

final class HeadlessScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if captureSession?.isRunning == false {
            DispatchQueue.global(qos: .userInitiated).async { self.captureSession?.startRunning() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession?.isRunning == true { captureSession?.stopRunning() }
    }

    private func setupSession() {
        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            showPermissionError()
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.ean13, .ean8, .code128]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.layer.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        self.previewLayer = preview
        self.captureSession = session

        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput objects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let obj = objects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue else { return }
        captureSession?.stopRunning()
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        onScan?(value)
    }

    private func showPermissionError() {
        DispatchQueue.main.async {
            let label = UILabel()
            label.text = "Camera access required.\nEnable it in Settings."
            label.textColor = .white
            label.numberOfLines = 0
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
                label.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 24),
                label.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -24)
            ])
        }
    }
}

// MARK: - Result screen

/// Mockup card #6. Cover-area hero (with "Match found · provider"
/// badge) → library picker → status quick-set → big "Add to X" CTA.
struct RedesignedScanResultView: View {
    let isbn: String
    let onScanAnother: () -> Void
    let onClose: () -> Void
    /// Triggered by the "Enter manually" button on the no-match screen.
    /// The parent ScanFlow surfaces its own manual-entry sheet.
    let onManualEntry: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @State private var lookup: ISBNLookupResult?
    @State private var lookupLoading = true
    @State private var lookupError: String?
    @State private var libraries: [Library] = []
    @State private var librariesError: String?
    /// Per-library ownership keyed by `Library.clientKey`. true = book
    /// with this ISBN is already in that library; false = confirmed not
    /// in library; nil = check still in flight.
    @State private var ownership: [String: Bool] = [:]
    /// `clientKey` (server URL + library id) so duplicates between
    /// servers — same library uuid on a cloned database, or just two
    /// libraries with the same display name — don't select together.
    @State private var selectedLibraryKey: String?
    @State private var selectedStatus: ReadStatus = .unread
    @State private var selectedFormat: String = "paperback"
    /// Media types are server-scoped; we lazily fetch them per server
    /// so users can pick "manga" / "comic book" / etc. instead of
    /// accepting whatever the lookup defaulted to. Keyed by server URL.
    @State private var mediaTypesByServer: [String: [MediaType]] = [:]
    @State private var selectedMediaTypeID: String?
    /// Library tags loaded for the currently-selected library. The user
    /// taps to toggle membership; the IDs ride along on the create.
    @State private var libraryTags: [Tag] = []
    @State private var selectedTagIDs: Set<String> = []
    @State private var isAdding = false
    @State private var addError: String?
    @State private var addedSuccess = false
    @State private var showMediaTypeSheet = false
    @State private var moreOpen = false

    private let formats: [(id: String, label: String)] = [
        ("paperback", "Paperback"),
        ("hardcover", "Hardcover"),
        ("ebook", "E-book"),
        ("audiobook", "Audiobook")
    ]

    private enum ReadStatus: Hashable {
        case unread, reading, read
        var apiValue: String {
            switch self {
            case .unread:  return "unread"
            case .reading: return "reading"
            case .read:    return "read"
            }
        }
    }

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topBar
                    coverHero
                    if lookup != nil {
                        librarySection
                        mediaAndStatusRow
                        moreOptionsSection
                    } else if let lookupError {
                        errorView(message: lookupError)
                    }
                    if let addError {
                        Text(addError)
                            .font(Theme.Fonts.ui(12, weight: .medium))
                            .foregroundStyle(Theme.Colors.bad)
                            .padding(.horizontal, 22)
                            .padding(.top, 8)
                    }
                }
                .padding(.bottom, 100) // room for the CTA
            }
            .scrollIndicators(.hidden)

            VStack {
                Spacer()
                if lookup != nil {
                    addCTA
                }
            }
        }
        .task { await runLookup() }
        .onChange(of: selectedLibraryKey) { _, _ in
            Task { await loadLibraryDependentMetadata() }
        }
        .sheet(isPresented: $showMediaTypeSheet) {
            MediaTypePickerSheet(
                types: currentMediaTypes,
                selectedID: $selectedMediaTypeID
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    /// Fetch media types + tags for the active library (server-scoped).
    /// Triggered on first lookup and whenever the user switches library.
    /// Cache media types per server so re-selecting a library on the
    /// same server doesn't re-hit the network.
    private func loadLibraryDependentMetadata() async {
        guard let library = libraries.first(where: { $0.clientKey == selectedLibraryKey })
            ?? libraries.first else { return }

        // Lite libraries don't have a server-side media type catalog.
        // Seed a small hardcoded list so the picker has options and
        // the picker doesn't sit on "Loading…" forever.
        if library.serverURL.hasPrefix("local://") {
            if mediaTypesByServer[library.serverURL] == nil {
                mediaTypesByServer[library.serverURL] = Self.liteMediaTypes
            }
            if selectedMediaTypeID == nil {
                let types = mediaTypesByServer[library.serverURL] ?? []
                selectedMediaTypeID = guessMediaTypeID(for: lookup, types: types)
                    ?? types.first?.id
            }
            // Tags don't exist for Lite either; leave empty.
            libraryTags = []
            return
        }

        let client = appState.makeClient(serverURL: library.serverURL)

        if mediaTypesByServer[library.serverURL] == nil {
            if let types = try? await MediaTypeService(client: client).list() {
                mediaTypesByServer[library.serverURL] = types
                // Pick a sensible default — prefer the lookup's hint
                // ("manga"/"comic"/etc) when the api emits one in the
                // categories array; otherwise leave the user to pick.
                if selectedMediaTypeID == nil {
                    selectedMediaTypeID = guessMediaTypeID(for: lookup, types: types)
                }
            }
        } else if selectedMediaTypeID == nil,
                  let types = mediaTypesByServer[library.serverURL] {
            selectedMediaTypeID = guessMediaTypeID(for: lookup, types: types)
        }

        // Tags are per-library — always re-fetch on library change.
        if let tags = try? await TagService(client: client).list(libraryId: library.id) {
            libraryTags = tags
            // Drop any selected tags that don't exist in the new library
            // so we don't try to attach a server-A tag to a server-B add.
            let valid = Set(tags.map(\.id))
            selectedTagIDs = selectedTagIDs.intersection(valid)
        }
    }

    /// Smart default for the media-type chip:
    ///
    /// 1. Try to match the lookup's `categories` strings against type
    ///    display names so providers that classify as "Manga" / "Comic"
    ///    / "Light Novel" land on the right type.
    /// 2. If no category match, fall back to a Novel-family type
    ///    (`Novel`, `Light Novel`, etc — anything containing "novel"
    ///    in the display name). Most ISBNs are novels, so this is the
    ///    right default for the long tail.
    /// 3. As a last resort, fall back to the first type the server
    ///    returns. Shouldn't trigger for any normal Librarium instance
    ///    since "Novel" is a stock type.
    private func guessMediaTypeID(for lookup: ISBNLookupResult?, types: [MediaType]) -> String? {
        guard !types.isEmpty else { return nil }

        if let lookup {
            let cats = (lookup.categories ?? []).map { $0.lowercased() }
            for t in types {
                let name = t.displayName.lowercased()
                if cats.contains(where: { $0.contains(name) || name.contains($0) }) {
                    return t.id
                }
            }
        }

        // Prefer plain "Book" (Lite's default name) or plain "Novel" (the
        // stock remote-api name). Partial matches on "novel" come last so
        // we don't accidentally pick "Graphic novel" / "Light novel" as
        // the default for an unclassified scan.
        if let book = types.first(where: { $0.displayName.lowercased() == "book" }) {
            return book.id
        }
        if let novel = types.first(where: { $0.displayName.lowercased() == "novel" }) {
            return novel.id
        }
        if let partial = types.first(where: { $0.displayName.lowercased().contains("novel") }) {
            return partial.id
        }
        return types.first?.id
    }

    // MARK: - Top bar

    @ViewBuilder
    private var topBar: some View {
        HStack {
            Button(action: onScanAnother) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.06), in: Circle())
                    .overlay(Circle().stroke(Theme.Colors.appLine, lineWidth: 0.5))
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.appText)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.06), in: Circle())
                    .overlay(Circle().stroke(Theme.Colors.appLine, lineWidth: 0.5))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    // MARK: - Cover hero

    @ViewBuilder
    private var coverHero: some View {
        VStack(spacing: 12) {
            if lookupLoading {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.Colors.appCard)
                    .frame(width: 140, height: 210)
                    .overlay(ProgressView().tint(Theme.Colors.appText2))
                Text("Looking up \(isbn)…")
                    .font(Theme.Fonts.ui(13, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText3)
            } else if let lookup {
                BookCoverImage(
                    url: URL(string: lookup.coverUrl),
                    width: 140,
                    height: 210,
                    title: lookup.title,
                    author: lookup.authors.first
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 6)

                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.Colors.good)
                    Text("Match found · \(lookup.providerDisplay)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Colors.good)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(hex: 0x7bd6a8, opacity: 0.15), in: Capsule())

                Text(lookup.title)
                    .font(Theme.Fonts.heroTitle)
                    .foregroundStyle(Theme.Colors.appText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22)
                Text(authorMeta(for: lookup))
                    .font(Theme.Fonts.ui(13, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22)
                Text("ISBN \(lookup.isbn13.isEmpty ? lookup.isbn10 : lookup.isbn13)")
                    .font(Theme.Fonts.label(11))
                    .tracking(1.2)
                    .foregroundStyle(Theme.Colors.appText3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
        .padding(.bottom, 22)
    }

    private func authorMeta(for lookup: ISBNLookupResult) -> String {
        var parts: [String] = lookup.authors
        let year = String(lookup.publishDate.prefix(4))
        if !year.isEmpty && Int(year) != nil {
            parts.append(year)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Library section

    @ViewBuilder
    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ADD TO")
                .font(Theme.Fonts.label(11))
                .tracking(1.2)
                .foregroundStyle(Theme.Colors.appText3)
                .padding(.horizontal, 22)

            Group {
                if !libraries.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(libraries.enumerated()), id: \.element.clientKey) { idx, library in
                            let owned = ownership[library.clientKey] == true
                            Button {
                                selectedLibraryKey = library.clientKey
                            } label: {
                                libraryRow(library: library, isSelected: selectedLibraryKey == library.clientKey, owned: owned)
                            }
                            .buttonStyle(.plain)
                            if idx != libraries.count - 1 {
                                Divider().background(Theme.Colors.appLine).padding(.leading, 22 + 28 + 12)
                            }
                        }
                    }
                } else if let librariesError {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Colors.warn)
                        Text(librariesError)
                            .font(Theme.Fonts.ui(12, weight: .medium))
                            .foregroundStyle(Theme.Colors.appText2)
                            .lineLimit(2)
                    }
                    .padding(14)
                } else {
                    HStack {
                        ProgressView().tint(Theme.Colors.appText3)
                        Text("Loading libraries…")
                            .font(Theme.Fonts.ui(12, weight: .medium))
                            .foregroundStyle(Theme.Colors.appText3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.Colors.appCard)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.Colors.appLine, lineWidth: 0.5))
            )
            .padding(.horizontal, 22)
        }
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private func libraryRow(library: Library, isSelected: Bool, owned: Bool) -> some View {
        let initial = String(library.name.prefix(1)).uppercased()
        let multiServer = appState.accounts.count > 1
        HStack(spacing: 12) {
            ZStack {
                if isSelected {
                    LinearGradient(
                        colors: [Theme.Colors.accent, Color(hex: 0x5a64e8)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                } else {
                    Color.white.opacity(0.06)
                }
                Text(initial)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isSelected ? .white : Theme.Colors.appText2)
            }
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(library.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.Colors.accentStrong : Theme.Colors.appText)
                if multiServer, !library.serverName.isEmpty {
                    Text(library.serverName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Colors.appText3)
                        .lineLimit(1)
                }
            }
            Spacer()
            if owned {
                // Informational only — tapping still selects, the CTA
                // shows "Add another copy" since the api increments the
                // existing edition's copy count when the ISBN matches.
                ownedBadge
            } else if ownership[library.clientKey] == nil {
                ProgressView()
                    .scaleEffect(0.65)
                    .tint(Theme.Colors.appText3)
            } else if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Colors.accentStrong)
            }
        }
        .padding(14)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var ownedBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
            Text("Already in")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.4)
        }
        .foregroundStyle(Theme.Colors.good)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(hex: 0x7bd6a8, opacity: 0.15), in: Capsule())
    }

    // MARK: - Tier 2 — Media type + Status side-by-side

    /// Compact second tier: a media-type chip on the left (tap to open
    /// a sheet picker) and a 3-segment status toggle on the right.
    /// These are the two fields users override most often, sized to
    /// match each other so the tier reads as a single horizontal unit.
    @ViewBuilder
    private var mediaAndStatusRow: some View {
        HStack(alignment: .top, spacing: 14) {
            mediaTypePicker
                .frame(maxWidth: .infinity, alignment: .leading)
            statusSegmented
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var mediaTypePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MEDIA TYPE")
                .font(Theme.Fonts.label(11))
                .tracking(1.2)
                .foregroundStyle(Theme.Colors.appText3)
            Button { showMediaTypeSheet = true } label: {
                HStack(spacing: 6) {
                    Text(currentMediaTypeName ?? "Loading…")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.appText)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.Colors.appText3)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.Colors.appCard)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.Colors.appLine, lineWidth: 0.5))
                )
            }
            .buttonStyle(.plain)
            .disabled(currentMediaTypes.isEmpty)
        }
    }

    private var currentMediaTypeName: String? {
        guard let id = selectedMediaTypeID else { return nil }
        return currentMediaTypes.first(where: { $0.id == id })?.displayName
    }

    @ViewBuilder
    private var statusSegmented: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STATUS")
                .font(Theme.Fonts.label(11))
                .tracking(1.2)
                .foregroundStyle(Theme.Colors.appText3)
            HStack(spacing: 0) {
                statusSegment(.unread,  icon: "circle",        label: "Unread")
                statusSegment(.reading, icon: "book.fill",     label: "Reading")
                statusSegment(.read,    icon: "checkmark",     label: "Read")
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.Colors.appCard)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.Colors.appLine, lineWidth: 0.5))
            )
        }
    }

    @ViewBuilder
    private func statusSegment(_ value: ReadStatus, icon: String, label: String) -> some View {
        let active = selectedStatus == value
        Button { selectedStatus = value } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(active ? Theme.Colors.accentStrong : Theme.Colors.appText3)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(active ? Theme.Colors.accentSoft : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Media types live on the active library's server — switch when
    /// the user picks a library from a different server.
    private var currentMediaTypes: [MediaType] {
        guard let library = libraries.first(where: { $0.clientKey == selectedLibraryKey })
            ?? libraries.first else { return [] }
        return mediaTypesByServer[library.serverURL] ?? []
    }

    // MARK: - Tier 3 — More options (collapsed by default)

    /// Format + Tags hidden behind a single tappable row that summarises
    /// the current state. Expands inline to reveal both pickers.
    @ViewBuilder
    private var moreOptionsSection: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.18)) { moreOpen.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: moreOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.Colors.appText3)
                        .frame(width: 14)
                    Text("MORE OPTIONS")
                        .font(Theme.Fonts.label(11))
                        .tracking(1.2)
                        .foregroundStyle(Theme.Colors.appText3)
                    Spacer()
                    if !moreOpen {
                        Text(moreSummary)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.Colors.appText3)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if moreOpen {
                VStack(alignment: .leading, spacing: 14) {
                    formatGroup
                    tagsGroup
                }
                .padding(.top, 6)
                .padding(.bottom, 14)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 6)
    }

    private var moreSummary: String {
        let formatLabel = formats.first(where: { $0.id == selectedFormat })?.label ?? selectedFormat
        let tagBit = selectedTagIDs.isEmpty ? "no tags" : "\(selectedTagIDs.count) tag\(selectedTagIDs.count == 1 ? "" : "s")"
        return "\(formatLabel) · \(tagBit)"
    }

    @ViewBuilder
    private var formatGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Format")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Colors.appText2)
            HStack(spacing: 8) {
                ForEach(formats, id: \.id) { f in
                    chipButton(label: f.label, active: selectedFormat == f.id) {
                        selectedFormat = f.id
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var tagsGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Colors.appText2)
            if libraryTags.isEmpty {
                Text("No tags configured for this library yet.")
                    .font(Theme.Fonts.ui(12, weight: .medium))
                    .foregroundStyle(Theme.Colors.appText3)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(libraryTags) { tag in
                            chipButton(label: tag.name,
                                       active: selectedTagIDs.contains(tag.id)) {
                                if selectedTagIDs.contains(tag.id) {
                                    selectedTagIDs.remove(tag.id)
                                } else {
                                    selectedTagIDs.insert(tag.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func chipButton(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? Theme.Colors.accentStrong : Theme.Colors.appText2)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(active ? Theme.Colors.accentSoft : Color.white.opacity(0.06))
                )
                .overlay(
                    Capsule().stroke(active ? Color.clear : Theme.Colors.appLine, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Error

    @ViewBuilder
    private func errorView(message: String) -> some View {
        let looksLikeUPC = Self.scannedLooksLikeUPC(isbn)
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(Theme.Colors.warn)
            Text(looksLikeUPC ? "Not an ISBN" : "No match")
                .font(Theme.Fonts.cardTitle)
                .foregroundStyle(Theme.Colors.appText)
            Text(looksLikeUPC
                 ? "This looks like a UPC barcode, not an ISBN. Find the ISBN inside the front cover and enter it manually."
                 : message)
                .font(Theme.Fonts.ui(13, weight: .medium))
                .foregroundStyle(Theme.Colors.appText3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            HStack(spacing: 10) {
                Button { onScanAnother() } label: {
                    Text("Scan another")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.appText2)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.06), in: Capsule())
                }
                Button { onManualEntry() } label: {
                    Text("Enter manually")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.Colors.accentSoft, in: Capsule())
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.vertical, 30)
    }

    /// Heuristic: 12-digit codes are UPC-A; 13-digit codes whose
    /// prefix isn't 978 or 979 aren't ISBNs in the Bookland sense
    /// (they're EAN-13 representations of UPCs, or some other
    /// non-book product). Either way, the user almost certainly
    /// needs to enter the printed ISBN by hand.
    private static func scannedLooksLikeUPC(_ raw: String) -> Bool {
        let digits = raw.filter { $0.isNumber }
        if digits.count == 12 { return true }
        if digits.count == 13, !(digits.hasPrefix("978") || digits.hasPrefix("979")) {
            return true
        }
        return false
    }

    // MARK: - CTA

    @ViewBuilder
    private var addCTA: some View {
        let library = libraries.first { $0.clientKey == selectedLibraryKey }
        let owned = library.map { ownership[$0.clientKey] == true } ?? false
        Button {
            guard let library else { return }
            Task { await addToLibrary(library: library) }
        } label: {
            HStack(spacing: 8) {
                if isAdding {
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(.white)
                } else if addedSuccess {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                }
                Text(ctaLabel(for: library))
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(
                        colors: [Theme.Colors.accent, Color(hex: 0x5a64e8)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            )
            .shadow(color: Theme.Colors.accent.opacity(0.5), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(library == nil || isAdding || addedSuccess)
        .padding(.horizontal, 22)
        .padding(.bottom, 30)
        // Suppress the unused-warning when the closure doesn't reference
        // `owned` — kept here so future status-driven CTA tweaks have it.
        .accessibilityLabel(owned ? "Add another copy" : "Add")
    }

    private func ctaLabel(for library: Library?) -> String {
        if addedSuccess { return "Added" }
        guard let library else { return "Pick a library" }
        if ownership[library.clientKey] == true {
            return "Add another copy to \(library.name)"
        }
        return "Add to \(library.name)"
    }

    // MARK: - Lookup + add

    private func runLookup() async {
        lookupLoading = true
        defer { lookupLoading = false }

        // Lookup strategy:
        // - If we have a remote-capable account, hit its api LookupService
        //   first — server-side aggregation gives richer metadata than
        //   any single provider direct.
        // - Fall back to Open Library directly when no remote is
        //   available OR the api call fails.
        // Lite-only installs reach the Open Library path immediately.
        let lookupAccount = lookupCapableAccount()
        async let allLibrariesTask = loadAllLibraries()
        async let lookupResultTask = Self.lookupMetadata(isbn: isbn, account: lookupAccount, appState: appState)
        let result = await lookupResultTask
        switch result {
        case .success(let payload):
            lookup = payload
        case .notFound:
            lookupError = "No results for \(isbn)."
        case .failed(let message):
            lookupError = message
        }

        let libs = await allLibrariesTask
        if libs.isEmpty {
            librariesError = "Couldn't load libraries from any server."
        } else {
            libraries = libs.sorted { lhs, rhs in
                if lhs.serverName == rhs.serverName {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.serverName.localizedStandardCompare(rhs.serverName) == .orderedAscending
            }
            if selectedLibraryKey == nil {
                selectedLibraryKey = libraries.first?.clientKey
            }
            // Ownership checks fire after libraries are visible — the
            // row UI shows a spinner until each library reports back.
            await checkOwnership(libraries: libraries)
        }
    }

    /// Fan out `LibraryService.list` across every signed-in account.
    /// Stamps server URL + name onto each library so the rest of the
    /// flow can route subsequent requests (byISBN, create) to the
    /// correct server. Lite accounts contribute their SwiftData
    /// libraries here too so the user can scan straight into a local
    /// library without needing a server.
    private func loadAllLibraries() async -> [Library] {
        var collected: [Library] = []

        // Lite libraries (local SwiftData) first — cheap, no network.
        let localAccounts = appState.accounts.filter { $0.kind == .local }
        if !localAccounts.isEmpty {
            let context = ModelContext(modelContext.container)
            for account in localAccounts {
                let accountID = account.id
                let accountName = account.name
                let descriptor = FetchDescriptor<PersistedLibrary>(
                    predicate: #Predicate { $0.serverAccountID == accountID && $0.deletedAt == nil }
                )
                if let rows = try? context.fetch(descriptor) {
                    collected.append(contentsOf: rows.map {
                        $0.toLibrary(serverAccountID: accountID, accountName: accountName)
                    })
                }
            }
        }

        // Remote accounts via api fan-out.
        let remoteAccounts = appState.accounts.filter { $0.kind == .remote }
        guard !remoteAccounts.isEmpty else { return collected }
        await withTaskGroup(of: [Library].self) { group in
            for account in remoteAccounts {
                group.addTask {
                    let client = await appState.makeClient(serverURL: account.url)
                    guard var libs = try? await LibraryService(client: client).list() else {
                        return []
                    }
                    for i in libs.indices {
                        libs[i].serverURL = account.url
                        libs[i].serverName = account.name
                    }
                    return libs
                }
            }
            for await libs in group {
                collected.append(contentsOf: libs)
            }
        }
        return collected
    }

    /// Per-library "is this ISBN already here?" check. Resolves to true
    /// when the server has a matching book for either the 13-digit or
    /// 10-digit form (some servers store one, some the other).
    private func checkOwnership(libraries: [Library]) async {
        let lookupISBN13 = isbn.count == 13 ? isbn : (lookup?.isbn13 ?? "")
        let lookupISBN10 = isbn.count == 10 ? isbn : (lookup?.isbn10 ?? "")
        let candidates = Set([isbn, lookupISBN13, lookupISBN10].filter { !$0.isEmpty })

        await withTaskGroup(of: (String, Bool).self) { group in
            for library in libraries {
                group.addTask {
                    // Local (Lite) libraries — query SwiftData for an
                    // existing book whose primary edition matches one
                    // of the candidate ISBNs.
                    if library.serverURL.hasPrefix("local://") {
                        let owned = await Self.localOwnsISBN(
                            library: library,
                            candidates: candidates,
                            modelContainer: modelContext.container
                        )
                        return (library.clientKey, owned)
                    }
                    let client = await appState.makeClient(serverURL: library.serverURL)
                    let svc = BookService(client: client)
                    for candidate in candidates {
                        if (try? await svc.byISBN(libraryId: library.id, isbn: candidate)) != nil {
                            return (library.clientKey, true)
                        }
                    }
                    return (library.clientKey, false)
                }
            }
            for await (key, owned) in group {
                ownership[key] = owned
            }
        }

    }

    private func addToLibrary(library: Library) async {
        guard let lookup, !isAdding, !addedSuccess else { return }
        isAdding = true
        addError = nil
        defer { isAdding = false }

        // Lite library? Write to SwiftData and we're done.
        if library.serverURL.hasPrefix("local://"),
           let account = appState.accounts.first(where: { $0.kind == .local && $0.url == library.serverURL }) {
            let picked = mediaTypesByServer[library.serverURL]?
                .first(where: { $0.id == selectedMediaTypeID })
            let writer = LiteBookWriter(modelContainer: modelContext.container)
            _ = writer.add(
                lookup: lookup,
                to: library,
                serverAccountID: account.id,
                mediaType: picked?.displayName ?? "Book",
                readStatus: selectedStatus.apiValue
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            addedSuccess = true
            try? await Task.sleep(for: .milliseconds(700))
            onScanAnother()
            return
        }

        let client = appState.makeClient(serverURL: library.serverURL)

        // Use the user's picked media type when set; otherwise fall back
        // to the active library's server's first type so the api never
        // gets an empty UUID (which it would reject).
        let mediaTypeID: String = selectedMediaTypeID
            ?? mediaTypesByServer[library.serverURL]?.first?.id
            ?? ""

        let edition = CreateEditionRequest(
            format: selectedFormat,
            language: lookup.language,
            editionName: "",
            narrator: "",
            publisher: lookup.publisher,
            publishDate: lookup.publishDate.isEmpty ? nil : lookup.publishDate,
            isbn10: lookup.isbn10,
            isbn13: lookup.isbn13,
            description: lookup.description,
            pageCount: lookup.pageCount,
            copyCount: 1,
            isPrimary: true
        )
        let body = CreateBookRequest(
            title: lookup.title,
            subtitle: lookup.subtitle,
            mediaTypeId: mediaTypeID,
            description: lookup.description,
            contributors: [],
            tagIds: Array(selectedTagIDs),
            genreIds: [],
            edition: edition
        )

        do {
            let book = try await BookService(client: client).create(libraryId: library.id, body: body)
            // If the user picked Reading or Read, set status on the
            // primary edition's interaction.
            if selectedStatus != .unread,
               let edition = (try? await BookService(client: client).editions(libraryId: library.id, bookId: book.id))?.first {
                let upd = UpdateInteractionRequest(
                    readStatus: selectedStatus.apiValue,
                    rating: nil,
                    notes: "",
                    review: "",
                    dateStarted: nil,
                    dateFinished: nil,
                    isFavorite: false
                )
                _ = try? await BookService(client: client)
                    .updateInteraction(libraryId: library.id, bookId: book.id, editionId: edition.id, body: upd)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            addedSuccess = true
            // Auto-return to camera after a short pause so the user can
            // scan the next book. They can tap close at any time to bail.
            try? await Task.sleep(for: .milliseconds(700))
            onScanAnother()
        } catch {
            addError = error.localizedDescription
        }
    }

    private func primaryAccount() -> ServerAccount? {
        if let id = appState.primaryAccountID,
           let primary = appState.accounts.first(where: { $0.id == id }) {
            return primary
        }
        return appState.accounts.first
    }

    /// Synthetic media-type catalog for Lite libraries. Server-backed
    /// libraries get the same list via `MediaTypeService.list`, which
    /// has UUIDs from the database; for Lite we don't need persistent
    /// ids since the books we add carry the mediaType string directly
    /// on PersistedBook. Names match the api's defaults so a future
    /// "promote Lite to self-hosted" flow can map cleanly.
    private static let liteMediaTypes: [MediaType] = [
        MediaType(id: "lite-book", name: "book", displayName: "Book"),
        MediaType(id: "lite-manga", name: "manga", displayName: "Manga"),
        MediaType(id: "lite-comic", name: "comic", displayName: "Comic"),
        MediaType(id: "lite-graphic-novel", name: "graphic_novel", displayName: "Graphic novel"),
        MediaType(id: "lite-audiobook", name: "audiobook", displayName: "Audiobook"),
    ]

    /// Check the SwiftData book cache for an edition matching any of
    /// the candidate ISBNs in this Lite library. Walks cached books'
    /// primary editions via EditionCache. Bounded by the library size;
    /// fine for the offline scale.
    private static func localOwnsISBN(
        library: Library,
        candidates: Set<String>,
        modelContainer: ModelContainer
    ) async -> Bool {
        let bookCache = BookCache(modelContainer: modelContainer)
        let editionCache = EditionCache(modelContainer: modelContainer)
        for book in bookCache.books(for: library) {
            let editions = editionCache.editions(for: library, bookId: book.id)
            for edition in editions {
                if candidates.contains(edition.isbn13) || candidates.contains(edition.isbn10) {
                    return true
                }
            }
        }
        return false
    }

    enum LookupOutcome {
        case success(ISBNLookupResult)
        case notFound
        case failed(String)
    }

    /// Resolve an ISBN to metadata. Tries the api LookupService when a
    /// remote account is available, falls back to Open Library on api
    /// failure or when there's no server at all. Returns a typed
    /// outcome so the UI can distinguish "no metadata for this ISBN"
    /// from "we couldn't reach anything".
    private static func lookupMetadata(
        isbn: String,
        account: ServerAccount?,
        appState: AppState
    ) async -> LookupOutcome {
        // Path 1: api LookupService when we have a remote account.
        if let account {
            let client = await appState.makeClient(serverURL: account.url)
            if let results = try? await LookupService(client: client).isbn(isbn),
               let match = results.first(where: { !$0.title.isEmpty }) {
                return .success(match)
            }
            // Server returned but didn't find anything, or threw —
            // try Open Library directly before giving up.
        }
        // Path 2: Open Library direct. Distinguish network failure
        // (throws) from "ISBN not in their database" (returns empty).
        do {
            let results = try await OpenLibraryService().isbn(isbn)
            if let match = results.first(where: { !$0.title.isEmpty }) {
                return .success(match)
            }
            return .notFound
        } catch {
            return .failed("Couldn't reach Open Library to look up this ISBN.")
        }
    }

    /// Account to hit for ISBN lookups. Provider-based, so any remote
    /// server gives the same answer — but the preferred account wins if
    /// it's remote so multi-server users get consistent results.
    private func lookupCapableAccount() -> ServerAccount? {
        if let preferred = primaryAccount(),
           preferred.kind == .remote, !preferred.needsReauth {
            return preferred
        }
        return appState.accounts.first { $0.kind == .remote && !$0.needsReauth }
    }
}

// MARK: - Media type picker sheet

/// Half-sheet picker for the active library's media types. Opens from
/// the compact MEDIA TYPE chip on the result screen — keeping the chip
/// visually quiet (single line, current value) while moving the long
/// scrollable list of options off the main screen.
private struct MediaTypePickerSheet: View {
    let types: [MediaType]
    @Binding var selectedID: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Text("Media type")
                    .font(Theme.Fonts.heroTitle)
                    .foregroundStyle(Theme.Colors.appText)
                    .padding(.horizontal, 22)
                    .padding(.top, 16)
                    .padding(.bottom, 14)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(types) { type in
                            Button {
                                selectedID = type.id
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Text(type.displayName)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(selectedID == type.id ? Theme.Colors.accentStrong : Theme.Colors.appText)
                                    Spacer()
                                    if selectedID == type.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(Theme.Colors.accentStrong)
                                    }
                                }
                                .padding(.horizontal, 22)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if type.id != types.last?.id {
                                Divider().background(Theme.Colors.appLine).padding(.leading, 22)
                            }
                        }
                    }
                }
            }
        }
    }
}
