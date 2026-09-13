import XCTest
@testable import Computah

final class NotchGeometryTests: XCTestCase {
    func testPhysicalNotchUsesAuxiliaryGapAndExactSafeAreaHeight() {
        let geometry = NotchGeometry(
            safeAreaTop: 32,
            auxiliaryTopLeftArea: CGRect(x: 2_560, y: 1_158, width: 663, height: 32),
            auxiliaryTopRightArea: CGRect(x: 3_408, y: 1_158, width: 664, height: 32)
        )

        XCTAssertEqual(geometry.notchWidth, 185)
        XCTAssertEqual(geometry.notchHeight, 32)
        XCTAssertEqual(geometry.collapsedHeight, 32)
    }

    func testExternalDisplayKeepsExistingFallbackDimensions() {
        let geometry = NotchGeometry(
            safeAreaTop: 0,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        )

        XCTAssertEqual(geometry.notchWidth, 120)
        XCTAssertEqual(geometry.notchHeight, 24)
        XCTAssertEqual(geometry.collapsedHeight, 32)
    }
}
