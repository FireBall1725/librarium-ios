// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation

extension String {
    /// Sort key matching the api's `natural_sort_key()` Postgres function.
    /// - Strips a multilingual list of leading articles ("the", "a", "an",
    ///   "le", "la", "el", etc.) so "The Bad Guys" sorts under B.
    /// - Drops a leading "l'" so "L'Assommoir" sorts under A.
    /// - Lowercases the remainder.
    /// - Zero-pads embedded digit sequences to 10 characters so "Bleach #2"
    ///   sorts before "Bleach #10".
    ///
    /// Kept in lockstep with `sort_title` + `natural_sort_key` in
    /// `api/internal/db/migrations/000001_init_schema.up.sql`. If a new
    /// article gets added on the server, mirror it here.
    func librariumSortKey() -> String {
        let articles = "unos|unas|eine|the|les|una|une|des|los|las|gli|het|een|das|der|die|dem|den|det|ein|ett|uma|um|os|as|le|la|lo|el|un|de|na|az|yr|il|et|en|y|an|o|a"
        var working = trimmingCharacters(in: .whitespacesAndNewlines)
        working = Self.replaceLeading(in: working, pattern: "^(?:\(articles))\\s+")
        working = Self.replaceLeading(in: working, pattern: "^l['\u{2019}]")
        working = working.lowercased()
        return Self.padDigits(in: working)
    }

    private static func replaceLeading(in source: String, pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return source
        }
        let range = NSRange(source.startIndex..., in: source)
        return regex.stringByReplacingMatches(in: source, range: range, withTemplate: "")
    }

    private static func padDigits(in source: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "[0-9]+") else { return source }
        let nsRange = NSRange(source.startIndex..., in: source)
        let matches = regex.matches(in: source, range: nsRange)
        guard !matches.isEmpty else { return source }

        var result = ""
        var cursor = source.startIndex
        for match in matches {
            guard let range = Range(match.range, in: source) else { continue }
            result.append(contentsOf: source[cursor..<range.lowerBound])
            let digits = String(source[range])
            if digits.count < 10 {
                result.append(String(repeating: "0", count: 10 - digits.count))
            }
            result.append(digits)
            cursor = range.upperBound
        }
        result.append(contentsOf: source[cursor...])
        return result
    }
}
