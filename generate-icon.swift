// Compiled and run by generate-icon.sh — do not run with `swift` directly.
// AppKit's SF Symbol APIs require a compiled binary; the Swift interpreter crashes.
//
// Outputs (written to the current working directory):
//   AppIcon-1024.png        — opaque, no alpha  (Xcode / App Store)
//   AppIcon-Debug-1024.png  — orange bg, no alpha  (Debug builds — visually distinct on home screen)
//   AppIcon-transparent.png — transparent bg    (web UI / marketing)

import AppKit
import ImageIO

final class IconGenerator: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        defer { NSApp.terminate(nil) }

        let size: CGFloat = 1024
        let iSize = Int(size)
        let rect  = CGRect(origin: .zero, size: CGSize(width: size, height: size))
        let sRGB  = CGColorSpace(name: CGColorSpace.sRGB)!

        // ── Tinted SF Symbol ──────────────────────────────────────────────────
        let cfg = NSImage.SymbolConfiguration(pointSize: 480, weight: .medium)
        guard let raw    = NSImage(systemSymbolName: "books.vertical.fill", accessibilityDescription: nil),
              let symbol = raw.withSymbolConfiguration(cfg) else {
            fputs("❌  SF Symbol not found — requires macOS 11+\n", stderr); return
        }

        let symSize  = symbol.size

        // Centered at natural size — used for the opaque app icon (background fills the canvas)
        let destRect = CGRect(
            x: (size - symSize.width)  / 2,
            y: (size - symSize.height) / 2,
            width: symSize.width, height: symSize.height
        )

        // Scaled to fill ~96% of the canvas — used for the transparent export (no background padding)
        let transPad:  CGFloat = size * 0.02
        let transScale = (size - transPad * 2) / max(symSize.width, symSize.height)
        let transW = symSize.width  * transScale
        let transH = symSize.height * transScale
        let transDestRect = CGRect(
            x: (size - transW) / 2,
            y: (size - transH) / 2,
            width: transW, height: transH
        )

        symbol.lockFocus()
        NSColor(red: 0.220, green: 0.627, blue: 1.000, alpha: 1).set()
        NSRect(origin: .zero, size: symSize).fill(using: .sourceAtop)
        symbol.unlockFocus()

        // ── Helper: RGBA NSBitmapImageRep (only format NSGraphicsContext accepts)
        func makeRGBARep() -> NSBitmapImageRep {
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: iSize, pixelsHigh: iSize,
                bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            )!
        }

        func makeNSCtx(_ rep: NSBitmapImageRep) -> NSGraphicsContext {
            guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
                fputs("❌  NSGraphicsContext init failed\n", stderr); exit(1)
            }
            return ctx
        }

        // ── Helper: draw gradient icon → flatten to opaque RGB PNG ───────────
        func writeOpaqueIcon(
            gradTop: CGColor, gradBottom: CGColor, fillColor: CGColor,
            filename: String, label: String
        ) {
            let rgbaRep = makeRGBARep()
            NSGraphicsContext.current = makeNSCtx(rgbaRep)
            let cgCtx = NSGraphicsContext.current!.cgContext
            let gradColors = [gradTop, gradBottom] as CFArray
            let gradient = CGGradient(colorsSpace: sRGB, colors: gradColors, locations: [0, 1])!
            cgCtx.drawLinearGradient(gradient,
                start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
            symbol.draw(in: destRect)
            NSGraphicsContext.current = nil

            guard let composited = rgbaRep.cgImage else {
                fputs("❌  Failed to get CGImage (\(filename))\n", stderr); return
            }

            // Flatten to RGB — CGImageDestination with noneSkipLast writes a no-alpha PNG
            guard let flatCtx = CGContext(
                data: nil, width: iSize, height: iSize,
                bitsPerComponent: 8, bytesPerRow: iSize * 4,
                space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else {
                fputs("❌  Could not create flat CGContext (\(filename))\n", stderr); return
            }
            flatCtx.setFillColor(fillColor)
            flatCtx.fill(rect)
            flatCtx.draw(composited, in: rect)

            guard let flatImage = flatCtx.makeImage() else {
                fputs("❌  Could not produce flat CGImage (\(filename))\n", stderr); return
            }
            let path = URL(fileURLWithPath: filename)
            guard let dest = CGImageDestinationCreateWithURL(path as CFURL, "public.png" as CFString, 1, nil) else {
                fputs("❌  Could not create PNG destination (\(filename))\n", stderr); return
            }
            CGImageDestinationAddImage(dest, flatImage, nil)
            guard CGImageDestinationFinalize(dest) else {
                fputs("❌  PNG write failed (\(filename))\n", stderr); return
            }
            print("✅  \(filename)  (\(iSize)×\(iSize), no alpha)\(label)")
        }

        // ── 1. Production icon — dark navy gradient ───────────────────────────
        writeOpaqueIcon(
            gradTop:   CGColor(red: 0.055, green: 0.118, blue: 0.220, alpha: 1),
            gradBottom: CGColor(red: 0.020, green: 0.047, blue: 0.110, alpha: 1),
            fillColor:  CGColor(red: 0.020, green: 0.047, blue: 0.110, alpha: 1),
            filename: "AppIcon-1024.png",
            label: " — drag into AppIcon in Assets.xcassets"
        )

        // ── 2. Debug icon — orange gradient (visually distinct on home screen) ─
        writeOpaqueIcon(
            gradTop:   CGColor(red: 0.820, green: 0.380, blue: 0.020, alpha: 1),
            gradBottom: CGColor(red: 0.500, green: 0.180, blue: 0.000, alpha: 1),
            fillColor:  CGColor(red: 0.500, green: 0.180, blue: 0.000, alpha: 1),
            filename: "AppIcon-Debug-1024.png",
            label: " — drag into AppIcon-Debug in Assets.xcassets"
        )

        // ── 3. Transparent PNG — symbol only on clear background ──────────────
        let transRep = makeRGBARep()
        NSGraphicsContext.current = makeNSCtx(transRep)
        NSGraphicsContext.current!.cgContext.clear(rect)
        symbol.draw(in: transDestRect)
        NSGraphicsContext.current = nil

        let transPNG = transRep.representation(using: .png, properties: [:])!
        try! transPNG.write(to: URL(fileURLWithPath: "AppIcon-transparent.png"))
        print("✅  AppIcon-transparent.png  (\(iSize)×\(iSize), transparent) — use for web UI")
    }
}

let app      = NSApplication.shared
let delegate = IconGenerator()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
