import XCTest
import AppKit
@testable import Computah

final class WakeWordTests: XCTestCase {
    func testRecognizesWakePhraseAcrossCaseAndPunctuation() {
        for phrase in ["Hey, Computer", "HEY COMPUTER!", "hey computah", "Okay. Hey, computer, help me.", "hey\ncomputer"] {
            XCTAssertTrue(WakePhrase.matches(phrase), phrase)
        }
    }

    func testRejectsPartialWordsAndUnrelatedSpeech() {
        for phrase in ["", "hey", "computer", "hey computerized", "they computer", "hey there computer", "my computer is on"] {
            XCTAssertFalse(WakePhrase.matches(phrase), phrase)
        }
    }

    @MainActor
    func testWakeNeverTogglesOffAnActiveConversation() {
        let model = AppModel(enableShortcuts: false, loadCredentials: false)
        model.active = true
        model.state = .listening
        model.wake()
        XCTAssertTrue(model.active)
        XCTAssertEqual(model.state, .listening)
        model.shutdownWakeListening()
        model.stop()
    }

    @MainActor
    func testOutsideClickCollapsesPanelWithoutStoppingVoice() {
        _ = NSApplication.shared
        let model = AppModel(enableShortcuts: false, loadCredentials: false)
        model.active = true; model.expanded = true
        let controller = PanelController(model: model)
        controller.panel.setFrame(NSRect(x: 100, y: 100, width: 410, height: 500), display: false)
        controller.dismissIfOutside(NSPoint(x: 200, y: 200))
        XCTAssertTrue(model.expanded)
        controller.dismissIfOutside(NSPoint(x: 50, y: 50))
        XCTAssertFalse(model.expanded)
        XCTAssertTrue(model.active)
        model.shutdownWakeListening(); model.stop()
        controller.panel.orderOut(nil)
    }
}
