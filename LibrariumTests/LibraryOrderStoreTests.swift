import XCTest
@testable import Librarium

/// Tests the per-device drag-reorder persistence layer that drives the
/// Libraries list and the scan-result rows. The store is small but
/// load-bearing: a regression that lost the saved order would silently
/// re-shuffle every connected user's library list on the next boot.
///
/// `@MainActor` — `Library` and `LibraryOrderStore` carry the default
/// main-actor isolation Swift 6 / iOS 26 inherits across the project.
@MainActor
final class LibraryOrderStoreTests: XCTestCase {

    /// Each test gets its own UserDefaults suite so writes from one
    /// case don't bleed into another. The default suite (`.standard`)
    /// is shared global state and would make these tests order-
    /// dependent.
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "LibraryOrderStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeLibrary(_ name: String, id: String = UUID().uuidString, server: String = "https://a.example") -> Library {
        var lib = Library(
            id: id,
            name: name,
            description: "",
            slug: name.lowercased(),
            ownerId: UUID().uuidString,
            isPublic: false,
            createdAt: "",
            updatedAt: "",
            bookCount: nil,
            readingCount: nil,
            readCount: nil
        )
        lib.serverURL = server
        lib.serverName = server
        return lib
    }

    /// With no saved order, `sorted(_:)` returns libraries in
    /// case-insensitive alphabetical order — the documented fallback
    /// when the user hasn't dragged anything yet.
    func testSortedAlphabeticalWhenNoSavedOrder() {
        let store = LibraryOrderStore(defaults: defaults)
        let libraries = [
            makeLibrary("zeta"),
            makeLibrary("Alpha"),
            makeLibrary("beta"),
        ]
        let sorted = store.sorted(libraries)
        XCTAssertEqual(sorted.map { $0.name }, ["Alpha", "beta", "zeta"])
    }

    /// User-defined order is preserved across the sorted projection
    /// when every library is in the saved order.
    func testSortedRespectsSavedOrder() {
        let store = LibraryOrderStore(defaults: defaults)
        let a = makeLibrary("Alpha")
        let b = makeLibrary("Beta")
        let c = makeLibrary("Gamma")

        store.setOrder(from: [c, a, b])

        // Pass them in a different order to prove sorted(_:) is
        // pulling from the saved list, not just preserving input.
        let sorted = store.sorted([b, a, c])
        XCTAssertEqual(sorted.map { $0.name }, ["Gamma", "Alpha", "Beta"])
    }

    /// New libraries that aren't in the saved order land at the bottom,
    /// alphabetically sorted among themselves. Matches the user-facing
    /// rule "new servers / new libraries appear at the bottom".
    func testNewLibrariesAppendAtBottom() {
        let store = LibraryOrderStore(defaults: defaults)
        let a = makeLibrary("Alpha")
        let b = makeLibrary("Beta")

        store.setOrder(from: [b, a])

        let newLib = makeLibrary("Gamma")
        let anotherNew = makeLibrary("Delta")

        let sorted = store.sorted([a, b, newLib, anotherNew])
        XCTAssertEqual(sorted.map { $0.name }, ["Beta", "Alpha", "Delta", "Gamma"])
    }

    /// Stale `clientKey`s — for libraries on a server that's since been
    /// removed — are silently dropped from the projection. The order
    /// store tolerates them because purging at remove-time is best-
    /// effort; this test pins that the read path filters cleanly.
    func testStaleSavedKeysAreFiltered() {
        let store = LibraryOrderStore(defaults: defaults)
        let live = makeLibrary("Live")
        let removed = makeLibrary("Removed")

        store.setOrder(from: [removed, live])

        // Only "Live" comes back from the server this boot.
        let sorted = store.sorted([live])
        XCTAssertEqual(sorted.map { $0.name }, ["Live"])
    }

    /// Two libraries on different servers can share a UUID (DB
    /// transplant case noted in the README); the store keys on
    /// `clientKey` (serverURL + id) to disambiguate. This test guards
    /// against a regression that collapsed them.
    func testSharedUUIDAcrossServersStaysDistinct() {
        let store = LibraryOrderStore(defaults: defaults)
        let sharedID = UUID().uuidString

        let libA = makeLibrary("A", id: sharedID, server: "https://server-one.example")
        let libB = makeLibrary("B", id: sharedID, server: "https://server-two.example")

        store.setOrder(from: [libB, libA])

        let sorted = store.sorted([libA, libB])
        XCTAssertEqual(sorted.map { $0.serverURL },
                       ["https://server-two.example", "https://server-one.example"])
    }

    /// Order persists across store re-instantiation — the contract
    /// future boots rely on. A regression that wrote to memory but
    /// not UserDefaults would pass every other test in this file.
    func testOrderSurvivesReinstantiation() {
        let storeA = LibraryOrderStore(defaults: defaults)
        let a = makeLibrary("Alpha")
        let b = makeLibrary("Beta")

        storeA.setOrder(from: [b, a])

        let storeB = LibraryOrderStore(defaults: defaults)
        let sorted = storeB.sorted([a, b])
        XCTAssertEqual(sorted.map { $0.name }, ["Beta", "Alpha"])
    }
}
