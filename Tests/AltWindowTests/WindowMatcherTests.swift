import XCTest
@testable import AltWindow

final class WindowMatcherTests: XCTestCase {
    let bounds = CGRect(x: 30, y: 40, width: 1200, height: 800)
    func candidate(_ id: UInt32, pid: Int32 = 10, title: String = "Page", bounds: CGRect? = nil) -> WindowCandidate {
        WindowCandidate(id: id, pid: pid, title: title, bounds: bounds ?? self.bounds)
    }
    func testChromeTitleMismatchStillMatchesUniqueGeometry() {
        XCTAssertEqual(WindowMatcher.match(pid: 10, title: "Page - Google Chrome", bounds: bounds,
                                            preferredID: nil, candidates: [candidate(42, title: "")]), 42)
    }
    func testSameSizeChromeWindowsUseTitleToDisambiguate() {
        XCTAssertEqual(WindowMatcher.match(pid: 10, title: "Second - Google Chrome", bounds: bounds, preferredID: nil,
                                            candidates: [candidate(41, title: "First"), candidate(42, title: "Second")]), 42)
    }
    func testNeverUsesAnotherAppsMatchingTitleOrID() {
        XCTAssertNil(WindowMatcher.match(pid: 10, title: "Page", bounds: bounds, preferredID: 42,
                                         candidates: [candidate(42, pid: 20)]))
    }
    func testMovedWindowUsesKnownID() {
        XCTAssertEqual(WindowMatcher.match(pid: 10, title: "Old title", bounds: .zero, preferredID: 42,
                                            candidates: [candidate(42, title: "New title")]), 42)
    }
    func testAmbiguousWindowsDoNotShowWrongPreview() {
        XCTAssertNil(WindowMatcher.match(pid: 10, title: "Page", bounds: bounds, preferredID: nil,
                                         candidates: [candidate(41), candidate(42)]))
    }
    func testAssignedPreviewCannotBeReusedForAnotherWindow() {
        XCTAssertNil(WindowMatcher.match(pid: 10, title: "Page", bounds: bounds, preferredID: 42,
                                         candidates: [candidate(42)], excluding: [42]))
    }
}
