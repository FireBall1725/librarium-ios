import Foundation
import Observation

enum BookCacheState: Equatable {
    case notCached
    case syncing(progress: Double)
    case cached(bookCount: Int)
}

/// Manages client-side per-library offline preferences and caches.
/// Small prefs (enabled keys, fingerprints, server context) live in UserDefaults;
/// larger JSON payloads live in the app's Caches directory since they're
/// rebuildable from the server.
///
/// All state is keyed on `Library.clientKey` ("<serverURL>|<libraryID>") rather
/// than the bare server-side `id`, because two different Librarium servers can
/// expose libraries with colliding UUIDs (common when both were seeded from the
/// same database). Keying on the composite makes those entries independent.
@Observable
final class LibraryOfflineStore {
    static let shared = LibraryOfflineStore()

    private(set) var enabledKeys: Set<String> = []
    private(set) var bookCacheStates: [String: BookCacheState] = [:]

    private let fm = FileManager.default
    private let cacheDir: URL

    private init() {
        let fm = FileManager.default
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LibraryOffline", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        self.cacheDir = base

        enabledKeys = Set(UserDefaults.standard.stringArray(forKey: "offline_enabled_keys") ?? [])
        for key in enabledKeys {
            if let books = cachedBooks(for: key) {
                bookCacheStates[key] = .cached(bookCount: books.count)
            } else {
                bookCacheStates[key] = .notCached
            }
        }
    }

    func isEnabled(for key: String) -> Bool { enabledKeys.contains(key) }

    func setEnabled(_ enabled: Bool, for key: String) {
        if enabled {
            enabledKeys.insert(key)
            if bookCacheStates[key] == nil { bookCacheStates[key] = .notCached }
        } else {
            enabledKeys.remove(key)
            try? fm.removeItem(at: libraryFile(key))
            try? fm.removeItem(at: booksFile(key))
            UserDefaults.standard.removeObject(forKey: fingerprintKey(key))
            UserDefaults.standard.removeObject(forKey: serverURLKey(key))
            UserDefaults.standard.removeObject(forKey: serverNameKey(key))
            bookCacheStates.removeValue(forKey: key)
        }
        UserDefaults.standard.set(Array(enabledKeys), forKey: "offline_enabled_keys")
    }

    /// Call after a successful online load to persist the library for offline use.
    func cacheLibrary(_ library: Library) {
        let key = library.clientKey
        guard isEnabled(for: key) else { return }
        if let data = try? JSONEncoder().encode(library) {
            try? data.write(to: libraryFile(key), options: .atomic)
        }
        // Persist the client-side server context separately (excluded from CodingKeys).
        UserDefaults.standard.set(library.serverURL,  forKey: serverURLKey(key))
        UserDefaults.standard.set(library.serverName, forKey: serverNameKey(key))
    }

    /// Returns all cached libraries for keys that have offline enabled.
    func cachedLibraries() -> [Library] {
        enabledKeys
            .compactMap { key -> Library? in
                guard let data = try? Data(contentsOf: libraryFile(key)),
                      var lib = try? JSONDecoder().decode(Library.self, from: data) else { return nil }
                // Re-inject server context so setActiveAccount(for:) works when offline.
                lib.serverURL  = UserDefaults.standard.string(forKey: serverURLKey(key))  ?? ""
                lib.serverName = UserDefaults.standard.string(forKey: serverNameKey(key)) ?? ""
                return lib
            }
            .sorted { $0.name < $1.name }
    }

    /// Returns cached books for a library, or nil if no cache exists.
    func cachedBooks(for key: String) -> [Book]? {
        guard let data = try? Data(contentsOf: booksFile(key)) else { return nil }
        return try? JSONDecoder().decode([Book].self, from: data)
    }

    /// Fetches all pages of books and caches them. Updates bookCacheStates with live progress.
    ///
    /// Short-circuits when the server-side fingerprint (count + max updated_at)
    /// matches the one persisted alongside the cache, avoiding a full re-download
    /// on every app launch. Additionally throttles fingerprint checks to once
    /// per 60 s per library so rapid navigation doesn't spam the endpoint.
    func syncBooks(for library: Library, client: APIClient) async {
        let key = library.clientKey
        guard isEnabled(for: key) else { return }
        if case .syncing = bookCacheStates[key] { return }

        let now = Date()
        if let last = lastFingerprintCheck[key], now.timeIntervalSince(last) < 60 { return }
        lastFingerprintCheck[key] = now

        let fp: BookFingerprint
        do {
            fp = try await BookService(client: client).fingerprint(libraryId: library.id)
        } catch {
            // If fingerprint fails (e.g. older server without the endpoint) fall
            // through to a full sync only if we don't already have a cache.
            if cachedBooks(for: key) != nil { return }
            await fullSync(for: library, client: client, newFingerprint: nil)
            return
        }

        if let stored = UserDefaults.standard.string(forKey: fingerprintKey(key)),
           stored == fp.cacheToken,
           cachedBooks(for: key) != nil {
            return
        }

        await fullSync(for: library, client: client, newFingerprint: fp)
    }

    private func fullSync(for library: Library, client: APIClient, newFingerprint: BookFingerprint?) async {
        let key = library.clientKey
        bookCacheStates[key] = .syncing(progress: 0)
        var allBooks: [Book] = []
        let perPage = 100
        var page = 1

        do {
            let first = try await BookService(client: client).list(libraryId: library.id, page: page, perPage: perPage)
            allBooks.append(contentsOf: first.items)
            let total = max(first.total, 1)
            bookCacheStates[key] = .syncing(progress: Double(allBooks.count) / Double(total))

            while allBooks.count < first.total {
                page += 1
                let next = try await BookService(client: client).list(libraryId: library.id, page: page, perPage: perPage)
                allBooks.append(contentsOf: next.items)
                bookCacheStates[key] = .syncing(progress: Double(allBooks.count) / Double(total))
            }

            if let data = try? JSONEncoder().encode(allBooks) {
                try? data.write(to: booksFile(key), options: .atomic)
            }
            if let fp = newFingerprint {
                UserDefaults.standard.set(fp.cacheToken, forKey: fingerprintKey(key))
            }
            bookCacheStates[key] = .cached(bookCount: allBooks.count)
        } catch {
            if let existing = cachedBooks(for: key) {
                bookCacheStates[key] = .cached(bookCount: existing.count)
            } else {
                bookCacheStates[key] = .notCached
            }
        }
    }

    private var lastFingerprintCheck: [String: Date] = [:]

    // Filenames/UserDefaults keys derived from the composite clientKey need a
    // filesystem-safe representation since clientKey contains "://|" etc.
    private func safe(_ key: String) -> String {
        key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
    }
    private func libraryFile(_ key: String) -> URL { cacheDir.appendingPathComponent("lib_\(safe(key)).json") }
    private func booksFile(_ key: String) -> URL   { cacheDir.appendingPathComponent("books_\(safe(key)).json") }
    private func fingerprintKey(_ key: String) -> String { "offline_books_fp_\(safe(key))" }
    private func serverURLKey(_ key: String) -> String   { "offline_lib_url_\(safe(key))" }
    private func serverNameKey(_ key: String) -> String  { "offline_lib_server_\(safe(key))" }
}
