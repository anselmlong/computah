import XCTest
import ScreenCaptureKit
@testable import Computah

final class PermissionTests: XCTestCase {
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
