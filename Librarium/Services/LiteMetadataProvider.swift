// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation

/// A metadata source a Lite library can query directly from the device.
///
/// Self-hosted installs get their metadata through the api, which fans
/// out across six providers server-side. Lite has no server, so the app
/// talks to the sources itself. Keeping them behind one protocol means
/// the refresh flow does not care which is configured.
protocol LiteMetadataProvider: Sendable {
    /// Stable identifier written into `ISBNLookupResult.provider`.
    var id: String { get }
    /// Shown in the picker when more than one source returns a match.
    var displayName: String { get }
    /// False when the source needs credentials the user has not supplied.
    /// An unconfigured provider is skipped rather than surfaced as an error.
    var isConfigured: Bool { get }
    /// True when using this provider sends data to a third party that can
    /// identify the user. Drives the copy on the settings screen.
    var isAuthenticated: Bool { get }

    func lookup(isbn: String) async throws -> [ISBNLookupResult]
    func search(query: String) async throws -> [ISBNLookupResult]
}

/// Errors surfaced to the user rather than swallowed. Everything else is
/// treated as "this provider had nothing", because one source failing
/// should never block the others.
enum LiteMetadataError: LocalizedError {
    case notConfigured(provider: String)
    case invalidKey(provider: String)
    case rateLimited(provider: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let p):
            return "\(p) is not set up yet. Add your API key in Settings."
        case .invalidKey(let p):
            return "\(p) rejected the API key. Check it in Settings."
        case .rateLimited(let p):
            return "\(p) is rate limiting requests. Try again in a minute."
        }
    }
}

/// Runs every configured provider and merges what comes back.
///
/// Ordering is deliberate: results arrive in provider order, and the
/// review sheet uses the first non-empty value per field. So a source
/// that returns a description outranks one that returns an empty string
/// for it, without either having to know the other exists.
struct LiteMetadataAggregator {
    let providers: [LiteMetadataProvider]

    /// Providers that can actually run right now.
    var configured: [LiteMetadataProvider] { providers.filter(\.isConfigured) }

    /// What a fan-out produced, keeping enough detail to tell "nobody
    /// has this book" apart from "nobody could be reached". The scan
    /// flow shows different copy for each, and telling a user their ISBN
    /// is unknown when the real problem is aeroplane mode sends them
    /// hunting for a barcode that was fine.
    struct Outcome {
        let results: [ISBNLookupResult]
        /// True when every provider threw, so nothing was actually asked.
        let allFailed: Bool
    }

    /// Look up by ISBN across every configured provider, concurrently.
    /// A provider that throws contributes nothing; the others still count.
    func lookup(isbn: String) async -> [ISBNLookupResult] {
        await lookupDetailed(isbn: isbn).results
    }

    func lookupDetailed(isbn: String) async -> Outcome {
        await run { provider in try await provider.lookup(isbn: isbn) }
    }

    /// Free-text search for books that have no ISBN to look up. Used by
    /// the refresh flow's "pick the match" step.
    func search(query: String) async -> [ISBNLookupResult] {
        await run { provider in try await provider.search(query: query) }.results
    }

    /// Fan out across configured providers and return their results in
    /// **provider order**, not completion order.
    ///
    /// This matters because `merge` takes the first non-empty value per
    /// field, so whoever comes first wins. A plain `for await` over a
    /// task group yields whichever provider answered fastest, which made
    /// the winning source a race: the same book could come back with
    /// different metadata run to run. Tagging each result with its index
    /// and sorting restores the priority the provider list declares.
    private func run(
        _ work: @escaping @Sendable (LiteMetadataProvider) async throws -> [ISBNLookupResult]
    ) async -> Outcome {
        let ordered = configured
        guard !ordered.isEmpty else { return Outcome(results: [], allFailed: false) }

        // nil marks a provider that threw, which is how allFailed can
        // tell an outage from a genuine miss.
        let collected = await withTaskGroup(of: (Int, [ISBNLookupResult]?).self) { group in
            for (index, provider) in ordered.enumerated() {
                group.addTask { (index, try? await work(provider)) }
            }
            var out: [(Int, [ISBNLookupResult]?)] = []
            for await result in group { out.append(result) }
            return out.sorted { $0.0 < $1.0 }
        }

        return Outcome(
            results: collected.compactMap(\.1).flatMap { $0 },
            allFailed: collected.allSatisfy { $0.1 == nil }
        )
    }

    /// Merge candidates into one result, taking the first non-empty value
    /// for each field. Input order is provider priority order, so the
    /// higher-priority source wins any field it can answer and the rest
    /// fill the gaps. Open Library rarely has a description and
    /// Hardcover usually does, so the union beats either source alone.
    static func merge(_ results: [ISBNLookupResult]) -> ISBNLookupResult? {
        guard let first = results.first else { return nil }
        func pick(_ keyPath: KeyPath<ISBNLookupResult, String>) -> String {
            results.first(where: { !$0[keyPath: keyPath].isEmpty })?[keyPath: keyPath] ?? ""
        }
        let authors = results.first(where: { !$0.authors.isEmpty })?.authors ?? []
        let pageCount = results.first(where: { ($0.pageCount ?? 0) > 0 })?.pageCount
        let categories = results.first(where: { !($0.categories ?? []).isEmpty })?.categories

        // Credit every source that contributed, so the review sheet can
        // say where the incoming values came from.
        let names = results.map(\.providerDisplay)
        var seen = Set<String>()
        let credited = names.filter { seen.insert($0).inserted }

        return ISBNLookupResult(
            provider: first.provider,
            providerDisplay: credited.joined(separator: " + "),
            title: pick(\.title),
            subtitle: pick(\.subtitle),
            authors: authors,
            publisher: pick(\.publisher),
            publishDate: pick(\.publishDate),
            isbn10: pick(\.isbn10),
            isbn13: pick(\.isbn13),
            description: pick(\.description),
            coverUrl: pick(\.coverUrl),
            language: pick(\.language),
            pageCount: pageCount,
            categories: categories
        )
    }
}
