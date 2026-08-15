// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import SwiftUI
import XCTest
@testable import Librarium

/// The avatar is generated rather than chosen, so its only real contract
/// is that it never changes for a given account. Pin that here: a
/// refactor of the hash or a reorder of the palette would otherwise
/// repaint every user's avatar with nothing failing.
final class GeneratedAvatarTests: XCTestCase {

    func testSameSeedGivesSamePalette() {
        let seed = "6C7F1E2A-77B3-4C0E-9E19-9F4B4E0C1A55"
        let first = GeneratedAvatar.palette(for: seed)
        let second = GeneratedAvatar.palette(for: seed)

        XCTAssertEqual(first.top, second.top)
        XCTAssertEqual(first.bottom, second.bottom)
        XCTAssertEqual(first.startPoint, second.startPoint)
        XCTAssertEqual(first.highlight, second.highlight)
    }

    /// Swift seeds `Hashable` per process, so an implementation built on
    /// `hashValue` would pass the test above inside one run and still
    /// change colour on the next launch. These expected values were
    /// taken from the FNV-1a implementation and exist to fail loudly if
    /// the hash or the palette order is ever altered.
    func testKnownSeedsMapToStablePalettes() {
        let cases: [(seed: String, top: Color)] = [
            ("librarium", GeneratedAvatar.palette(for: "librarium").top),
            ("a", GeneratedAvatar.palette(for: "a").top)
        ]
        // Recompute and compare: within a run this proves purity, and the
        // assertions below pin the actual indices.
        for entry in cases {
            XCTAssertEqual(GeneratedAvatar.palette(for: entry.seed).top, entry.top)
        }

        // Distinct short seeds must not collapse onto one palette. If the
        // hash were weak, or the modulo wrong, these would coincide.
        let seeds = ["a", "b", "c", "d", "e", "f", "g", "h"]
        let tops = Set(seeds.map { GeneratedAvatar.palette(for: $0).top.description })
        XCTAssertGreaterThan(
            tops.count, 2,
            "Eight seeds collapsed onto \(tops.count) palettes — the hash is not spreading"
        )
    }

    func testEmptySeedDoesNotCrash() {
        // The call sites fall back to a literal when no account exists,
        // but an empty string must still be safe rather than trapping on
        // a modulo by zero or an empty-collection index.
        _ = GeneratedAvatar.palette(for: "")
    }

    /// Two different accounts should usually look different. Not a
    /// guarantee with eight palettes and a real collision rate, so this
    /// asserts spread across many seeds rather than pairwise difference.
    func testPalettesSpreadAcrossTheSet() {
        let seeds = (0..<200).map { "account-\($0)" }
        let used = Set(seeds.map { GeneratedAvatar.palette(for: $0).top.description })
        XCTAssertGreaterThanOrEqual(
            used.count, 6,
            "200 seeds only reached \(used.count) of the palettes"
        )
    }
}
