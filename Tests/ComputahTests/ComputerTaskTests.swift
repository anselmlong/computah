import XCTest
import AppKit
@testable import Computah

final class ComputerTaskTests: XCTestCase {
    @MainActor
    func testConcurrentTasksKeepIndependentWorkersBrowsersAndDelegations() async throws {
        _ = NSApplication.shared
        let peer = ComputerTaskTestPeer()
        let manager = peer.manager()
        let voiceID = UUID()
        var callbacks: [UUID: Int] = [:]
        var reviewed: [UUID: String] = [:]
        var callbackDelegations: [UUID: Set<String>] = [:]
        manager.onResult = { session, _ in
            callbacks[session.id, default: 0] += 1
            callbackDelegations[session.id] = session.delegationIDs
            XCTAssertEqual(session.voiceSessionID, voiceID)
        }
        manager.onReview = { session, text in
            reviewed[session.id] = text
            callbackDelegations[session.id] = session.delegationIDs
            XCTAssertFalse(session.worker.running)
        }
        let first = manager.start(task: "Research the first job", context: "", apiKey: "dummy-no-real-credentials", delegationIDs: ["first-delegation"], voiceSessionID: voiceID)
        let second = manager.start(task: "Prepare the second job", context: "", apiKey: "dummy-no-real-credentials", delegationIDs: ["second-delegation"], voiceSessionID: voiceID)
        let third = manager.start(task: "Find the third job", context: "", apiKey: "dummy-no-real-credentials", delegationIDs: ["third-delegation"], voiceSessionID: voiceID)
        defer { manager.stopAll() }
        try await waitUntil { manager.sessions.allSatisfy { $0.state == .working } }
        XCTAssertEqual(manager.sessions.count, 3)
        XCTAssertEqual(Set(manager.sessions.map(\.id)).count, 3)
        XCTAssertTrue(manager.sessions.allSatisfy { $0.worker.running })
        XCTAssertFalse(first.worker === second.worker)
        XCTAssertFalse(first.browser === second.browser)
        XCTAssertFalse(first.browser.webView === third.browser.webView)
        XCTAssertFalse(first.browser.webView.configuration.websiteDataStore === third.browser.webView.configuration.websiteDataStore)

        // A completion from another task cannot terminate this worker.
        peer.emit(0, method: "turn/completed", params: ["threadId": "thread-2", "turn": ["id": "turn-2", "status": "completed"]])
        XCTAssertEqual(first.state, .working)
        second.stop()
        second.stop()
        XCTAssertEqual(second.state, .cancelled)
        XCTAssertTrue(first.worker.running)
        XCTAssertTrue(third.worker.running)
        XCTAssertEqual(callbacks[second.id], 1)

        peer.finish(0, text: "First job researched.")
        peer.emit(2, method: "item/tool/call", id: "third-review-rpc", params: [
            "threadId": "thread-2", "turnId": "turn-2", "callId": "third-review", "namespace": NSNull(),
            "tool": "browser_request_review", "arguments": ["reason": "Review the third job."]
        ])
        try await waitUntil { first.state == .completed && third.state == .review }
        XCTAssertEqual(callbacks[first.id], 1)
        XCTAssertEqual(reviewed[third.id], "Review the third job.")
        XCTAssertEqual(callbackDelegations[first.id], ["first-delegation"])
        XCTAssertEqual(callbackDelegations[second.id], ["second-delegation"])
        XCTAssertEqual(callbackDelegations[third.id], ["third-delegation"])
        first.addDelegations(["late-first-delegation"])
        XCTAssertEqual(first.delegationIDs, ["first-delegation", "late-first-delegation"])
        XCTAssertEqual(callbacks[first.id], 1)

        manager.stopAll()
        XCTAssertEqual(first.state, .completed)
        XCTAssertEqual(first.result, "First job researched.")
        XCTAssertEqual(third.state, .review)
        XCTAssertEqual(third.result, "Review the third job.")
        XCTAssertEqual(manager.sessions.count, 3)
        XCTAssertFalse(manager.sessions.contains { $0.worker.running })
        XCTAssertEqual(callbacks[second.id], 1)
    }

    @MainActor
    func testCancelBeforeStartupAndQuitEmitEachCancellationOnce() async throws {
        _ = NSApplication.shared
        let peer = ComputerTaskTestPeer()
        let manager = peer.manager()
        var callbacks: [UUID: Int] = [:]
        manager.onResult = { session, _ in callbacks[session.id, default: 0] += 1 }
        let canceled = manager.start(task: "Research jobs", context: "", apiKey: "dummy-no-real-credentials")
        canceled.stop()
        let running = manager.start(task: "Research jobs", context: "", apiKey: "dummy-no-real-credentials")
        try await waitUntil { running.state == .working }
        XCTAssertNil(peer.connections[0])
        XCTAssertNotEqual(canceled.title, running.title)
        XCTAssertEqual(canceled.state, .cancelled)
        XCTAssertEqual(callbacks[canceled.id], 1)
        manager.stopAll()
        manager.stopAll()
        XCTAssertEqual(running.state, .cancelled)
        XCTAssertEqual(callbacks[running.id], 1)
        XCTAssertEqual(callbacks[canceled.id], 1)
        XCTAssertEqual(manager.sessions.count, 2)
    }

    @MainActor
    func testManualTakeoverChangesOnlyItsSessionAndCompletesReviewOnce() async throws {
        _ = NSApplication.shared
        let peer = ComputerTaskTestPeer()
        let manager = peer.manager()
        var reviews: [UUID: Int] = [:]
        var results: [UUID: Int] = [:]
        manager.onReview = { session, _ in reviews[session.id, default: 0] += 1 }
        manager.onResult = { session, _ in results[session.id, default: 0] += 1 }
        let first = manager.start(task: "Review this task manually", context: "", apiKey: "dummy-no-real-credentials")
        let second = manager.start(task: "Continue another task", context: "", apiKey: "dummy-no-real-credentials")
        defer { manager.stopAll() }
        try await waitUntil { first.state == .working && second.state == .working }
        first.takeOver()
        first.takeOver()
        XCTAssertEqual(first.state, .manualReview)
        XCTAssertTrue(first.browser.manualControl)
        XCTAssertFalse(first.worker.running)
        XCTAssertEqual(reviews[first.id], 1)
        XCTAssertNil(results[first.id])
        XCTAssertEqual(second.state, .working)
        XCTAssertTrue(second.worker.running)
        XCTAssertFalse(second.browser.manualControl)
        peer.finish(0, text: "A stale result must be ignored.")
        XCTAssertEqual(first.state, .manualReview)
        XCTAssertFalse(first.result.contains("stale result"))
        manager.stopAll()
        XCTAssertEqual(first.state, .manualReview)
        XCTAssertEqual(reviews[first.id], 1)
        XCTAssertNil(results[first.id])
        XCTAssertEqual(second.state, .cancelled)
        XCTAssertEqual(results[second.id], 1)
    }

    @MainActor
    func testBrowsingAndFailedSessionsRemainAvailableWithoutStartingOtherWorkers() async throws {
        _ = NSApplication.shared
        let peer = ComputerTaskTestPeer()
        let manager = peer.manager()
        let browsing = manager.createBrowsingSession(title: "Browse manually")
        XCTAssertEqual(browsing.state, .manualReview)
        XCTAssertTrue(browsing.browser.manualControl)
        XCTAssertFalse(browsing.worker.running)
        var callbacks: [UUID] = []
        manager.onResult = { session, _ in callbacks.append(session.id) }
        let failures = (0..<4).map { manager.start(task: "Task \($0)", context: "", apiKey: "") }
        try await waitUntil { failures.allSatisfy { $0.state == .failed } }
        XCTAssertEqual(Set(callbacks), Set(failures.map(\.id)))
        XCTAssertEqual(peer.connections.count, 0)
        manager.stopAll()
        XCTAssertEqual(manager.sessions.count, 5)
        XCTAssertTrue(failures.allSatisfy { $0.state == .failed })
        XCTAssertEqual(browsing.state, .manualReview)
    }

    @MainActor
    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<400 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Fake computer sessions did not reach the expected state")
        throw ComputahError.message("Timed out waiting for fake computer sessions.")
    }
}

@MainActor
private final class ComputerTaskTestPeer {
    var connections: [Int: CodexRPC] = [:]
    private var nextIndex = 0

    func manager() -> ComputerTaskManager {
        ComputerTaskManager(workerFactory: { browser in
            let index = self.nextIndex
            self.nextIndex += 1
            return CodexWorker(browser: browser, rpcFactory: { _, _, environment, directory in
                let script = """
                IFS= read -r fixture_line
                printf '%s\\n' '{"id":1,"result":{}}'
                IFS= read -r fixture_line
                IFS= read -r fixture_line
                printf '%s\\n' '{"id":2,"result":{"model":"gpt-5.6-sol","modelProvider":"computah_openai","thread":{"id":"thread-\(index)"}}}'
                IFS= read -r fixture_line
                printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-\(index)"}}}'
                while IFS= read -r fixture_line; do :; done
                """
                let rpc = CodexRPC(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script], environment: environment, directory: directory)
                self.connections[index] = rpc
                return rpc
            })
        })
    }

    func emit(_ index: Int, method: String, id: String? = nil, params: [String: Any]) {
        var message: [String: Any] = ["method": method, "params": params]
        if let id { message["id"] = id }
        var data = try! JSONSerialization.data(withJSONObject: message)
        data.append(0x0a)
        connections[index]?.receive(data)
    }

    func finish(_ index: Int, text: String) {
        emit(index, method: "item/completed", params: [
            "threadId": "thread-\(index)", "turnId": "turn-\(index)",
            "item": ["type": "agentMessage", "id": "message-\(index)", "phase": "final_answer", "text": text]
        ])
        emit(index, method: "turn/completed", params: [
            "threadId": "thread-\(index)", "turn": ["id": "turn-\(index)", "status": "completed"]
        ])
    }
}
