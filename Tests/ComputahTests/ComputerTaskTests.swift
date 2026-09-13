import XCTest
import AppKit
@testable import Computah

final class ComputerTaskTests: XCTestCase {
    @MainActor
    func testConcurrentTasksFinishCancelAndAnswerQuestionIndependently() async throws {
        _ = NSApplication.shared
        let peer = ComputerTaskTestPeer()
        let manager = peer.manager()
        let voiceID = UUID()
        var callbacks: [UUID: Int] = [:]
        var reviewed: [UUID: String] = [:]
        var questions: [UUID: CodexQuestionRequest] = [:]
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
            XCTAssertEqual(session.voiceSessionID, voiceID)
        }
        manager.onQuestion = { session, request in
            questions[session.id] = request
            XCTAssertEqual(session.voiceSessionID, voiceID)
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
        XCTAssertFalse(first.worker === third.worker)
        XCTAssertEqual(first.delegationIDs, ["first-delegation"])
        XCTAssertEqual(second.delegationIDs, ["second-delegation"])
        XCTAssertEqual(third.delegationIDs, ["third-delegation"])

        // A completion from another task cannot terminate this worker.
        peer.emit(0, method: "turn/completed", params: ["threadId": "thread-2", "turn": ["id": "turn-2", "status": "completed"]])
        XCTAssertEqual(first.state, .working)
        second.stop()
        second.stop()
        XCTAssertEqual(second.state, .cancelled)
        XCTAssertTrue(first.worker.running)
        XCTAssertTrue(third.worker.running)
        XCTAssertEqual(callbacks[second.id], 1)

        first.addDelegations(["late-first-delegation"])
        peer.finish(0, text: "First job researched.")
        try await waitUntil { first.state == .completed }
        XCTAssertEqual(first.result, "First job researched.")
        XCTAssertEqual(third.state, .working)
        XCTAssertTrue(third.worker.running)

        peer.requestQuestions(2)
        try await waitUntil { third.pendingQuestions.count == 1 }
        XCTAssertEqual(callbacks[first.id], 1)
        XCTAssertNil(reviewed[third.id])
        XCTAssertEqual(third.state, .working)
        XCTAssertTrue(third.worker.running)
        let request = try XCTUnwrap(questions[third.id])
        XCTAssertEqual(request.id, "s:questions-rpc-2")
        XCTAssertEqual(request.itemID, "questions-2")
        XCTAssertEqual(request.questions.map(\.id), ["school", "account"])
        XCTAssertEqual(request.questions[0].options.map(\.label), ["UCLA", "Berkeley"])
        XCTAssertTrue(request.questions[0].allowsOther)
        XCTAssertTrue(request.questions[1].isSecret)
        try third.answerPendingQuestion(requestID: request.id, answers: [
            "school": ["UCLA"],
            "account": ["private answer"]
        ])
        XCTAssertTrue(third.pendingQuestions.isEmpty)
        XCTAssertEqual(third.state, .working)
        XCTAssertTrue(third.worker.running)
        peer.finish(2, text: "Third job finished after the answer.")
        try await waitUntil { third.state == .completed }
        XCTAssertEqual(third.result, "Third job finished after the answer.")
        XCTAssertEqual(callbackDelegations[first.id], ["first-delegation", "late-first-delegation"])
        XCTAssertEqual(callbackDelegations[second.id], ["second-delegation"])
        XCTAssertEqual(callbackDelegations[third.id], ["third-delegation"])
        XCTAssertEqual(first.delegationIDs, ["first-delegation", "late-first-delegation"])
        XCTAssertEqual(callbacks[first.id], 1)

        manager.stopAll()
        XCTAssertEqual(first.state, .completed)
        XCTAssertEqual(first.result, "First job researched.")
        XCTAssertEqual(third.state, .completed)
        XCTAssertEqual(third.result, "Third job finished after the answer.")
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
    func testNativeAppApprovalKeepsSessionActiveAndCompletionStillWins() async throws {
        _ = NSApplication.shared
        let peer = ComputerTaskTestPeer()
        let manager = peer.manager()
        var reviews = 0
        var results = 0
        manager.onReview = { _, _ in reviews += 1 }
        manager.onResult = { _, _ in results += 1 }
        let session = manager.start(task: "Read Calculator", context: "", apiKey: "voice-key-is-not-worker-auth")
        defer { manager.stopAll() }
        try await waitUntil { session.state == .working }
        peer.requestAppApproval(0, message: "Allow Calculator for this task?")
        try await waitUntil { session.state == .review }
        XCTAssertTrue(session.worker.running)
        XCTAssertTrue(session.approvalPending)
        XCTAssertTrue(session.approvalCanBeAccepted)
        XCTAssertEqual(reviews, 1)
        XCTAssertEqual(results, 0)
        try session.allowPendingApproval()
        XCTAssertEqual(session.state, .working)
        XCTAssertTrue(session.worker.running)
        peer.finish(0, text: "Calculator is visible.")
        try await waitUntil { session.state == .completed }
        XCTAssertEqual(session.result, "Calculator is visible.")
        XCTAssertEqual(results, 1)
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
            return CodexWorker(browser: browser, resolveExecutable: { URL(fileURLWithPath: "/bin/sh") }, rpcFactory: { _, _, environment, directory in
                let script = """
                IFS= read -r fixture_line
                printf '%s\\n' '{"id":1,"result":{}}'
                IFS= read -r fixture_line
                IFS= read -r fixture_line
                printf '%s\\n' '{"id":2,"result":{"model":"gpt-5.6-sol","modelProvider":"openai","thread":{"id":"thread-\(index)"}}}'
                IFS= read -r fixture_line
                printf '%s\\n' '{"method":"turn/started","params":{"threadId":"thread-\(index)","turn":{"id":"turn-\(index)"}}}'
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

    func requestQuestions(_ index: Int) {
        emit(index, method: "item/tool/requestUserInput", id: "questions-rpc-\(index)", params: [
            "threadId": "thread-\(index)", "turnId": "turn-\(index)", "itemId": "questions-\(index)",
            "isBlocking": true,
            "questions": [
                [
                    "header": "School", "id": "school", "question": "Which school should I use?",
                    "options": [
                        ["label": "UCLA", "description": "Use the UCLA application."],
                        ["label": "Berkeley", "description": "Use the Berkeley application."]
                    ],
                    "isOther": true, "isSecret": false
                ],
                [
                    "header": "Account", "id": "account", "question": "Enter the private account detail.",
                    "options": [], "isOther": false, "isSecret": true
                ]
            ]
        ])
    }

    func requestAppApproval(_ index: Int, message: String) {
        emit(index, method: "mcpServer/elicitation/request", id: "approval-rpc-\(index)", params: [
            "threadId": "thread-\(index)", "turnId": "turn-\(index)", "serverName": "computer-use",
            "mode": "form", "message": message,
            "requestedSchema": ["type": "object", "properties": [:], "required": []],
            "_meta": ["codex_approval_kind": "mcp_tool_call"]
        ])
    }
}
