// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import Foundation

/// Expand a scanned barcode into the set of ISBN-like strings worth
/// trying against a metadata source. Handles three real-world cases:
///
/// - 10-digit code → ISBN-10 → also derive ISBN-13 (Bookland 978 prefix)
/// - 13-digit code starting with 978/979 → ISBN-13 → also derive
///   ISBN-10 (the 978-prefixed form has a deterministic ISBN-10)
/// - 12-digit UPC-A → try as-is, plus the heuristic "drop check, prefix
///   978, recompute EAN check" form which catches mass-market
///   paperbacks issued before EAN-13 became the standard
///
/// Returns the original string verbatim plus any derived candidates;
/// dedup is the caller's responsibility (cheap to do — the set is at
/// most 3 elements).
enum ISBNCandidates {
    static func expand(_ raw: String) -> [String] {
        let digits = raw.filter { $0.isNumber || $0 == "X" || $0 == "x" }
        var out: [String] = [raw]

        switch digits.count {
        case 10:
            if let derived = isbn13(fromIsbn10: digits.uppercased()) {
                out.append(derived)
            }
        case 13 where digits.hasPrefix("978") || digits.hasPrefix("979"):
            if let derived = isbn10(fromIsbn13: digits) {
                out.append(derived)
            }
        case 13 where digits.hasPrefix("0"):
            // EAN-13 representation of a UPC-A (leading "0" + 12 UPC
            // digits). Strip the prefix and apply the UPC heuristic
            // below on the underlying 12-digit code.
            let upc = String(digits.dropFirst())
            if let derived = upcAToISBN13Heuristic(upc) {
                out.append(derived)
            }
        case 12:
            if let derived = upcAToISBN13Heuristic(digits) {
                out.append(derived)
            }
        default:
            break
        }
        return out
    }

    /// Heuristic for converting a UPC-A barcode on a book to a guessed
    /// ISBN-13. Many mass-market paperbacks pre-2007 carry a UPC-A
    /// whose middle 9 digits coincide with the book's ISBN-10 body —
    /// prepending "978" and recomputing the EAN check gives an
    /// ISBN-13 that Open Library / Google Books sometimes recognise.
    /// Far from guaranteed; treat as a best-effort fallback.
    static func upcAToISBN13Heuristic(_ upc: String) -> String? {
        let digits = upc.compactMap { $0.wholeNumberValue }
        guard digits.count == 12 else { return nil }
        // UPC-A on books usually has the ISBN-10 body in positions
        // 1..9, i.e. after the leading number-system digit. This used to
        // take `prefix(9)`, which includes that leading digit and so
        // shifted every derived ISBN by one place: the heuristic never
        // matched anything and only cost an extra round-trip.
        let body = "978" + String(upc.dropFirst().prefix(9))
        return body + String(ean13CheckDigit(for: body))
    }

    // MARK: - Math

    /// ISBN-10 → ISBN-13 conversion. Bookland prefix "978" + first 9
    /// digits + EAN-13 check digit.
    static func isbn13(fromIsbn10 isbn10: String) -> String? {
        let digits = isbn10.prefix(9)
        guard digits.count == 9, digits.allSatisfy({ $0.isNumber }) else { return nil }
        let body = "978" + digits
        return body + String(ean13CheckDigit(for: body))
    }

    /// ISBN-13 → ISBN-10 conversion. Only works for 978-prefixed
    /// codes; 979 codes have no ISBN-10 equivalent.
    static func isbn10(fromIsbn13 isbn13: String) -> String? {
        guard isbn13.count == 13, isbn13.hasPrefix("978") else { return nil }
        let body = isbn13.dropFirst(3).prefix(9)
        guard body.count == 9, body.allSatisfy({ $0.isNumber }) else { return nil }
        return body + String(isbn10CheckDigit(for: String(body)))
    }

    /// EAN-13 (and ISBN-13) check digit for a 12-digit body. Each digit
    /// is multiplied by 1 or 3 alternating; (10 - sum % 10) % 10 is
    /// the check.
    static func ean13CheckDigit(for body: String) -> Character {
        let digits = body.compactMap { $0.wholeNumberValue }
        guard digits.count == 12 else { return "0" }
        var sum = 0
        for (i, d) in digits.enumerated() {
            sum += (i % 2 == 0) ? d : d * 3
        }
        let check = (10 - sum % 10) % 10
        return Character(String(check))
    }

    /// ISBN-10 check digit for a 9-digit body. Digits 1..9 multiplied
    /// by 10..2 respectively; check = (11 - sum % 11) % 11, with 10
    /// rendered as 'X'.
    static func isbn10CheckDigit(for body: String) -> Character {
        let digits = body.compactMap { $0.wholeNumberValue }
        guard digits.count == 9 else { return "0" }
        var sum = 0
        for (i, d) in digits.enumerated() {
            sum += d * (10 - i)
        }
        let check = (11 - sum % 11) % 11
        return check == 10 ? "X" : Character(String(check))
    }
}
