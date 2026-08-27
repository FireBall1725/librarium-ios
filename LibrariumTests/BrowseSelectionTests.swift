// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import XCTest
@testable import Librarium

/// The selection is the only thing standing between a tick in the filter sheet
/// and the two requests that have to agree about it. Everything here is about
/// the URL it produces, because that is where a wrong answer becomes a list and
/// a count that disagree.
@MainActor
final class BrowseSelectionTests: XCTestCase {

    private func query(_ selection: BrowseSelection) -> [String: String] {
        var out: [String: String] = [:]
        for item in selection.queryItems() { out[item.name] = item.value }
        return out
    }

    func testDefaultsToTheShelf() {
        // Without this the first thing anyone sees is their wishlist and a
        // machine's suggestions mixed into the books they actually have.
        XCTAssertEqual(query(BrowseSelection())["own"], "shelf")
    }

    func testTheDefaultDoesNotCountAsAFilter() {
        // The badge on the filter button says how many filters are on. A reader
        // who has touched nothing has none.
        XCTAssertEqual(BrowseSelection().activeCount, 0)
    }

    func testClearedOwnershipSendsNothingRatherThanSnappingBack() {
        // Ownership left empty means every state, which the API expresses by
        // receiving no ownership parameter. Defaulting again here would make
        // "show me everything" impossible to ask for.
        var selection = BrowseSelection()
        selection.toggle(.ownership, "shelf")
        XCTAssertNil(query(selection)["own"])
        XCTAssertEqual(selection.activeCount, 0)
    }

    func testGapsAreReachable() {
        var selection = BrowseSelection()
        selection[.ownership] = ["gap"]
        XCTAssertEqual(query(selection)["own"], "gap")
    }

    func testEveryDimensionUsesTheParameterTheServerReads() {
        var selection = BrowseSelection()
        selection[.library] = ["lib-1"]
        selection[.shelf] = ["list-1"]
        selection[.location] = ["loc-1"]
        selection[.readStatus] = ["reading"]
        selection[.favourite] = ["true"]
        selection[.rating] = ["8"]
        selection[.myRating] = ["10"]
        selection[.mediaType] = ["manga"]
        selection[.tag] = ["signed"]
        selection[.genre] = ["Horror"]
        let q = query(selection)

        XCTAssertEqual(q["lib"], "lib-1")
        // Not "list". The URL on the web says list because that is the word the
        // reader sees, but the server has always called the facet shelf.
        XCTAssertEqual(q["shelf"], "list-1")
        XCTAssertEqual(q["location"], "loc-1")
        XCTAssertEqual(q["status"], "reading")
        XCTAssertEqual(q["fav"], "true")
        XCTAssertEqual(q["rating"], "8")
        XCTAssertEqual(q["my_rating"], "10")
        XCTAssertEqual(q["type"], "manga")
        XCTAssertEqual(q["tag"], "signed")
        XCTAssertEqual(q["genre"], "Horror")
    }

    func testTheSameSelectionAlwaysProducesTheSameURL() {
        // Set iteration order is not stable, and an unstable URL defeats every
        // cache between the phone and the database.
        var a = BrowseSelection()
        a[.genre] = ["Horror", "Comedy", "Drama"]
        var b = BrowseSelection()
        b[.genre] = ["Drama", "Horror", "Comedy"]
        XCTAssertEqual(query(a)["genre"], query(b)["genre"])
        XCTAssertEqual(query(a)["genre"], "Comedy,Drama,Horror")
    }

    func testAnEmptySearchIsNotASearch() {
        var selection = BrowseSelection()
        selection.query = "   "
        XCTAssertNil(query(selection)["q"])
    }

    // MARK: - Counts

    func testCountsFromTwoServersAddUpByValue() {
        // One install can hold several accounts and there is no server that can
        // count across them. A genre both servers know is one row; a library is
        // a UUID and stays two.
        var first = BookFacets()
        first.genre = [FacetValue(value: "Horror", label: "Horror", count: 3)]
        first.library = [FacetValue(value: "lib-a", label: "Home", count: 10)]
        var second = BookFacets()
        second.genre = [FacetValue(value: "Horror", label: "Horror", count: 4)]
        second.library = [FacetValue(value: "lib-b", label: "Work", count: 5)]

        let merged = first.merged(with: second)
        XCTAssertEqual(merged.genre.count, 1)
        XCTAssertEqual(merged.genre.first?.count, 7)
        XCTAssertEqual(merged.library.count, 2)
    }

    // MARK: - Labels

    func testRatingsReadAsStarsRatherThanPoints() {
        // Stored in whole points where two points are one star, so an 8 handed
        // to a reader who counts stars is a wrong number, not a raw one.
        XCTAssertEqual(FacetLabels.stars("8"), "4 stars")
        XCTAssertEqual(FacetLabels.stars("7"), "3½ stars")
        XCTAssertEqual(FacetLabels.stars("2"), "1 star")
    }

    func testAGapIsCalledWhatPeopleCallIt() {
        XCTAssertEqual(FacetLabels.ownership("gap"), "Missing volume")
        XCTAssertEqual(FacetLabels.ownership("shelf"), "On the shelf")
    }

    // MARK: - Decoding what the server actually sends

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    func testAMissingVolumeDecodesWithNoLibrary() throws {
        // Taken off a running server. A gap is a book row nobody holds, so it
        // has no library and no cover, and a decoder that assumes either drops
        // every missing volume on the floor: 187 books on this collection.
        let json = Data("""
        {"id":"b-7","title":"Absolute Boyfriend #7","subtitle":"","description":"",
         "media_type":"Manga","media_type_id":"mt-1","cover_url":null,
         "created_at":"2026-08-26T15:24:56Z","updated_at":"2026-08-26T15:24:56Z",
         "libraries":[],"library_id":null,"ownership":"gap","shelves":[],
         "tags":[],"genres":[],"active_loan_count":0,"user_rating":0,
         "user_progress_pct":0,"user_read_status":"unread",
         "contributors":[{"contributor_id":"c-1","name":"Yuu Watase","role":"author","display_order":0}]}
        """.utf8)

        let book = try decoder().decode(Book.self, from: json)
        XCTAssertEqual(book.ownership, "gap")
        XCTAssertEqual(book.libraryId, "")
        XCTAssertNil(book.coverUrl)
        XCTAssertEqual(book.contributors.first?.name, "Yuu Watase")
    }

    func testTheCountsAreWrappedTwice() throws {
        // `/me/books/facets` builds its body as `{"data": facets}` and the
        // response writer wraps every body in `data` again. Unwrapping once
        // lands on an envelope, and decoding straight into BookFacets there
        // finds none of its keys: no error, and a filter sheet with nothing in
        // it. The service compensates, and this is what would catch the day
        // the API stops double-wrapping.
        struct Envelope: Decodable { let data: BookFacets }
        let json = Data("""
        {"data":{"ownership":[{"value":"gap","label":"gap","count":187}],
                 "library":[{"value":"lib-1","label":"Book Collection","count":1425}]}}
        """.utf8)

        let outer = try decoder().decode(Envelope.self, from: json)
        XCTAssertEqual(outer.data.ownership.first?.count, 187)
        XCTAssertEqual(outer.data.library.first?.label, "Book Collection")

        // The mistake this guards against, spelled out: one unwrap too few
        // decodes cleanly and returns nothing.
        let wrong = try decoder().decode(BookFacets.self, from: json)
        XCTAssertTrue(wrong.ownership.isEmpty)
    }
}
