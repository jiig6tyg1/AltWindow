import XCTest
import ServiceManagement
import AppKit
@testable import AltWindow

@MainActor
private final class FakeLoginItem: LoginItemManaging {
    var status: SMAppService.Status = .notRegistered
    var registrationResult: SMAppService.Status = .enabled
    var fail = false
    var registerCalls = 0
    var unregisterCalls = 0
    func register() throws {
        registerCalls += 1
        if fail { throw NSError(domain: "Test", code: 99) }
        status = registrationResult
    }
    func unregister() async throws {
        unregisterCalls += 1
        if fail { throw NSError(domain: "Test", code: 99) }
        status = .notRegistered
    }
    func openSettings() {}
}

final class LoginItemTests: XCTestCase {
    @MainActor func testEnableAndDisableReflectSystemState() async {
        let service = FakeLoginItem()
        let controller = LoginItemController(service: service)
        await controller.setEnabled(true)
        XCTAssertTrue(controller.isRegistered)
        XCTAssertEqual(service.registerCalls, 1)
        await controller.setEnabled(false)
        XCTAssertFalse(controller.isRegistered)
        XCTAssertEqual(service.unregisterCalls, 1)
    }

    @MainActor func testApprovalPendingIsNotReportedAsEnabled() async {
        let service = FakeLoginItem()
        service.registrationResult = .requiresApproval
        let controller = LoginItemController(service: service)
        await controller.setEnabled(true)
        XCTAssertTrue(controller.isRegistered)
        XCTAssertEqual(controller.status, .requiresApproval)
        XCTAssertTrue(controller.detail.contains("許可"))
        await controller.setEnabled(false)
        XCTAssertFalse(controller.isRegistered)
    }

    @MainActor func testRegistrationFailureDoesNotLeaveToggleOn() async {
        let service = FakeLoginItem()
        service.fail = true
        let controller = LoginItemController(service: service)
        await controller.setEnabled(true)
        XCTAssertFalse(controller.isRegistered)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertFalse(controller.isChanging)
    }

    @MainActor func testFailedDisablePreservesActualEnabledState() async {
        let service = FakeLoginItem()
        service.status = .enabled
        service.fail = true
        let controller = LoginItemController(service: service)
        await controller.setEnabled(false)
        XCTAssertTrue(controller.isRegistered)
        XCTAssertNotNil(controller.errorMessage)
    }

    @MainActor func testExternalChangeIsReflectedWithoutRegisteringAgain() async {
        let service = FakeLoginItem()
        service.status = .enabled
        let controller = LoginItemController(service: service)
        await controller.setEnabled(true)
        XCTAssertEqual(service.registerCalls, 0)
        service.status = .notRegistered
        controller.refresh()
        XCTAssertFalse(controller.isRegistered)
    }

    func testBackgroundStartupNeverDisplaysPermissionsWindow() {
        XCTAssertFalse(StartupPresentation.shouldShowSettings(missingPermissions: true, loginItemRegistered: true, backgroundLaunch: false, explicitlyRequested: false))
        XCTAssertFalse(StartupPresentation.shouldShowSettings(missingPermissions: true, loginItemRegistered: false, backgroundLaunch: true, explicitlyRequested: false))
        XCTAssertTrue(StartupPresentation.shouldShowSettings(missingPermissions: true, loginItemRegistered: false, backgroundLaunch: false, explicitlyRequested: false))
        XCTAssertTrue(StartupPresentation.shouldShowSettings(missingPermissions: false, loginItemRegistered: true, backgroundLaunch: true, explicitlyRequested: true))
    }

    func testLoginAppleEventAndExplicitBackgroundArgument() {
        let event = NSAppleEventDescriptor.appleEvent(withEventClass: AEEventClass(kCoreEventClass),
                                                     eventID: AEEventID(kAEOpenApplication), targetDescriptor: nil,
                                                     returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: AEKeyword(keyAEPropData))
        XCTAssertTrue(StartupPresentation.isBackgroundLaunch(event: event, arguments: []))
        XCTAssertTrue(StartupPresentation.isBackgroundLaunch(event: nil, arguments: ["AltWindow", "--background"]))
        XCTAssertFalse(StartupPresentation.isBackgroundLaunch(event: nil, arguments: ["AltWindow"]))
    }
}
