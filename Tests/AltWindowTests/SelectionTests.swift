import XCTest
@testable import AltWindow

final class SelectionTests: XCTestCase {
    func testStartingFromAnUnlistedAppSelectsMostRecentWindow() {
        var selection = Selection()
        selection.begin(ids: ["recent", "older"], currentID: nil, backwards: false)
        XCTAssertEqual(selection.finish(commit: true), "recent")
    }
    func testQuickSwitchReturnsPreviousWindow() {
        var selection = Selection()
        selection.begin(ids: ["current", "previous", "older"], currentID: "current", backwards: false)
        XCTAssertEqual(selection.finish(commit: true), "previous")
        XCTAssertFalse(selection.isOpen)
    }
    func testReverseFromCurrentWrapsToLastWindow() {
        var selection = Selection()
        selection.begin(ids: ["current", "previous", "older"], currentID: "current", backwards: true)
        XCTAssertEqual(selection.selectedID, "older")
        selection.step(-1)
        XCTAssertEqual(selection.finish(commit: true), "previous")
    }
    func testCancelNeverCommitsAndNextGestureStartsFresh() {
        var selection = Selection()
        selection.begin(ids: ["a", "b", "c"], currentID: "a", backwards: false)
        selection.step(1)
        XCTAssertNil(selection.finish(commit: false))
        XCTAssertNil(selection.finish(commit: true))
        selection.begin(ids: ["d", "e"], currentID: "d", backwards: false)
        XCTAssertEqual(selection.finish(commit: true), "e")
    }
    func testEmptyAndSingleWindow() {
        var selection = Selection()
        selection.begin(ids: [], currentID: nil, backwards: true)
        XCTAssertFalse(selection.isOpen)
        XCTAssertNil(selection.finish(commit: true))
        selection.begin(ids: ["only"], currentID: "only", backwards: true)
        selection.step(4)
        XCTAssertEqual(selection.finish(commit: true), "only")
    }
    func testCurrentWindowNeedNotBeFirstAndClickSelectsExactWindow() {
        var selection = Selection()
        selection.begin(ids: ["a", "b", "c"], currentID: "b", backwards: false)
        XCTAssertEqual(selection.selectedID, "c")
        selection.select(0)
        selection.select(99)
        XCTAssertEqual(selection.finish(commit: true), "a")
    }
}
