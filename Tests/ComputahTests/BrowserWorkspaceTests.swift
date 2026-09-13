import XCTest
@testable import Computah

@MainActor
private final class InstalledComputerUseFixture: CodexComputerUseTransport {
    var available = false
    var connectionError: Error?
    var connectCount = 0
    var calls: [(String, [String: Any])] = []
    var delay: Duration = .zero
    var stopCount = 0
    func connect() async throws {
        connectCount += 1
        if let connectionError { throw connectionError }
        available = true
    }
    func call(name: String, arguments: [String: Any]) async throws -> [String: Any] {
        calls.append((name, arguments))
        if delay != .zero { try await Task.sleep(for: delay) }
        return ["content": [["type": "text", "text": "Untrusted application state"]]]
    }
    func stop() { stopCount += 1 }
}

final class BrowserWorkspaceTests: XCTestCase {
    @MainActor
    func testUnavailableInstalledClientFailsBeforeAnyComputerAction() async {
        let transport = InstalledComputerUseFixture()
        transport.connectionError = CodexComputerUseError.unavailable
        let browser = BrowserWorkspace(transport: transport)
        do { try await browser.prepareForTask(title: "Research"); XCTFail("Unresponsive client must block startup") }
        catch { XCTAssertEqual(error.localizedDescription, CodexComputerUseError.unavailable.localizedDescription) }
        XCTAssertEqual(transport.connectCount, 1)
        XCTAssertTrue(transport.calls.isEmpty)
        XCTAssertFalse(browser.workspaceReady)
        XCTAssertFalse(browser.hasTaskTab)
        XCTAssertNil(browser.preview)
    }

    @MainActor
    func testInstalledAppActionsRefreshStateWithoutClaimingOwnedTabs() async throws {
        let transport = InstalledComputerUseFixture()
        let browser = BrowserWorkspace(transport: transport)
        try await browser.prepareForTask(title: "Research")
        XCTAssertTrue(browser.workspaceReady)
        XCTAssertFalse(browser.hasTaskTab)
        _ = try await browser.perform(name: "computer_click", arguments: ["app": "Chrome", "element_index": "17"])
        XCTAssertEqual(transport.calls.map { $0.0 }, ["get_app_state", "click"])
        XCTAssertEqual(transport.calls.last?.1["element_index"] as? String, "17")
        let output = try await browser.perform(name: "computer_get_app_state", arguments: ["app": "Chrome"])
        XCTAssertTrue((output.first?["text"] as? String ?? "").contains("Tasks share app controls"))
        XCTAssertEqual(output.last?["text"] as? String, "Untrusted application state")
    }

    @MainActor
    func testReviewToolLocksTaskBeforeFurtherActions() async throws {
        let transport = InstalledComputerUseFixture()
        let browser = BrowserWorkspace(transport: transport)
        try await browser.prepareForTask(title: "Research")
        var callback: String?
        browser.onReviewRequested = { callback = $0; browser.stopAgentWork() }
        let output = try await browser.perform(name: "computer_request_review", arguments: ["reason": "Review before purchase."])
        XCTAssertEqual(callback, "Review before purchase.")
        XCTAssertTrue((output.first?["text"] as? String ?? "").hasPrefix("MANUAL_REVIEW_REQUIRED"))
        do { _ = try await browser.perform(name: "computer_click", arguments: ["app": "Chrome", "x": 10, "y": 10]); XCTFail("Review must stop further actions") } catch { }
        XCTAssertTrue(transport.calls.isEmpty)
        try await browser.enableManualReview()
        XCTAssertTrue(browser.manualControl)
        XCTAssertEqual(transport.stopCount, 0)
    }

    @MainActor
    func testInvalidArgumentsNeverReachInstalledClient() async throws {
        let transport = InstalledComputerUseFixture()
        let browser = BrowserWorkspace(transport: transport)
        try await browser.prepareForTask(title: "Research")
        let invalid: [[String: Any]] = [
            ["app": "Chrome", "element_index": "1", "x": 10, "y": 10],
            ["app": "Chrome", "x": true, "y": 10],
            ["app": "Chrome", "x": -1, "y": 10],
            ["app": "Chrome", "x": 10],
            ["app": "Chrome", "element_index": "1", "click_count": 4],
            ["app": "Chrome", "element_index": "1", "script": "not an allowed argument"]
        ]
        for arguments in invalid {
            do { _ = try await browser.perform(name: "computer_click", arguments: arguments); XCTFail("Invalid arguments must fail") } catch { }
        }
        XCTAssertTrue(transport.calls.isEmpty)
    }

    @MainActor
    func testSharedQueueKeepsRefreshAndMutationTogetherAcrossTasks() async throws {
        let transport = InstalledComputerUseFixture()
        transport.delay = .milliseconds(20)
        let first = BrowserWorkspace(transport: transport)
        let second = BrowserWorkspace(transport: transport)
        try await first.prepareForTask(title: "First")
        try await second.prepareForTask(title: "Second")
        async let one = first.perform(name: "computer_click", arguments: ["app": "Chrome", "element_index": "1"])
        async let two = second.perform(name: "computer_type_text", arguments: ["app": "Notes", "text": "Draft"])
        _ = try await (one, two)
        let names = transport.calls.map { $0.0 }
        XCTAssertEqual(names[0], "get_app_state")
        XCTAssertEqual(names[2], "get_app_state")
        XCTAssertEqual(Set([names[1], names[3]]), ["click", "type_text"])
        XCTAssertEqual(transport.calls[0].1["app"] as? String, transport.calls[1].1["app"] as? String)
        XCTAssertEqual(transport.calls[2].1["app"] as? String, transport.calls[3].1["app"] as? String)
    }

    @MainActor
    func testManualTakeoverWaitsForDispatchedActionWithoutStoppingSharedClient() async throws {
        let transport = InstalledComputerUseFixture()
        transport.delay = .milliseconds(40)
        let browser = BrowserWorkspace(transport: transport)
        try await browser.prepareForTask(title: "Research")
        let action = Task { try await browser.perform(name: "computer_click", arguments: ["app": "Chrome", "element_index": "1"]) }
        while transport.calls.count < 2 { try await Task.sleep(for: .milliseconds(2)) }
        browser.stopAgentWork()
        var returnedControl = false
        let takeover = Task { try await browser.enableManualReview(); returnedControl = true }
        try await Task.sleep(for: .milliseconds(5))
        XCTAssertFalse(returnedControl)
        _ = try? await action.value
        try await takeover.value
        XCTAssertTrue(returnedControl)
        XCTAssertTrue(browser.manualControl)
        XCTAssertEqual(transport.stopCount, 0)
        await browser.detach()
        XCTAssertEqual(transport.stopCount, 0)
    }
}
