// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 FireBall1725 (Adaléa)

import XCTest
@testable import Librarium

/// Reading state is keyed to the work now, and two things about that decode
/// path fail silently rather than loudly if they regress.
@MainActor
final class ReadingStateTests: XCTestCase {
    // Decoding runs on the main actor because the app's models are
    // main-actor-isolated by default under Swift 6 concurrency.
    private func decode(_ json: String) throws -> MyBook {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(MyBook.self, from: Data(json.utf8))
    }

    /// The row id is what the sync outbox addresses offline edits by. Dropping
    /// it does not fail a build or a request: edits simply stop being queued,
    /// and nothing says so.
    func testCarriesTheRowIDTheOutboxNeeds() throws {
        let mine = try decode("""
        {"id":"6aeb0be2-b34d-4ef9-8ef6-c8ef1f088737",
         "book_id":"00efc871-a8b6-43e9-830c-f68988f99ab2",
         "read_status":"read","rating":8,"is_favorite":true,
         "review":"r","notes":"n","wants":false,"inherited":false}
        """)
        XCTAssertEqual(mine.id, "6aeb0be2-b34d-4ef9-8ef6-c8ef1f088737")
        XCTAssertNotNil(UUID(uuidString: mine.id),
                        "the outbox parses this as a UUID; an unparsable one enqueues nothing")

        let folded = mine.asInteraction(editionID: "edition-1")
        XCTAssertEqual(folded.id, mine.id, "folding into the old shape must keep the id")
        XCTAssertEqual(folded.bookEditionId, "edition-1")
    }

    /// A book nobody has said anything about answers with defaults rather than
    /// a 404, so the decode has to survive a body with almost nothing in it.
    func testDecodesTheDefaultAnswerForAnUntouchedBook() throws {
        let mine = try decode("""
        {"book_id":"00efc871-a8b6-43e9-830c-f68988f99ab2",
         "read_status":"unread","is_favorite":false,
         "review":"","notes":"","wants":false,"inherited":false}
        """)
        XCTAssertEqual(mine.readStatus, "unread")
        XCTAssertNil(mine.rating)
        // No row yet, so no id. The outbox must not queue an edit against one.
        XCTAssertEqual(mine.id, "")
        XCTAssertNil(UUID(uuidString: mine.id))
    }

    /// Inherited says the status came from a container the reader finished, not
    /// from this book. Losing it makes a volume nobody opened read as Read with
    /// no explanation.
    func testInheritedSurvivesTheDecode() throws {
        let mine = try decode("""
        {"book_id":"00efc871-a8b6-43e9-830c-f68988f99ab2",
         "read_status":"read","is_favorite":false,
         "review":"","notes":"","wants":false,"inherited":true}
        """)
        XCTAssertTrue(mine.inherited)
    }

    /// The capability probe decides which route a given server is asked for.
    /// It has to fail closed: an unreachable server means the per-edition
    /// route, which every version still serves.
    func testCapabilityProbeFailsClosed() async {
        await ServerCapabilities.shared.forgetAll()
        // A port nothing listens on, so the probe cannot succeed.
        let answer = await ServerCapabilities.shared
            .hasWorkKeyedReadingState(serverURL: "http://127.0.0.1:9")
        XCTAssertFalse(answer, "an unreachable server must fall back, not claim the new route")
        await ServerCapabilities.shared.forgetAll()
    }
}

/// Lists reach further than shelves did: a shelf is a list shared with a
/// library, so the shelf read never returned a private one.
@MainActor
final class SavedListTests: XCTestCase {
    private func decode(_ json: String) throws -> SavedList {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(SavedList.self, from: Data(json.utf8))
    }

    func testDecodesAPrivateManualList() throws {
        let list = try decode("""
        {"id":"11111111-1111-1111-1111-111111111111","name":"Lent to James",
         "description":"","icon":"lent","color":"","kind":"manual",
         "visibility":"private","shared_library_id":null,"book_count":4,
         "builtin_key":""}
        """)
        XCTAssertEqual(list.name, "Lent to James")
        XCTAssertEqual(list.bookCount, 4)
        XCTAssertFalse(list.isSmart)
        XCTAssertNil(list.sharedLibraryId, "a private list belongs to no library")
    }

    /// A shelf answers the same question on a server too old for lists, so the
    /// fold has to produce something the same view can render.
    func testAShelfFoldsIntoAList() {
        let shelf = Shelf(
            id: "s1", libraryId: "lib1", name: "Signed", description: "",
            color: "#ff0000", icon: "star", displayOrder: 0, bookCount: 3,
            tags: [], createdAt: "", updatedAt: ""
        )
        let folded = shelf.asSavedList
        XCTAssertEqual(folded.id, "s1")
        XCTAssertEqual(folded.bookCount, 3)
        XCTAssertEqual(folded.kind, "manual")
        XCTAssertEqual(folded.visibility, "library",
                       "a shelf is a list shared with a library, which is what made it visible")
        XCTAssertEqual(folded.sharedLibraryId, "lib1")
    }

    /// The icon field holds two different things. Rendering a name as text drew
    /// the literal word "star" for anything the web client made.
    func testIconResolvesNamesButLeavesEmojiAlone() {
        XCTAssertEqual(ListIcon.symbol(for: "star"), "star")
        XCTAssertEqual(ListIcon.symbol(for: "lent"), "arrow.up.right")
        XCTAssertNil(ListIcon.symbol(for: "📚"), "an emoji is not a name and must be drawn as itself")
        XCTAssertNil(ListIcon.symbol(for: ""))
    }
}
