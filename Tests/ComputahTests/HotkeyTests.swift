import XCTest
import CoreGraphics
@testable import Computah

final class HotkeyTests: XCTestCase {
    func testRightModifierDeviceMasksMatchSDKAndRejectLeftKeys() {
        let pairs: [(HotkeyModifier, UInt64, UInt64, Int64)] = [
            (.rightShift, 0x04, 0x02, 60), (.rightCommand, 0x10, 0x08, 54),
            (.rightOption, 0x40, 0x20, 61), (.rightControl, 0x2000, 0x01, 62)
        ]
        for (key, right, left, code) in pairs {
            XCTAssertEqual(key.keyCode, code)
            XCTAssertTrue(key.isSoloPress(flags: CGEventFlags(rawValue: right)))
            XCTAssertFalse(key.isPressed(flags: CGEventFlags(rawValue: left)))
            XCTAssertFalse(key.isSoloPress(flags: CGEventFlags(rawValue: right | left)))
        }
    }
    func testOrdinaryModifierCombinationsDoNotTriggerConversation() {
        XCTAssertTrue(HotkeyModifier.rightShift.isSoloPress(flags: [.maskShift, CGEventFlags(rawValue: 0x04)]))
        XCTAssertFalse(HotkeyModifier.rightShift.isSoloPress(flags: [.maskShift, .maskCommand, CGEventFlags(rawValue: 0x04)]))
        XCTAssertFalse(HotkeyModifier.rightControl.isSoloPress(flags: [.maskControl, .maskAlternate, CGEventFlags(rawValue: 0x2000)]))
    }

    func testRightShiftTapAndHoldHaveSeparateActions() {
        var gesture = HotkeyGesture()
        let down: CGEventFlags = [.maskShift, CGEventFlags(rawValue: 0x04)]
        XCTAssertEqual(gesture.flagsChanged(keyCode: 60, flags: down, modifier: .rightShift), .armHold)
        XCTAssertEqual(gesture.flagsChanged(keyCode: 60, flags: [], modifier: .rightShift), .tap)
        XCTAssertEqual(gesture.holdElapsed(), .none)
        XCTAssertEqual(gesture.flagsChanged(keyCode: 60, flags: down, modifier: .rightShift), .armHold)
        XCTAssertEqual(gesture.holdElapsed(), .hold)
        XCTAssertEqual(gesture.flagsChanged(keyCode: 60, flags: [], modifier: .rightShift), .release)
    }
    func testUnrelatedFlagsDoNotCancelHeldGestureButTypingDoes() {
        var gesture = HotkeyGesture()
        let down: CGEventFlags = [.maskShift, CGEventFlags(rawValue: 0x04)]
        XCTAssertEqual(gesture.flagsChanged(keyCode: 60, flags: down, modifier: .rightShift), .armHold)
        XCTAssertEqual(gesture.holdElapsed(), .hold)
        XCTAssertEqual(gesture.flagsChanged(keyCode: 0, flags: down, modifier: .rightShift), .none)
        XCTAssertEqual(gesture.keyDown(), .cancel)
        XCTAssertEqual(gesture.flagsChanged(keyCode: 60, flags: [], modifier: .rightShift), .none)
    }
    func testAddingAnotherModifierCancelsWithoutTogglingOnRelease() {
        var gesture = HotkeyGesture()
        let down: CGEventFlags = [.maskShift, CGEventFlags(rawValue: 0x04)]
        XCTAssertEqual(gesture.flagsChanged(keyCode: 60, flags: down, modifier: .rightShift), .armHold)
        let combined: CGEventFlags = [.maskShift, .maskCommand, CGEventFlags(rawValue: 0x0c)]
        XCTAssertEqual(gesture.flagsChanged(keyCode: 55, flags: combined, modifier: .rightShift), .cancel)
        XCTAssertEqual(gesture.holdElapsed(), .none)
        XCTAssertEqual(gesture.flagsChanged(keyCode: 60, flags: [], modifier: .rightShift), .none)
    }
    @MainActor
    func testLassoAcceptsFirstDragWhenAppIsInactive() {
        let view = LassoView(frame: .zero)
        XCTAssertTrue(view.acceptsFirstMouse(for: nil))
        XCTAssertTrue(view.acceptsFirstResponder)
    }

    @MainActor
    func testPartialEventTapMaskIsNotShortcutReady() {
        XCTAssertFalse(HotkeyController.containsRequiredEvents(1 << CGEventType.flagsChanged.rawValue))
        XCTAssertFalse(HotkeyController.containsRequiredEvents(1 << CGEventType.keyDown.rawValue))
        XCTAssertTrue(HotkeyController.containsRequiredEvents(HotkeyController.requiredEvents))
    }
}
