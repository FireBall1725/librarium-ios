// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import XCTest
@testable import Librarium

/// A run is a length, a count of what is held, and the difference between them.
/// Everything here is about getting that difference right, because it is the
/// number the whole surface exists to show.
@MainActor
final class SeriesBrowseTests: XCTestCase {

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    private func series(bookCount: Int, totalCount: Int?) throws -> Series {
        let total = totalCount.map(String.init) ?? "null"
        let json = Data("""
        {"id":"s-1","library_id":"lib-1","name":"Bleach","created_at":"2026-01-01T00:00:00Z",
         "updated_at":"2026-01-01T00:00:00Z","book_count":\(bookCount),"total_count":\(total),
         "status":"completed","rating":8,"rated_books":3,"read_count":2}
        """.utf8)
        return try decoder().decode(Series.self, from: json)
    }

    func testMissingIsTheDifference() throws {
        XCTAssertEqual(try series(bookCount: 6, totalCount: 7).missingCount, 1)
    }

    func testARunOfUnknownLengthIsMissingNothingKnown() throws {
        // nil is not zero. A run nobody has recorded the length of cannot be
        // said to be complete, and saying so would put every unfinished
        // collection in the clear.
        XCTAssertNil(try series(bookCount: 6, totalCount: nil).missingCount)
    }

    func testHoldingMoreThanTheStatedLengthIsNotNegative() throws {
        // An anniversary reprint or a volume the publisher never counted, and
        // "-2 missing" on the row is worse than saying nothing.
        XCTAssertEqual(try series(bookCount: 9, totalCount: 7).missingCount, 0)
    }

    func testTheRatingReadsAsStars() throws {
        // Whole points where two points are one star.
        XCTAssertEqual(try series(bookCount: 1, totalCount: 1).ratingStars, 4)
    }

    // MARK: - Volumes

    private func entry(_ json: String) throws -> SeriesEntry {
        try decoder().decode(SeriesEntry.self, from: Data(json.utf8))
    }

    func testAVolumeNobodyHasStillDecodes() throws {
        let e = try entry("""
        {"position":7,"position_end":null,"book_id":"b-7","title":"Bleach #7",
         "held":false,"user_read_status":"unread"}
        """)
        XCTAssertFalse(e.held)
        XCTAssertEqual(e.positionLabel, "7")
    }

    func testAnOlderServerIsAssumedToHoldWhatItLists() throws {
        // The field did not always exist. Reading its absence as "nobody has
        // this" would grey out an entire collection.
        let e = try entry("""
        {"position":1,"book_id":"b-1","title":"Bleach #1"}
        """)
        XCTAssertTrue(e.held)
    }

    func testAnOmnibusSpansThePositionsItCovers() throws {
        // It sits at the first volume it contains rather than taking a position
        // of its own, so the run reads 1-3, 4, 5 instead of two volume ones.
        let e = try entry("""
        {"position":1,"position_end":3,"book_id":"b-o","title":"Bleach 3-in-1","held":true}
        """)
        XCTAssertEqual(e.positionLabel, "1-3")
    }

    func testAHalfVolumeKeepsItsHalf() throws {
        // Side stories and specials are numbered 4.5, which is why the column
        // is numeric rather than an integer.
        let e = try entry("""
        {"position":4.5,"book_id":"b-45","title":"Side story","held":true}
        """)
        XCTAssertEqual(e.positionLabel, "4.5")
    }

    // MARK: - Selection

    func testSeriesFiltersUseTheParametersTheIndexReads() {
        var selection = SeriesSelection()
        selection[.library] = ["lib-1"]
        selection[.mediaType] = ["manga"]
        selection[.status] = ["ongoing"]
        selection[.arcs] = ["with"]
        selection[.reading] = ["read_all"]
        selection[.genre] = ["Horror"]
        selection[.tag] = ["signed"]
        selection[.rating] = ["8"]
        selection[.myRating] = ["10"]

        var q: [String: String] = [:]
        for item in selection.queryItems() { q[item.name] = item.value }
        XCTAssertEqual(q["lib"], "lib-1")
        XCTAssertEqual(q["type"], "manga")
        XCTAssertEqual(q["status"], "ongoing")
        XCTAssertEqual(q["arcs"], "with")
        XCTAssertEqual(q["reading"], "read_all")
        XCTAssertEqual(q["genre"], "Horror")
        XCTAssertEqual(q["tag"], "signed")
        XCTAssertEqual(q["rating"], "8")
        XCTAssertEqual(q["my_rating"], "10")
    }

    // MARK: - Loans

    private func loan(due: String?, returned: String? = nil) throws -> Loan {
        let d = due.map { "\"\($0)\"" } ?? "null"
        let r = returned.map { "\"\($0)\"" } ?? "null"
        let json = Data("""
        {"id":"l-1","library_id":"lib-1","book_id":"b-1","book_title":"Bleach #1",
         "loaned_to":"Sam","loaned_at":"2026-01-01","due_date":\(d),"returned_at":\(r),
         "notes":"","tags":[],"created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"}
        """.utf8)
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(Loan.self, from: json)
    }

    func testALoanPastItsDueDateIsOverdue() throws {
        XCTAssertTrue(try loan(due: "2020-01-01").isOverdue)
    }

    func testALoanWithNoDueDateIsNeverOverdue() throws {
        // It was lent open-endedly. Inventing a deadline would put a red badge
        // on a book nobody is waiting for.
        XCTAssertFalse(try loan(due: nil).isOverdue)
        XCTAssertNil(try loan(due: nil).dueLabel)
    }

    func testAReturnedLoanIsNotOverdueHoweverLateItWas() throws {
        let back = try loan(due: "2020-01-01", returned: "2026-01-01T00:00:00Z")
        XCTAssertFalse(back.isActive)
        XCTAssertFalse(back.isOverdue)
    }

    func testAFullTimestampDueDateStillParses() throws {
        // The column is a date on one route and a timestamp on another, so both
        // spellings arrive and neither can be assumed.
        XCTAssertTrue(try loan(due: "2020-01-01T12:30:00Z").isOverdue)
    }

    // MARK: - Wishlist

    func testAWishNeedNotBeACatalogueRow() throws {
        // Most of what anyone writes down in a shop is a book no catalogue has
        // heard of, so a null book id is the ordinary case rather than an error.
        let json = Data("""
        {"id":"w-1","book_id":null,"title":"Something I saw","author_name":"","notes":"","priority":0}
        """.utf8)
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let entry = try d.decode(WishlistEntry.self, from: json)
        XCTAssertNil(entry.bookId)
        XCTAssertEqual(entry.title, "Something I saw")
    }

    // MARK: - Containment

    func testAContainmentLinkNamesTheFarEnd() throws {
        // The list routes fill only one end: asking what a book contains gives
        // contained_id and leaves the container implicit, and asking what
        // contains it does the reverse. A row that followed the wrong end would
        // navigate back to the book already on screen.
        let json = Data("""
        {"container_id":"omnibus-1","contained_id":"vol-2","title":"Bleach #2","position":2}
        """.utf8)
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let link = try d.decode(BookContentLink.self, from: json)

        XCTAssertEqual(link.otherID(from: "omnibus-1"), "vol-2")
        XCTAssertEqual(link.otherID(from: "vol-2"), "omnibus-1")
        XCTAssertEqual(link.positionLabel, "2")
    }

    func testOnlyRunsWithGapsIsNotSentToTheServer() {
        // The server has no facet for it. It is a subtraction over counts every
        // row already carries, so sending it would be asking for a filter that
        // does not exist.
        var selection = SeriesSelection()
        selection.incompleteOnly = true
        XCTAssertTrue(selection.queryItems().isEmpty)
        // It still counts as a filter, or the badge under-reports and "why is
        // half my list gone" has no visible cause.
        XCTAssertEqual(selection.activeCount, 1)
    }
}
