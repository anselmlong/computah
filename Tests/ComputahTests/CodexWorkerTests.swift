import XCTest
import AppKit
@testable import Computah

final class CodexWorkerTests: XCTestCase {
    func testExecutableDiscoveryWithFinderPathAndUserInstall() {
        let expected = "/Users/test/.local/bin/codex"
        let result = CodexExecutable.resolve(environment: ["PATH": "/usr/bin:/bin"],
                                             home: URL(fileURLWithPath: "/Users/test"),
                                             isExecutable: { $0 == expected })
        XCTAssertEqual(result?.path, expected)
    }

    func testExecutableDiscoveryUsesPathAndFallsBackToHomebrew() {
        for expected in ["/custom/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"] {
            let result = CodexExecutable.resolve(environment: ["PATH": "/custom/bin:/usr/bin"],
                                                 isExecutable: { $0 == expected })
            XCTAssertEqual(result?.path, expected)
        }
    }

    func testExecutableDiscoveryRejectsRelativePathsAndMissingExecutables() {
        XCTAssertNil(CodexExecutable.resolve(environment: ["PATH": ":.:relative/bin"],
                                              isExecutable: { !$0.hasPrefix("/") }))
        XCTAssertNil(CodexExecutable.resolve(isExecutable: { _ in false }))
    }

    func testWorkerConfigurationUsesNormalCodexHomeAndRemovesParentTaskIdentity() throws {
        let directory = URL(fileURLWithPath: "/Users/tester")
        let environment = CodexWorkerProtocol.environment(from: [
            "HOME": directory.path, "CODEX_HOME": "/Users/tester/.codex",
            "HTTP_PROXY": "http://localhost:8080", "CODEX_THREAD_ID": "parent",
            "CODEX_INTERNAL_ORIGINATOR_OVERRIDE": "parent-origin", "CODEX_ENGINE_STATE": "private",
            "OPENAI_API_KEY": "not-for-the-worker", "PATH": "/usr/bin"
        ])
        XCTAssertEqual(environment["HOME"], directory.path)
        XCTAssertEqual(environment["CODEX_HOME"], "/Users/tester/.codex")
        XCTAssertNil(environment["CODEX_THREAD_ID"])
        XCTAssertNil(environment["CODEX_INTERNAL_ORIGINATOR_OVERRIDE"])
        XCTAssertNil(environment["CODEX_ENGINE_STATE"])
        XCTAssertNil(environment["OPENAI_API_KEY"])
        XCTAssertEqual(environment["HTTP_PROXY"], "http://localhost:8080")
        XCTAssertEqual(CodexWorkerProtocol.arguments, [
            "app-server", "--enable", "default_mode_request_user_input", "--listen", "stdio://"
        ])
        let thread = CodexWorkerProtocol.thread(directory: directory)
        XCTAssertEqual(thread["model"] as? String, "gpt-5.6-sol")
        XCTAssertEqual(thread["allowProviderModelFallback"] as? Bool, false)
        XCTAssertEqual(thread["approvalPolicy"] as? String, "never")
        XCTAssertEqual(thread["sandbox"] as? String, "danger-full-access")
        XCTAssertEqual(thread["ephemeral"] as? Bool, true)
        XCTAssertNil(thread["modelProvider"])
        XCTAssertNil(thread["dynamicTools"])
        XCTAssertNil(thread["environments"])
        let turn = CodexWorkerProtocol.turn(threadID: "t", task: "x", context: "y")
        XCTAssertEqual(turn["model"] as? String, "gpt-5.6-sol")
        XCTAssertEqual(turn["effort"] as? String, "high")
        XCTAssertNil(turn["environments"])
        let instructions = try XCTUnwrap(thread["baseInstructions"] as? String)
        XCTAssertTrue(instructions.contains("Never submit, send, pay, publish, accept terms, or finalize"))
        XCTAssertTrue(instructions.contains("clear confirmation question with explicit choices"))
        XCTAssertTrue(instructions.contains("through request_user_input"))
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: thread))
    }

    func testApprovalRequestsBecomeActionableSummariesWithoutCapturingQuestions() {
        XCTAssertNil(CodexWorkerProtocol.reviewSummary(method: "item/tool/requestUserInput", params: [
            "questions": [["question": "Review the prepared form before submission."]]
        ]))
        XCTAssertEqual(CodexWorkerProtocol.reviewSummary(
            method: "mcpServer/elicitation/request",
            params: ["message": "Allow Calculator for this task?"]
        ), "Allow Calculator for this task?")
        XCTAssertEqual(CodexWorkerProtocol.reviewSummary(
            method: "item/permissions/requestApproval",
            params: ["reason": "Codex needs network access to the university site."]
        ), "Codex needs network access to the university site.")
        XCTAssertEqual(CodexWorkerProtocol.reviewSummary(
            method: "item/commandExecution/requestApproval", params: [:]
        ), "Codex is waiting for approval to run a command.")
        XCTAssertNil(CodexWorkerProtocol.reviewSummary(method: "unexpectedTool", params: [:]))
    }

    func testQuestionResponseUsesCodexRequestUserInputShape() throws {
        let response = CodexWorkerProtocol.questionResponse(answers: [
            "program": ["Computer science"],
            "confirm": ["Yes, submit it"]
        ])
        let data = try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
        XCTAssertEqual(String(decoding: data, as: UTF8.self),
                       #"{"answers":{"confirm":{"answers":["Yes, submit it"]},"program":{"answers":["Computer science"]}}}"#)
    }

    @MainActor
    func testFramingHandlesSplitUnicodeAndMultipleMessages() throws {
        let rpc = makeIdleRPC()
        var values: [String] = []
        rpc.onMessage = { values.append($0["method"] as? String ?? "") }
        let frames = Data("{\"method\":\"消息\"}\n{\"method\":\"second\"}\n".utf8)
        for byte in frames { rpc.receive(Data([byte])) }
        XCTAssertEqual(values, ["消息", "second"])
        rpc.close()
    }

    @MainActor
    func testInvalidAndOversizedFramesFailWithoutDisplayingPayload() {
        for frame in [Data("secret-key-is-not-json\n".utf8), Data(repeating: 65, count: CodexRPC.maximumFrameBytes + 1)] {
            let rpc = makeIdleRPC()
            var failure: String?
            rpc.onFailure = { failure = $0.localizedDescription }
            rpc.receive(frame)
            XCTAssertNotNil(failure)
            XCTAssertFalse(failure?.contains("secret-key") ?? true)
        }
    }

    @MainActor
    func testPendingRequestsFailOnShutdownAndTimeout() async throws {
        let rpc = makeIdleRPC()
        try rpc.launch()
        let pending = Task { try await rpc.request("neverResponds", params: [:], timeout: 5) }
        await Task.yield()
        rpc.close()
        do { _ = try await pending.value; XCTFail("Shutdown must fail a pending request") }
        catch { }

        let timed = makeIdleRPC()
        try timed.launch()
        defer { timed.close() }
        do { _ = try await timed.request("neverResponds", params: [:], timeout: 0.03); XCTFail("Request must time out") }
        catch { XCTAssertTrue(error.localizedDescription.contains("in time")) }
    }

    @MainActor
    func testClosingRPCNeverDeletesItsWorkingDirectory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("computah-cwd-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sentinel = directory.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sentinel)
        let rpc = CodexRPC(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [],
                           environment: ["PATH": "/usr/bin:/bin"], directory: directory)
        try rpc.launch()
        rpc.close()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
    }

    @MainActor
    func testRequestCancellationAndLateReplyDoNotResolveAnotherRequest() async throws {
        let rpc = makeIdleRPC()
        try rpc.launch()
        defer { rpc.close() }
        let canceled = Task { try await rpc.request("one", params: [:]) }
        await Task.yield()
        canceled.cancel()
        do { _ = try await canceled.value; XCTFail("Cancellation must end the request") }
        catch { XCTAssertTrue(error is CancellationError) }
        rpc.receive(Data("{\"id\":1,\"result\":{\"stale\":true}}\n".utf8))
        let next = Task { try await rpc.request("two", params: [:]) }
        await Task.yield()
        rpc.receive(Data("{\"id\":2,\"result\":{\"ok\":true}}\n".utf8))
        let result = try await next.value
        XCTAssertEqual(result["ok"] as? Bool, true)
        XCTAssertNil(result["stale"])
    }

    @MainActor
    func testInstalledCodexHandshakeUsesNormalUserConfigurationWithoutModelCall() async throws {
        guard let executable = CodexExecutable.resolve() else { throw XCTSkip("Codex CLI is not installed") }
        let environment = CodexWorkerProtocol.environment()
        let directory = URL(fileURLWithPath: environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path)
        let rpc = CodexRPC(executable: executable, arguments: CodexWorkerProtocol.arguments,
                           environment: environment, directory: directory)
        defer { rpc.close() }
        try rpc.launch()
        _ = try await rpc.request("initialize", params: CodexWorkerProtocol.initialize)
        try rpc.notify("initialized")
        let started = try await rpc.request("thread/start", params: CodexWorkerProtocol.thread(directory: directory))
        XCTAssertEqual(started["model"] as? String, CodexWorkerProtocol.model)
        XCTAssertNotNil((started["thread"] as? [String: Any])?["id"] as? String)
    }

    @MainActor
    func testImmediateCompletionWhileTurnStartIsPendingReportsExactlyOnce() async throws {
        _ = NSApplication.shared
        let worker = fakeWorker(events: [
            #"{"method":"turn/started","params":{"threadId":"thread-test","turn":{"id":"turn-test"}}}"#,
            #"{"method":"item/agentMessage/delta","params":{"threadId":"thread-test","turnId":"turn-test","itemId":"message-test","delta":"Prepared the page."}}"#,
            #"{"method":"item/completed","params":{"threadId":"thread-test","turnId":"turn-test","item":{"type":"agentMessage","id":"message-test","phase":"final_answer","text":"Prepared the page."}}}"#,
            #"{"method":"turn/completed","params":{"threadId":"thread-test","turn":{"id":"turn-test","status":"completed"}}}"#
        ])
        var results: [String] = []
        worker.onResult = { results.append($0) }
        try await worker.start(task: "prepare a page", context: "test", apiKey: "dummy-no-real-credentials")
        XCTAssertEqual(results, ["Prepared the page."])
        XCTAssertEqual(worker.result, "Prepared the page.")
        XCTAssertFalse(worker.running)
        XCTAssertEqual(worker.status, "Finished")
    }

    @MainActor
    func testStructuredQuestionsWaitForExplicitVoiceAnswersAndResumeSameTask() async throws {
        _ = NSApplication.shared
        let worker = fakeWorker(events: [
            #"{"method":"turn/started","params":{"threadId":"thread-test","turn":{"id":"turn-test"}}}"#,
            #"{"method":"item/tool/requestUserInput","id":"tool-rpc","params":{"threadId":"thread-test","turnId":"turn-test","itemId":"question-call","isBlocking":true,"questions":[{"header":"Program","id":"program","question":"Which program should I use?","options":[{"label":"Computer science","description":"Use the computer science program."}],"isOther":true,"isSecret":false},{"header":"Submit","id":"confirm","question":"Should I submit the completed application?","options":[{"label":"Yes","description":"Submit it now."},{"label":"No","description":"Leave it prepared."}],"isOther":false,"isSecret":false}]}}"#
        ], respondBeforeEvents: true, afterResponseEvents: [
            #"{"method":"item/completed","params":{"threadId":"thread-test","turnId":"turn-test","item":{"type":"agentMessage","id":"answer","phase":"final_answer","text":"Submitted after receiving your answer."}}}"#,
            #"{"method":"turn/completed","params":{"threadId":"thread-test","turn":{"id":"turn-test","status":"completed"}}}"#
        ])
        var questions: [CodexQuestionRequest] = []
        var reviews: [String] = []
        var results: [String] = []
        worker.onQuestion = { questions.append($0) }
        worker.onReview = { reviews.append($0) }
        worker.onResult = { results.append($0) }
        try await worker.start(task: "prepare application", context: "test", apiKey: "dummy-no-real-credentials")
        for _ in 0..<50 where worker.pendingQuestion == nil { await Task.yield() }

        XCTAssertTrue(worker.running)
        XCTAssertFalse(worker.reviewRequested)
        XCTAssertFalse(worker.approvalPending)
        XCTAssertEqual(worker.status, "Waiting for your voice answer")
        XCTAssertEqual(questions.count, 1)
        let request = try XCTUnwrap(worker.pendingQuestion)
        XCTAssertEqual(request.id, "s:tool-rpc")
        XCTAssertEqual(request.itemID, "question-call")
        XCTAssertEqual(request.questions.map(\.id), ["program", "confirm"])
        XCTAssertEqual(request.questions[0].header, "Program")
        XCTAssertEqual(request.questions[0].prompt, "Which program should I use?")
        XCTAssertEqual(request.questions[0].options,
                       [CodexQuestionOption(label: "Computer science", description: "Use the computer science program.")])
        XCTAssertTrue(request.questions[0].allowsOther)
        XCTAssertFalse(request.questions[0].isSecret)
        XCTAssertEqual(request.questions[1].options.map(\.label), ["Yes", "No"])
        XCTAssertEqual(reviews, [])

        XCTAssertNoThrow(try worker.answerPendingQuestion(
            requestID: request.id, questionID: "program", answer: "Computer science"
        ))
        XCTAssertNotNil(worker.pendingQuestion)
        XCTAssertEqual(worker.result, "Should I submit the completed application?")
        XCTAssertThrowsError(try worker.answerPendingQuestion(
            requestID: request.id, questionID: "program", answer: "A different program"
        ))
        XCTAssertThrowsError(try worker.answerPendingQuestion(
            requestID: "s:another-task", answers: ["program": ["Computer science"], "confirm": ["Yes"]]
        ))
        XCTAssertNotNil(worker.pendingQuestion)

        try worker.answerPendingQuestion(requestID: request.id, questionID: "confirm", answer: "Yes, submit it")
        for _ in 0..<50 where worker.running { await Task.yield() }
        XCTAssertNil(worker.pendingQuestion)
        XCTAssertFalse(worker.running)
        XCTAssertEqual(worker.status, "Finished")
        XCTAssertEqual(results, ["Submitted after receiving your answer."])
    }

    @MainActor
    func testConcurrentWorkersKeepQuestionRequestIDsAndAnswersIsolated() async throws {
        _ = NSApplication.shared
        let event = #"{"method":"item/tool/requestUserInput","id":7,"params":{"threadId":"thread-test","itemId":"question-call","questions":[{"header":"Choice","id":"choice","question":"Which option?","options":[],"isOther":true,"isSecret":false}]}}"#
        let first = fakeWorker(events: [event], respondBeforeEvents: true)
        let second = fakeWorker(events: [event], respondBeforeEvents: true)
        try await first.start(task: "first task", context: "", apiKey: "")
        try await second.start(task: "second task", context: "", apiKey: "")
        for _ in 0..<50 where first.pendingQuestion == nil || second.pendingQuestion == nil { await Task.yield() }

        XCTAssertEqual(first.pendingQuestion?.id, "n:7")
        XCTAssertEqual(second.pendingQuestion?.id, "n:7")
        try first.answerPendingQuestion(requestID: "n:7", questionID: "choice", answer: "First option")
        XCTAssertNil(first.pendingQuestion)
        XCTAssertNotNil(second.pendingQuestion)
        XCTAssertThrowsError(try second.answerPendingQuestion(
            requestID: "n:7", questionID: "different-question", answer: "Second option"
        ))
        XCTAssertNotNil(second.pendingQuestion)
        first.stop()
        second.stop()
    }

    @MainActor
    func testLiveWebSearchDoesNotStopNormalWorker() async throws {
        _ = NSApplication.shared
        let worker = fakeWorker(events: [
            #"{"method":"turn/started","params":{"threadId":"thread-test","turn":{"id":"turn-test"}}}"#,
            #"{"method":"item/started","params":{"threadId":"thread-test","turnId":"turn-test","item":{"type":"webSearch","id":"search"}}}"#,
            #"{"method":"item/completed","params":{"threadId":"thread-test","turnId":"turn-test","item":{"type":"webSearch","id":"search"}}}"#,
            #"{"method":"item/completed","params":{"threadId":"thread-test","turnId":"turn-test","item":{"type":"agentMessage","id":"answer","phase":"final_answer","text":"Found the official program."}}}"#,
            #"{"method":"turn/completed","params":{"threadId":"thread-test","turn":{"id":"turn-test","status":"completed"}}}"#
        ])
        try await worker.start(task: "find official program", context: "", apiKey: "")
        XCTAssertEqual(worker.status, "Finished")
        XCTAssertEqual(worker.result, "Found the official program.")
    }

    @MainActor
    func testNativeAppApprovalKeepsWorkerAliveAndCanResume() async throws {
        _ = NSApplication.shared
        let worker = fakeWorker(events: [
            #"{"method":"turn/started","params":{"threadId":"thread-test","turn":{"id":"turn-test"}}}"#,
            #"{"method":"mcpServer/elicitation/request","id":"approval-rpc","params":{"threadId":"thread-test","turnId":"turn-test","serverName":"computer-use","mode":"form","message":"Allow Calculator for this task?","requestedSchema":{"type":"object","properties":{},"required":[]},"_meta":{"codex_approval_kind":"mcp_tool_call"}}}"#
        ], respondBeforeEvents: true)
        var reviews: [String] = []
        worker.onReview = { reviews.append($0) }
        try await worker.start(task: "read Calculator", context: "test", apiKey: "")
        for _ in 0..<50 where !worker.approvalPending { await Task.yield() }
        XCTAssertTrue(worker.running)
        XCTAssertTrue(worker.approvalPending)
        XCTAssertTrue(worker.approvalCanBeAccepted)
        XCTAssertEqual(reviews, ["Allow Calculator for this task?"])
        try worker.approvePendingReview()
        XCTAssertTrue(worker.running)
        XCTAssertFalse(worker.approvalPending)
        XCTAssertEqual(worker.status, "Working with Codex")
        worker.stop()
    }

    @MainActor
    func testNativeToolEventsRemainOwnedByCodex() async throws {
        _ = NSApplication.shared
        let worker = fakeWorker(events: [
            #"{"method":"turn/started","params":{"threadId":"thread-test","turn":{"id":"turn-test"}}}"#,
            #"{"method":"item/started","params":{"threadId":"thread-test","turnId":"turn-test","item":{"type":"commandExecution","id":"forbidden"}}}"#
        ], respondBeforeEvents: true)
        var results: [String] = []
        worker.onResult = { results.append($0) }
        try await worker.start(task: "test", context: "test", apiKey: "dummy-no-real-credentials")
        XCTAssertTrue(worker.running)
        XCTAssertEqual(worker.status, "Working with Codex")
        XCTAssertEqual(results.count, 0)
        worker.stop()
    }

    @MainActor
    func testUnknownOrMissingCompletionStatusCannotReportSuccess() async throws {
        _ = NSApplication.shared
        for status in [",\"status\":\"unexpected\"", ""] {
            let worker = fakeWorker(events: [
                #"{"method":"turn/started","params":{"threadId":"thread-test","turn":{"id":"turn-test"}}}"#,
                "{\"method\":\"turn/completed\",\"params\":{\"threadId\":\"thread-test\",\"turn\":{\"id\":\"turn-test\"\(status)}}}"
            ])
            var results: [String] = []
            worker.onResult = { results.append($0) }
            try await worker.start(task: "test", context: "", apiKey: "dummy-no-real-credentials")
            XCTAssertFalse(worker.running)
            XCTAssertEqual(worker.status, "Worker unavailable")
            XCTAssertEqual(results.count, 1)
            XCTAssertTrue(worker.result.contains("unrecognized task status"))
        }
    }

    @MainActor
    private func fakeWorker(events: [String], respondBeforeEvents: Bool = false,
                            afterResponseEvents: [String] = []) -> CodexWorker {
        // A deterministic subprocess speaks JSON-RPC without any model or network request.
        let eventPrints = events.map { "printf '%s\\n' '" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: "\n")
        let afterResponsePrints = afterResponseEvents.map {
            "printf '%s\\n' '" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }.joined(separator: "\n")
        let turnResponse = "printf '%s\\n' '{\"id\":3,\"result\":{\"turn\":{\"id\":\"turn-test\"}}}'"
        let turnExchange = respondBeforeEvents ? "\(turnResponse)\n\(eventPrints)" : "\(eventPrints)"
        let responseExchange = afterResponseEvents.isEmpty ? "" : "IFS= read -r fixture_line\n\(afterResponsePrints)"
        let script = """
        IFS= read -r fixture_line
        printf '%s\\n' '{"id":1,"result":{}}'
        IFS= read -r fixture_line
        IFS= read -r fixture_line
        printf '%s\\n' '{"id":2,"result":{"model":"gpt-5.6-sol","modelProvider":"openai","thread":{"id":"thread-test"}}}'
        IFS= read -r fixture_line
        \(turnExchange)
        \(responseExchange)
        while IFS= read -r fixture_line; do :; done
        """
        return CodexWorker(browser: BrowserWorkspace(transport: TestBrowserTransport()),
                           resolveExecutable: { URL(fileURLWithPath: "/bin/sh") },
                           rpcFactory: { _, _, environment, directory in
            CodexRPC(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script], environment: environment, directory: directory)
        })
    }

    @MainActor
    private func makeIdleRPC() -> CodexRPC {
        CodexRPC(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [], environment: ["PATH": "/usr/bin:/bin"])
    }
}
