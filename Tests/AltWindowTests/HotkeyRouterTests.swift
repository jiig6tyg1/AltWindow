import XCTest
@testable import AltWindow

final class HotkeyRouterTests: XCTestCase {
    func testQuickTabThenEscapeIsConsumedBeforePanelHasRendered() {
        var router = HotkeyRouter()
        XCTAssertTrue(router.keyDown(48, option: true, command: false, control: false, canOpen: true, panelOpen: false))
        XCTAssertTrue(router.keyDown(53, option: true, command: false, control: false, canOpen: true, panelOpen: false))
        XCTAssertFalse(router.gestureActive)
    }
    func testCommandTabAndEmptyCatalogArePassedThrough() {
        var router = HotkeyRouter()
        XCTAssertFalse(router.keyDown(48, option: true, command: true, control: false, canOpen: true, panelOpen: false))
        XCTAssertFalse(router.keyDown(48, option: true, command: false, control: false, canOpen: false, panelOpen: false))
    }
    func testOptionReleaseEndsGestureAndOrdinaryTypingPassesThrough() {
        var router = HotkeyRouter()
        _ = router.keyDown(48, option: true, command: false, control: false, canOpen: true, panelOpen: false)
        XCTAssertFalse(router.keyDown(0, option: true, command: false, control: false, canOpen: true, panelOpen: true))
        router.flagsChanged(option: false)
        XCTAssertFalse(router.keyDown(123, option: false, command: false, control: false, canOpen: true, panelOpen: false))
    }
}
