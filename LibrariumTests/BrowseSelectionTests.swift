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

    func testAContributorIsAskedForByIdAndCountsAsAFilter() {
        // By id, not by name. Naming a person is a different question from
        // searching for their name: "Tite" the person is not a book with Tite
        // in its title.
        var selection = BrowseSelection()
        selection.contributors = ["c-1", "c-2"]
        XCTAssertEqual(query(selection)["contributor"], "c-1,c-2")
        // It counts, even though the sheet has no section for it. A grid
        // narrowed to one author with no badge showing is a grid that looks
        // broken.
        XCTAssertEqual(selection.activeCount, 1)
        selection.clear()
        XCTAssertTrue(selection.contributors.isEmpty)
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

    // MARK: - Cancellation

    func testACancelledRequestIsNotAFailure() {
        // A view that goes away mid-request cancels it. Reporting that puts the
        // word "cancelled" in front of someone who did nothing but switch tabs,
        // and it also marks the load as having failed so nothing tries again.
        let urlCancel = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        XCTAssertTrue(BrowseViewModel.isCancellation(urlCancel))
        XCTAssertTrue(BrowseViewModel.isCancellation(CancellationError()))
        // Wrapped by the client, which is how it actually arrives.
        XCTAssertTrue(BrowseViewModel.isCancellation(APIError.networkError(urlCancel)))
    }

    func testARealNetworkFailureStillCounts() {
        // The guard has to be narrow. Treating every network error as a cancel
        // brings back the silent empty shelf this was meant to end.
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        XCTAssertFalse(BrowseViewModel.isCancellation(offline))
        XCTAssertFalse(BrowseViewModel.isCancellation(APIError.unauthorized))
    }

    // MARK: - Merging two servers

    private func book(title: String, created: String, year: Int?) throws -> Book {
        let y = year.map(String.init) ?? "null"
        let json = Data("""
        {"id":"\(title)","title":"\(title)","created_at":"\(created)","updated_at":"\(created)",
         "publish_year":\(y),"contributors":[],"tags":[],"genres":[],"libraries":[]}
        """.utf8)
        return try decoder().decode(Book.self, from: json)
    }

    func testTimestampsFromTwoZonesMergeByInstantNotByText() throws {
        // The later instant, written with an offset that sorts earlier as text.
        // Comparing the strings puts them the wrong way round, and a
        // recently-added list that is subtly wrong is worse than no sort.
        let earlier = try book(title: "Earlier", created: "2026-01-01T12:00:00+01:00", year: nil)
        let later = try book(title: "Later", created: "2026-01-01T12:00:00-04:00", year: nil)

        let newestFirst = BrowseViewModel.merge([earlier, later], by: .recentlyAdded)
        XCTAssertEqual(newestFirst.first?.title, "Later")
    }

    func testReleaseOrderUsesThePublishYear() throws {
        // Not updated_at, which is when somebody last touched the row.
        let old = try book(title: "Old", created: "2026-01-01T00:00:00Z", year: 1968)
        let new = try book(title: "New", created: "2020-01-01T00:00:00Z", year: 2024)

        XCTAssertEqual(BrowseViewModel.merge([old, new], by: .newestRelease).first?.title, "New")
        XCTAssertEqual(BrowseViewModel.merge([old, new], by: .oldestRelease).first?.title, "Old")
    }

    func testTitleOrderIgnoresALeadingArticle() throws {
        let bad = try book(title: "The Bad Guys", created: "2026-01-01T00:00:00Z", year: nil)
        let cat = try book(title: "Cat", created: "2026-01-01T00:00:00Z", year: nil)
        XCTAssertEqual(BrowseViewModel.merge([cat, bad], by: .titleAsc).first?.title, "The Bad Guys")
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

    // MARK: - Saved views

    func testAViewRoundTripsThroughItsQueryString() {
        // A view stores the same string the requests carry. If saving and
        // reopening used two spellings of one filter they would drift, and the
        // name on the chip would stop describing the list under it.
        var original = BrowseSelection()
        original[.ownership] = ["gap"]
        original[.mediaType] = ["manga"]
        original[.genre] = ["Horror", "Comedy"]
        original.contributors = ["c-1"]
        original.query = "bleach"

        let reopened = BrowseSelection(query: original.queryString())
        XCTAssertEqual(reopened[.ownership], ["gap"])
        XCTAssertEqual(reopened[.mediaType], ["manga"])
        XCTAssertEqual(reopened[.genre], ["Horror", "Comedy"])
        XCTAssertEqual(reopened.contributors, ["c-1"])
        XCTAssertEqual(reopened.query, "bleach")
        XCTAssertEqual(reopened.queryString(), original.queryString())
    }

    func testAViewWithNoOwnershipMeansEveryState() {
        // Not the shelf. A view saved on the web with the ownership filter
        // cleared was looking at wishlist entries and gaps too, and defaulting
        // here would quietly drop them from a list its author named.
        let reopened = BrowseSelection(query: "type=manga")
        XCTAssertTrue(reopened[.ownership].isEmpty)
        XCTAssertEqual(reopened[.mediaType], ["manga"])
    }

    func testAViewSurvivesAValueWithASeparatorInIt() {
        // Genres and tags are free text. A percent-encoded name has to come
        // back whole rather than split into two filters that match nothing.
        var original = BrowseSelection()
        original[.genre] = ["Boys' Love"]
        let reopened = BrowseSelection(query: original.queryString())
        XCTAssertEqual(reopened[.genre], ["Boys' Love"])
    }

    func testSeriesViewsRoundTripToo() {
        var original = SeriesSelection()
        original[.status] = ["ongoing"]
        original[.reading] = ["reading"]
        original.query = "one piece"

        let reopened = SeriesSelection(query: original.queryString())
        XCTAssertEqual(reopened[.status], ["ongoing"])
        XCTAssertEqual(reopened[.reading], ["reading"])
        XCTAssertEqual(reopened.query, "one piece")
    }

    func testAStoredViewDecodesItsSurfaceAndFilter() throws {
        // Taken off a running server. `surface` says which page it lands on and
        // `filter` is nested rather than a bare string.
        let json = Data("""
        {"id":"v-1","name":"Default","kind":"smart","surface":"series",
         "builtin_key":"default","filter":{"query":"status=ongoing"},"book_count":0}
        """.utf8)
        let view = try decoder().decode(SavedList.self, from: json)
        XCTAssertEqual(view.surface, "series")
        XCTAssertEqual(view.filterQuery, "status=ongoing")
        XCTAssertTrue(view.isSmart)
        XCTAssertTrue(view.isDefault)
    }

    func testAListFromBeforeSurfacesExistedLandsOnBooks() throws {
        let json = Data("""
        {"id":"l-1","name":"Childhood favourites","kind":"manual","book_count":1}
        """.utf8)
        let list = try decoder().decode(SavedList.self, from: json)
        XCTAssertEqual(list.surface, "books")
        XCTAssertEqual(list.filterQuery, "")
        XCTAssertFalse(list.isSmart)
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
