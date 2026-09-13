import XCTest
import ScreenCaptureKit
@testable import Computah

final class PermissionTests: XCTestCase {
    @MainActor
    func testAccessibilityRequestIsExplicitAndNeverClaimsPendingApproval() {
        var prompts = 0, settings = 0
        let allowed = Permissions.requestAccessibility(check: { false }, request: {
            prompts += 1; return false
        }, openSettings: { settings += 1 })
        XCTAssertFalse(allowed)
        XCTAssertEqual(prompts, 1)
        XCTAssertEqual(settings, 1)
    }

    @MainActor
    func testTrustedAccessibilityNeverPromptsAgain() {
        var prompts = 0, settings = 0
        let allowed = Permissions.requestAccessibility(check: { true }, request: {
            prompts += 1; return false
        }, openSettings: { settings += 1 })
        XCTAssertTrue(allowed)
        XCTAssertEqual(prompts, 0)
        XCTAssertEqual(settings, 0)
    }

    func testInputAccessAcceptsEitherActualSystemCheck() {
        XCTAssertTrue(Permissions.inputMonitoringAccess(coreGraphics: true, hidGranted: false))
        XCTAssertTrue(Permissions.inputMonitoringAccess(coreGraphics: false, hidGranted: true))
        XCTAssertFalse(Permissions.inputMonitoringAccess(coreGraphics: false, hidGranted: false))
    }

    @MainActor
    func testInputRequestRegistersOnceAndOpensSettingsWithoutPretendingAccess() {
        var requests = 0, settings = 0
        let allowed = Permissions.requestInputMonitoring(check: { false }, request: {
            requests += 1; return false
        }, openSettings: { settings += 1 })
        XCTAssertFalse(allowed)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(settings, 1)
    }

    @MainActor
    func testAlreadyGrantedInputAccessNeverRequestsConsent() {
        var requests = 0, settings = 0
        let allowed = Permissions.requestInputMonitoring(check: { true }, request: {
            requests += 1; return false
        }, openSettings: { settings += 1 })
        XCTAssertTrue(allowed)
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(settings, 0)
    }

    @MainActor
    func testInputRequestRechecksActualAccessBeforeReportingAllowed() {
        var granted = false, settings = 0
        let allowed = Permissions.requestInputMonitoring(check: { granted }, request: {
            granted = true; return true
        }, openSettings: { settings += 1 })
        XCTAssertTrue(allowed)
        XCTAssertEqual(settings, 0)
    }

    @MainActor
    func testRepeatedAutomaticChecksAfterDenialNeverProbeOrAllowCapture() async {
        Permissions.recordScreenAccess(.denied)
        var probeCalls = 0
        for _ in 0..<20 {
            let status = await Permissions.checkScreenAccess(allowPrompt: false, preflight: false) {
                probeCalls += 1
                return .available
            }
            XCTAssertEqual(status, .denied)
            XCTAssertFalse(Permissions.canAttemptScreenCapture(preflight: false))
        }
        XCTAssertEqual(probeCalls, 0)
    }

    @MainActor
    func testOnlyExplicitRequestProbesAfterDenialAndRemembersWorkingAccess() async {
        Permissions.recordScreenAccess(.denied)
        var probeCalls = 0
        let status = await Permissions.checkScreenAccess(allowPrompt: true, preflight: false) {
            probeCalls += 1
            return .available
        }
        XCTAssertEqual(status, .available)
        XCTAssertEqual(probeCalls, 1)
        let passive = await Permissions.checkScreenAccess(allowPrompt: false, preflight: false) {
            probeCalls += 1
            return .denied
        }
        XCTAssertEqual(passive, .available)
        XCTAssertTrue(Permissions.canAttemptScreenCapture(preflight: false))
        XCTAssertEqual(probeCalls, 1)
        Permissions.recordScreenAccess(.denied)
    }

    @MainActor
    func testChangedSettingsPreflightUnlocksDeniedLatchWithoutProbe() async {
        Permissions.recordScreenAccess(.denied)
        var probeCalls = 0
        let status = await Permissions.checkScreenAccess(allowPrompt: false, preflight: true) {
            probeCalls += 1
            return .denied
        }
        XCTAssertEqual(status, .available)
        XCTAssertEqual(probeCalls, 0)
        XCTAssertTrue(Permissions.canAttemptScreenCapture(preflight: false))
        Permissions.recordScreenAccess(.denied)
    }

    func testShareableDisplayConfirmsAccessWithoutPreflight() {
        XCTAssertEqual(Permissions.screenAccessStatus(error: nil, displayCount: 1), .available)
    }

    func testConfirmedUserDeclineIsDenied() {
        let error = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
        XCTAssertEqual(Permissions.screenAccessStatus(error: error, displayCount: 0), .denied)
    }

    func testWrappedUserDeclineIsDenied() {
        let underlying = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
        let error = NSError(domain: NSCocoaErrorDomain, code: 1, userInfo: [NSUnderlyingErrorKey: underlying])
        XCTAssertEqual(Permissions.screenAccessStatus(error: error, displayCount: 0), .denied)
    }

    func testServiceFailureAndMissingDisplayDoNotClaimDenialOrAccess() {
        let error = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.internalError.rawValue)
        if case .unavailable = Permissions.screenAccessStatus(error: error, displayCount: 1) {} else {
            XCTFail("A service failure must remain unknown, even when display metadata exists")
        }
        if case .unavailable = Permissions.screenAccessStatus(error: nil, displayCount: 0) {} else {
            XCTFail("An empty display list cannot confirm usable capture access")
        }
    }

    func testSameErrorNumberFromOtherDomainIsNotDenial() {
        let error = NSError(domain: NSCocoaErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
        XCTAssertFalse(Permissions.isScreenAccessDenied(error))
    }
}
