// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import CryptoKit
import Foundation

/// File-backed cache for book cover images. Sits alongside `BookCache`
/// — books live in SwiftData, covers live as raw bytes in the Caches
/// directory because storing megabytes of image data in SwiftData would
/// bloat the database and slow every read.
///
/// Keys are SHA-256 hashes of the cover URL string. Same URL → same
/// file regardless of which Librarium server served it (different
/// servers with the same cover hash dedupe naturally).
final class CoverCache {
    static let shared = CoverCache()

    private let fm = FileManager.default
    private let cacheDir: URL

    private init() {
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BookCovers", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        cacheDir = base
    }

    /// Path on disk for a given cover URL. Returns the same path
    /// deterministically for repeat URLs.
    private func file(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent(name)
    }

    /// Cached image bytes for a URL, or nil if we haven't downloaded
    /// this cover yet (or the cache got purged).
    func cached(for url: URL) -> Data? {
        try? Data(contentsOf: file(for: url))
    }

    /// Persist downloaded image bytes for offline retrieval.
    func save(_ data: Data, for url: URL) {
        try? data.write(to: file(for: url), options: .atomic)
    }

    /// Download a cover if we don't already have it, persisting on
    /// success. No-op when the cache already contains the URL. Returns
    /// true when the cache is populated after the call (either cached
    /// hit or successful download). Used by the offline-sync path.
    @discardableResult
    func prefetch(url: URL, accessToken: String?) async -> Bool {
        if cached(for: url) != nil { return true }
        var req = URLRequest(url: url)
        if let accessToken, !accessToken.isEmpty {
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 else { return false }
        save(data, for: url)
        return true
    }

    /// Wipe every cached cover. Convenience for sign-out and the
    /// "clear cache" path Profile will eventually surface.
    func purgeAll() {
        guard let contents = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) else { return }
        for url in contents { try? fm.removeItem(at: url) }
    }
}
