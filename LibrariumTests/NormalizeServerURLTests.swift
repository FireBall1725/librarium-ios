import XCTest
@testable import Librarium

/// `normalizeServerURL(_:)` is the small but load-bearing helper that
/// turns whatever the user typed into a `ServerAccount.url` we can hand
/// to APIClient. Every onboarding session and every re-auth flow runs
/// through it. Pin the contract so future "let me just clean up the
/// URL handling" PRs can't quietly change it.
final class NormalizeServerURLTests: XCTestCase {

    func testPrependsHTTPSWhenSchemeMissing() {
        XCTAssertEqual(
            normalizeServerURL("librarium.example.com"),
            "https://librarium.example.com"
        )
    }

    func testPreservesExistingHTTPS() {
        XCTAssertEqual(
            normalizeServerURL("https://librarium.example.com"),
            "https://librarium.example.com"
        )
    }

    func testPreservesExistingHTTPForLocalDev() {
        // Local-dev users on 127.0.0.1 should stay on http; we only
        // upgrade the *missing-scheme* case to https.
        XCTAssertEqual(
            normalizeServerURL("http://localhost:8080"),
            "http://localhost:8080"
        )
    }

    func testStripsTrailingSlash() {
        XCTAssertEqual(
            normalizeServerURL("https://librarium.example.com/"),
            "https://librarium.example.com"
        )
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(
            normalizeServerURL("  librarium.example.com  "),
            "https://librarium.example.com"
        )
    }

    func testPreservesPortAndPath() {
        XCTAssertEqual(
            normalizeServerURL("https://librarium.example.com:8443/api"),
            "https://librarium.example.com:8443/api"
        )
    }

    func testRejectsEmpty() {
        XCTAssertNil(normalizeServerURL(""))
        XCTAssertNil(normalizeServerURL("   "))
    }

    /// Only http/https are accepted — file://, ftp://, javascript:,
    /// etc. should fail validation rather than silently become an
    /// APIClient error later.
    func testRejectsUnsupportedSchemes() {
        XCTAssertNil(normalizeServerURL("file:///etc/passwd"))
        XCTAssertNil(normalizeServerURL("ftp://librarium.example.com"))
        XCTAssertNil(normalizeServerURL("javascript:alert(1)"))
    }

    func testRejectsHostlessInput() {
        // A bare path with a scheme and no host is malformed.
        XCTAssertNil(normalizeServerURL("https://"))
    }
}
